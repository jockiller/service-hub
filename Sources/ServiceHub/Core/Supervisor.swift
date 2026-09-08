import Foundation
import SwiftUI

public struct ServiceRuntimeInfo {
    public var status: ServiceStatus = .unknown
    public var pid: pid_t? = nil
    public var uptime: String? = nil

    public init(status: ServiceStatus = .unknown, pid: pid_t? = nil, uptime: String? = nil) {
        self.status = status
        self.pid = pid
        self.uptime = uptime
    }
}

@MainActor
public final class Supervisor: ObservableObject {
    public static let shared = Supervisor()

    @Published public var statuses: [String: ServiceStatus] = [:]
    @Published public var runtimes: [String: ServiceRuntimeInfo] = [:]
    @Published public var isBusy: [String: Bool] = [:]
    @Published public var lastOutputs: [String: String] = [:]

    private var probeTimer: Timer?
    /// 应用启动拉起只执行一次（主窗口重复出现时不重复拉起）
    private var hasLaunchedAtStartup = false
    /// 记录各服务在短时间内的自动重启尝试时间戳，用于滑动时间窗口熔断
    private var restartTimestamps: [String: [Date]] = [:]
    /// 记录各服务是否已被熔断暂停保活
    @Published public var isCircuitBroken: [String: Bool] = [:]
    /// 健康检查(HTTP)连续失败计数（即使进程仍被判活），达到阈值后强制重启
    @Published public var healthCheckFailCounts: [String: Int] = [:]
    /// 正在执行健康检查强制重启的服务（防重入）
    private var forceRestarting: Set<String> = []

    public init() {
        startProbeLoop()
    }

    /// 启动定时后台探测循环
    public func startProbeLoop() {
        probeTimer?.invalidate()
        probeTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.triggerProbeAll()
            }
        }
        // 延迟 0.3 秒触发首次检测，避免阻塞窗口首帧启动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.triggerProbeAll()
        }
    }

    /// 对所有已登记服务执行探活
    public func probeAllServices() async {
        triggerProbeAll()
    }

    /// 异步执行服务探活
    public func triggerProbeAll() {
        let services = ServiceStore.shared.services
        Task { [weak self] in
            for s in services {
                let probeRes = await HealthProbe.probe(service: s)
                self?.applyProbeResult(probeRes, for: s)
            }
        }
    }

    private func applyProbeResult(_ res: ProbeResult, for service: Service) {
        if res.status != .unknown {
            let prevStatus = self.statuses[service.id]
            self.statuses[service.id] = res.status
            self.runtimes[service.id] = ServiceRuntimeInfo(
                status: res.status,
                pid: res.status == .running ? res.pid : nil,
                uptime: res.status == .running ? res.uptimeString : nil
            )

            // 如果当前正处于“等待前置条件”，检查条件是否已恢复满足
            if self.statuses[service.id] == .waitingPrecondition && service.autoStart {
                Task {
                    let preCheck = await PreconditionChecker.check(service: service)
                    if preCheck.isSatisfied {
                        print("[Supervisor] 服务 \(service.name) 前置条件已满足，正在自动启动...")
                        await startService(service)
                    }
                }
            }

            // 如果服务配置了自启动，但发现停止了，且之前不是手动停止
            if service.autoStart && res.status == .stopped && prevStatus == .running {
                // 检查是否已被熔断暂停
                if isCircuitBroken[service.id] == true {
                    self.statuses[service.id] = .failed
                    self.runtimes[service.id]?.status = .failed
                    return
                }

                let now = Date()
                let window = TimeInterval(service.restartWindowSeconds)
                var history = restartTimestamps[service.id, default: []].filter { now.timeIntervalSince($0) <= window }

                if history.count >= service.maxRestarts {
                    // 触发熔断保护：在指定时间窗口内连续失败达到上限，暂停自动保活
                    isCircuitBroken[service.id] = true
                    self.statuses[service.id] = .failed
                    let failReason = L("已熔断: \(service.restartWindowSeconds)s内失败\(history.count)次，已停保活", "Circuit broken: \(history.count) failures within \(service.restartWindowSeconds)s; keep-alive paused")
                    self.runtimes[service.id] = ServiceRuntimeInfo(
                        status: .failed,
                        pid: nil,
                        uptime: failReason
                    )
                    lastOutputs[service.id] = L("服务在 \(service.restartWindowSeconds) 秒内连续重启达到 \(service.maxRestarts) 次上限，已暂停自动保活保护系统。请排查原因后手动点击启动恢复。", "Service restarted \(service.maxRestarts) time(s) within \(service.restartWindowSeconds)s; auto keep-alive paused. Investigate and start manually to resume.")
                    print("[-] [Supervisor] 服务 \(service.name) \(failReason)")
                } else {
                    history.append(now)
                    restartTimestamps[service.id] = history
                    print("[Supervisor] 检测到服务 \(service.name) 异常退出，正在自动重拉 (\(service.restartWindowSeconds)s内第 \(history.count)/\(service.maxRestarts) 次)...")
                    Task {
                        await startService(service)
                    }
                }
            } else if res.status == .running {
                // 运行正常，恢复重试计数与熔断状态
                restartTimestamps[service.id] = []
                isCircuitBroken[service.id] = false

                // 健康检查失败 N 次强制重启：进程仍在（statusCommand 判活）但 HTTP 探活连续失败
                // 强制重启同样计入滑动窗口熔断，防止"进程活着但不健康"时无限重启循环
                if let threshold = service.healthCheckRestartThreshold, threshold > 0,
                   service.healthCheckURL != nil {
                    if res.httpHealthCheckFailed {
                        // 已被熔断：不再强制重启，等手动恢复
                        if isCircuitBroken[service.id] == true {
                            self.statuses[service.id] = .failed
                            self.runtimes[service.id]?.status = .failed
                            return
                        }

                        let count = (healthCheckFailCounts[service.id] ?? 0) + 1
                        healthCheckFailCounts[service.id] = count
                        if count >= threshold && !forceRestarting.contains(service.id) {
                            // 检查熔断窗口：强制重启与崩溃重拉共用同一窗口
                            let now = Date()
                            let window = TimeInterval(service.restartWindowSeconds)
                            var history = restartTimestamps[service.id, default: []].filter { now.timeIntervalSince($0) <= window }
                            if history.count >= service.maxRestarts {
                                isCircuitBroken[service.id] = true
                                self.statuses[service.id] = .failed
                                healthCheckFailCounts[service.id] = 0
                                let failReason = L("健康检查强制重启已熔断: \(service.restartWindowSeconds)s内重启\(history.count)次仍不健康，已停自动重启", "Health-restart circuit broken: \(history.count) restarts within \(service.restartWindowSeconds)s still unhealthy; auto restart paused")
                                self.runtimes[service.id] = ServiceRuntimeInfo(
                                    status: .failed,
                                    pid: nil,
                                    uptime: failReason
                                )
                                lastOutputs[service.id] = L("服务在 \(service.restartWindowSeconds) 秒内因健康检查失败被强制重启 \(history.count) 次仍未恢复，已暂停自动重启保护系统。请排查原因后手动处理。", "Service was force-restarted \(history.count) time(s) within \(service.restartWindowSeconds)s due to health failures without recovery; auto restart paused. Investigate and handle manually.")
                                print("[-] [Supervisor] 服务 \(service.name) \(failReason)")
                                return
                            }

                            print("[Supervisor] 服务 \(service.name) 健康检查连续失败 \(count)/\(threshold) 次，进程虽在运行仍执行强制重启...")
                            lastOutputs[service.id] = L("健康检查连续失败 \(count) 次 (阈值 \(threshold))，进程仍在运行但强制重启以恢复健康状态。", "Health check failed \(count) time(s) in a row (threshold \(threshold)); process still alive but forcing restart to restore health.")
                            history.append(now)
                            restartTimestamps[service.id] = history
                            forceRestarting.insert(service.id)
                            healthCheckFailCounts[service.id] = 0
                            Task { [weak self] in
                                await self?.restartService(service)
                                self?.forceRestarting.remove(service.id)
                            }
                        } else {
                            print("[Supervisor] 服务 \(service.name) 健康检查失败 \(count)/\(threshold) 次")
                        }
                    } else {
                        // 探活恢复正常，清零计数
                        if let c = healthCheckFailCounts[service.id], c != 0 {
                            print("[Supervisor] 服务 \(service.name) 健康检查恢复正常，失败计数清零")
                        }
                        healthCheckFailCounts[service.id] = 0
                    }
                }
            }
        }
    }

    /// 应用启动时：拉起所有勾选「随 ServiceHub 启动」的服务（跳过未勾选的，保持手动管理）
    /// 已在运行中的服务自动跳过，避免重复执行 start 命令
    public func launchServicesAtStartup() {
        guard !hasLaunchedAtStartup else { return }
        hasLaunchedAtStartup = true
        let services = ServiceStore.shared.services
        let toLaunch = services.filter { $0.launchOnAppStart }
        guard !toLaunch.isEmpty else { return }
        Task { [weak self] in
            for s in toLaunch {
                // 先探测当前实际状态，已运行的不再重复启动
                let probeRes = await HealthProbe.probe(service: s)
                if probeRes.status == .running {
                    print("[Supervisor] 服务 \(s.name) 已在运行，跳过启动拉起")
                    self?.applyProbeResult(probeRes, for: s)
                    continue
                }
                print("[Supervisor] 应用启动：自动拉起 \(s.name)")
                await self?.startService(s)
            }
        }
    }

    /// 启动单个服务
    public func startService(_ service: Service) async {
        isBusy[service.id] = true

        // 用户主动或触发启动时，解除该服务的熔断标记
        isCircuitBroken[service.id] = false

        // 1. 启动前先检查前置条件（如：是否已连入外网/Wi-Fi）
        let preCheck = await PreconditionChecker.check(service: service)
        if !preCheck.isSatisfied {
            print("[Supervisor] 服务 \(service.name) 启动前置条件未满足: \(preCheck.reason)")
            statuses[service.id] = .waitingPrecondition
            runtimes[service.id] = ServiceRuntimeInfo(
                status: .waitingPrecondition,
                pid: nil,
                uptime: preCheck.reason
            )
            lastOutputs[service.id] = L("等待前置条件: \(preCheck.reason)", "Waiting for precondition: \(preCheck.reason)")
            isBusy[service.id] = false
            return
        }

        statuses[service.id] = .starting
        runtimes[service.id]?.status = .starting

        let result = await ProcessRunner.run(command: service.startCommand, timeout: 30)
        lastOutputs[service.id] = result.output

        // 启动后等待 1 秒，让进程稳定，然后探活
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let probeRes = await HealthProbe.probe(service: service)
        let finalStatus = (probeRes.status == .unknown ? (result.isSuccess ? .running : .failed) : probeRes.status)
        statuses[service.id] = finalStatus
        runtimes[service.id] = ServiceRuntimeInfo(
            status: finalStatus,
            pid: finalStatus == .running ? probeRes.pid : nil,
            uptime: finalStatus == .running ? probeRes.uptimeString : nil
        )

        // 启动成功后，若勾选了“启动后打开主页”，自动调用默认浏览器打开
        if finalStatus == .running, service.openWebURLOnStart,
           let webURLStr = service.webURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !webURLStr.isEmpty,
           let url = URL(string: webURLStr) {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }

        // 若服务配置了公网穿透并自启，启动成功后联动拉起隧道
        if finalStatus == .running, service.tunnelConfig?.enabled == true {
            CloudflareTunnelManager.shared.startTunnel(for: service)
        }

        isBusy[service.id] = false
    }

    /// 停止单个服务
    public func stopService(_ service: Service) async {
        guard let stopCmd = service.stopCommand, !stopCmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[-] 服务 \(service.name) 未配置停止命令")
            return
        }

        isBusy[service.id] = true
        statuses[service.id] = .stopping
        runtimes[service.id]?.status = .stopping

        let result = await ProcessRunner.run(command: stopCmd, timeout: 20)
        lastOutputs[service.id] = result.output

        try? await Task.sleep(nanoseconds: 800_000_000)
        let probeRes = await HealthProbe.probe(service: service)
        let finalStatus = (probeRes.status == .unknown ? (result.isSuccess ? .stopped : .failed) : probeRes.status)
        statuses[service.id] = finalStatus
        runtimes[service.id] = ServiceRuntimeInfo(
            status: finalStatus,
            pid: finalStatus == .running ? probeRes.pid : nil,
            uptime: nil
        )

        // 服务停止后，级联关闭关联的公网穿透隧道，防止孤立暴露
        CloudflareTunnelManager.shared.stopTunnel(for: service.id)

        isBusy[service.id] = false
    }

    /// 重启服务
    /// 注意：未配置 stopCommand 时 stopService 会直接返回，此时重启只会再跑一次 startCommand，
    /// 可能拉起重复进程 —— 调用方（如健康检查强制重启）应确保服务配置了停止命令
    public func restartService(_ service: Service) async {
        if service.stopCommand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            print("[!] [Supervisor] 服务 \(service.name) 未配置停止命令，重启将直接执行启动命令，可能导致重复进程")
        }
        await stopService(service)
        try? await Task.sleep(nanoseconds: 500_000_000)
        await startService(service)
    }

    /// 强制单次手动刷新状态
    public func refreshService(_ service: Service) async {
        await probeService(service)
    }

    /// 单个服务主动探活
    public func probeService(_ service: Service) async {
        isBusy[service.id] = true
        let probeRes = await HealthProbe.probe(service: service)
        applyProbeResult(probeRes, for: service)
        isBusy[service.id] = false
    }

    /// 全部启动
    public func startAllServices() async {
        let services = ServiceStore.shared.services
        for s in services {
            if statuses[s.id] != .running {
                await startService(s)
            }
        }
    }

    /// 全部停止
    public func stopAllServices() async {
        let services = ServiceStore.shared.services
        for s in services {
            if statuses[s.id] == .running {
                await stopService(s)
            }
        }
    }
}
