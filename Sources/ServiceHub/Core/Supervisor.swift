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

    /// 各服务是否有可用更新
    @Published public var updatesAvailable: [String: Bool] = [:]
    /// 各服务的更新信息/版本文本提示
    @Published public var updateInfos: [String: String] = [:]
    /// 正在检测更新中的服务 ID
    @Published public var isCheckingUpdates: [String: Bool] = [:]
    /// 正在执行升级中的服务 ID
    @Published public var isUpdatingServices: [String: Bool] = [:]

    private var probeTimer: Timer?
    /// 记录各服务在短时间内的自动重启尝试时间戳，用于滑动时间窗口熔断
    private var restartTimestamps: [String: [Date]] = [:]
    /// 记录各服务是否已被熔断暂停保活
    @Published public var isCircuitBroken: [String: Bool] = [:]
    /// 健康检查(HTTP)连续失败计数（即使进程仍被判活），达到阈值后强制重启
    @Published public var healthCheckFailCounts: [String: Int] = [:]
    /// 正在执行健康检查强制重启的服务（防重入）
    private var forceRestarting: Set<String> = []
    /// 应用启动后待拉起的服务集合（探活循环按前置条件就绪情况逐个消费）
    /// 「随 ServiceHub 启动」不再是独立拉起路线，而是交给探活循环统一决策
    private var pendingStartupLaunch: Set<String> = []

    public init() {
        startProbeLoop()
    }

    /// 启动定时后台探测循环
    public func startProbeLoop() {
        probeTimer?.invalidate()
        AppLogger.log("[Supervisor] 探活循环已就绪，周期 6.0s")
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
        // ============================================================
        // 探活循环 = 唯一状态机（决策树）：
        //  1. isBusy（正在启动/停止中）→ 跳过本轮，防重入
        //  2. 探活 .running → 正常更新运行数据，清零熔断计数，处理健康检查
        //  3. 未运行时按优先级决策：
        //     a) pendingStartupLaunch 含此服务 → 检查前置条件，
        //        满足则拉起并消费 pending 标记；未满足则标记/维持等待态
        //     b) autoStart 守护 且 之前在运行且本次停止 → 走熔断窗口自动重拉
        //     c) 其余（手动停止等）→ 仅更新状态，不做任何拉起
        // ============================================================

        // 0. 防重入：启动/停止命令执行中，跳过本轮决策
        if isBusy[service.id] == true {
            return
        }

        let isPendingLaunch = pendingStartupLaunch.contains(service.id)

        // 1. 探活结果为 running：正常更新运行数据
        if res.status == .running {
            if isPendingLaunch {
                pendingStartupLaunch.remove(service.id)
                AppLogger.log("[Supervisor] [开机待拉起] 服务「\(service.name)」检测到当前已在运行 (PID: \(res.pid ?? 0))，已认领纳入守护")
            }
            let prevStatus = self.statuses[service.id]
            if prevStatus != .running {
                AppLogger.log("[Supervisor] 服务「\(service.name)」状态就绪: running (PID: \(res.pid ?? 0))")
            }
            let prevRuntime = self.runtimes[service.id]
            self.statuses[service.id] = .running

            // 运行态数据平滑保护：
            // 如果单次探活未能重新抓取到 PID 或运行时长（如子命令或探活偶发延迟），继承上一轮的有效值，彻底杜绝周期性清空闪烁
            let effectivePid = res.pid ?? prevRuntime?.pid
            let effectiveUptime = res.uptimeString ?? prevRuntime?.uptime
            self.runtimes[service.id] = ServiceRuntimeInfo(
                status: .running,
                pid: effectivePid,
                uptime: effectiveUptime
            )

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
            return
        }

        // 2. 探活未运行（.stopped / .unknown / .failed），进入拉起决策分支
        // 2a. 【应用启动待拉起】pending 标记优先消费：
        //     前置条件满足 → 拉起并消费标记；未满足 → 标记等待态，下轮继续复查
        if isPendingLaunch {
            Task { [weak self] in
                guard let self = self else { return }
                guard self.pendingStartupLaunch.contains(service.id),
                      self.statuses[service.id] != .running,
                      self.isBusy[service.id] != true else { return }

                AppLogger.log("[Supervisor] [开机待拉起] 检测服务「\(service.name)」(ID: \(service.id)) 前置条件 (\(service.precondition.displayName))...")
                let preCheck = await PreconditionChecker.check(service: service)
                guard self.pendingStartupLaunch.contains(service.id),
                      self.statuses[service.id] != .running,
                      self.isBusy[service.id] != true else { return }

                if preCheck.isSatisfied {
                    AppLogger.log("[Supervisor] [开机待拉起] 服务「\(service.name)」前置条件已满足，准备执行启动...")
                    await self.startService(service)
                } else {
                    AppLogger.log("[Supervisor] [开机待拉起] 服务「\(service.name)」前置条件未满足: \(preCheck.reason)，保持等待...")
                    self.statuses[service.id] = .waitingPrecondition
                    self.runtimes[service.id] = ServiceRuntimeInfo(
                        status: .waitingPrecondition,
                        pid: nil,
                        uptime: preCheck.reason
                    )
                    self.lastOutputs[service.id] = L("等待前置条件: \(preCheck.reason)", "Waiting for precondition: \(preCheck.reason)")
                }
            }
            return
        }

        // 2b. 等待前置条件状态（非 pending 场景，如用户手动点了启动但前置未满足）：
        //     每轮探活自动复查前置条件，满足则自动拉起；探活的 .stopped 不覆盖等待态
        if self.statuses[service.id] == .waitingPrecondition {
            Task { [weak self] in
                guard let self = self,
                      self.statuses[service.id] == .waitingPrecondition,
                      self.isBusy[service.id] != true else { return }

                let preCheck = await PreconditionChecker.check(service: service)
                guard self.statuses[service.id] == .waitingPrecondition,
                      self.isBusy[service.id] != true else { return }

                if preCheck.isSatisfied {
                    print("[Supervisor] 服务 \(service.name) 前置条件已满足，正在自动启动...")
                    await self.startService(service)
                } else {
                    // 刷新等待原因，保持 UI 提示实时
                    self.runtimes[service.id] = ServiceRuntimeInfo(
                        status: .waitingPrecondition,
                        pid: nil,
                        uptime: preCheck.reason
                    )
                    self.lastOutputs[service.id] = L("等待前置条件: \(preCheck.reason)", "Waiting for precondition: \(preCheck.reason)")
                }
            }
            return
        }

        // 2c. 正常状态更新（非等待、非 pending）
        if res.status != .unknown {
            let prevStatus = self.statuses[service.id]
            self.statuses[service.id] = res.status

            // 明确停止或故障时，清空 PID 与运行时长
            self.runtimes[service.id] = ServiceRuntimeInfo(
                status: res.status,
                pid: nil,
                uptime: nil
            )

            // 如果服务配置了自启动守护，且之前是运行态、本次检测到停止（崩溃守护，非手动停止）
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
                    AppLogger.log("[-] [Supervisor] 服务「\(service.name)」\(failReason)")
                } else {
                    history.append(now)
                    restartTimestamps[service.id] = history
                    AppLogger.log("[Supervisor] 检测到服务「\(service.name)」异常退出，正在自动重拉 (\(service.restartWindowSeconds)s内第 \(history.count)/\(service.maxRestarts) 次)...")
                    Task {
                        await startService(service)
                    }
                }
            }
        }
    }

    /// 应用启动时：将勾选「随 ServiceHub 启动」的服务登记为「待拉起」，
    /// 实际拉起动作完全由探活循环统一决策（探活 → 检查前置条件 → 满足且允许则拉起）。
    /// 这样网络未就绪时服务会安静地每轮复查，网络一通立即自动启动，无需独立拉起路线。
    public func launchServicesAtStartup() {
        let services = ServiceStore.shared.services
        let startupServices = services.filter { $0.launchOnAppStart }
        let ids = startupServices.map { $0.id }
        guard !ids.isEmpty else {
            AppLogger.log("[Supervisor] launchServicesAtStartup(): 当前配置文件中无任何服务勾选「随应用启动」")
            return
        }
        pendingStartupLaunch.formUnion(ids)
        AppLogger.log("[Supervisor] launchServicesAtStartup(): 成功登记 \(ids.count) 个待拉起服务: [\(startupServices.map { "\($0.name)(\($0.id))" }.joined(separator: ", "))]，已交由探活循环统一按前置条件调度拉起")
    }

    /// 启动单个服务
    public func startService(_ service: Service) async {
        isBusy[service.id] = true

        // 用户主动或触发启动时，解除该服务的熔断标记
        isCircuitBroken[service.id] = false

        // 1. 启动前先检查前置条件（如：是否已连入外网/Wi-Fi）
        let preCheck = await PreconditionChecker.check(service: service)
        if !preCheck.isSatisfied {
            AppLogger.log("[Supervisor] 服务「\(service.name)」启动前置条件未满足: \(preCheck.reason)")
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

        AppLogger.log("[Supervisor] 开始执行启动服务「\(service.name)」(ID: \(service.id)) 命令: \(service.startCommand)")
        let result = await ProcessRunner.run(command: service.startCommand, timeout: 30)
        lastOutputs[service.id] = result.output
        let outputSnippet = result.output.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ⏎ ")
        AppLogger.log("[Supervisor] 服务「\(service.name)」启动命令执行完毕 (退出码: \(result.exitCode)，输出: \(outputSnippet.isEmpty ? "(无输出)" : outputSnippet))")

        // 启动后等待 1 秒，让进程稳定，然后探活
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let probeRes = await HealthProbe.probe(service: service)
        let finalStatus = (probeRes.status == .unknown ? (result.isSuccess ? .running : .failed) : probeRes.status)
        statuses[service.id] = finalStatus
        let effectivePid = probeRes.pid ?? runtimes[service.id]?.pid
        let effectiveUptime = probeRes.uptimeString ?? runtimes[service.id]?.uptime
        AppLogger.log("[Supervisor] 服务「\(service.name)」启动后探活结果: \(finalStatus.rawValue) (PID: \(effectivePid != nil ? "\(effectivePid!)" : "无"))")
        runtimes[service.id] = ServiceRuntimeInfo(
            status: finalStatus,
            pid: finalStatus == .running ? effectivePid : nil,
            uptime: finalStatus == .running ? effectiveUptime : nil
        )

        // 拉起流程结束（无论成功与否），消费「应用启动待拉起」标记，避免探活循环重复处理
        pendingStartupLaunch.remove(service.id)

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

        // 若服务勾选了检查更新，启动成功后在后台异步检测是否有更新
        if finalStatus == .running, service.checkUpdateEnabled {
            Task { [weak self] in
                // 缓冲 2 秒，等待服务完成自身端口监听与就绪
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self?.checkUpdate(for: service)
            }
        }

        isBusy[service.id] = false
    }

    /// 停止单个服务
    public func stopService(_ service: Service) async {
        // 用户主动停止：丢弃「应用启动待拉起」标记，防止探活循环随后又把服务拉起来
        pendingStartupLaunch.remove(service.id)

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

    // MARK: - 服务更新与升级管理

    public enum CheckUpdateResult: Sendable {
        case updateAvailable(String)
        case alreadyUpToDate
        case failed(String)
    }

    /// 检测单个服务是否有新版本/可用更新
    @discardableResult
    public func checkUpdate(for service: Service) async -> CheckUpdateResult {
        guard service.checkUpdateEnabled,
              let checkCmd = service.checkUpdateCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
              !checkCmd.isEmpty else {
            return .failed(L("未启用或未配置检测更新命令", "Update check not configured"))
        }

        // 防重入
        if isCheckingUpdates[service.id] == true || isUpdatingServices[service.id] == true {
            return .failed(L("正在检测中，请稍候...", "Check already in progress"))
        }

        isCheckingUpdates[service.id] = true
        defer { isCheckingUpdates[service.id] = false }

        print("[Supervisor] 正在检测服务「\(service.name)」更新...")
        let res = await ProcessRunner.run(command: checkCmd, timeout: 30)

        // 针对 Homebrew outdated 的退出码特性：有更新时退出码为 1，无更新时退出码为 0
        let isBrewCheck = checkCmd.contains("brew outdated")
        let meaningfulLine = extractMeaningfulUpdateLine(from: res.output)

        if (res.isSuccess || (isBrewCheck && res.exitCode == 1)) && meaningfulLine != nil {
            let updateLine = meaningfulLine!
            updatesAvailable[service.id] = true
            updateInfos[service.id] = updateLine
            print("[Supervisor] 服务「\(service.name)」检测到可用更新: \(updateLine)")
            return .updateAvailable(updateLine)
        } else {
            updatesAvailable[service.id] = false
            updateInfos[service.id] = nil
            if res.isSuccess || (isBrewCheck && res.exitCode == 0) {
                print("[Supervisor] 服务「\(service.name)」当前已是最新")
                return .alreadyUpToDate
            } else {
                print("[Supervisor] 服务「\(service.name)」检测更新退出码: \(res.exitCode)")
                return .failed(L("检测命令返回退出码 \(res.exitCode)", "Check exited with code \(res.exitCode)"))
            }
        }
    }

    /// 从检测命令输出中提取有价值的版本信息行，过滤掉包管理器下载/进度等干扰行
    private func extractMeaningfulUpdateLine(from output: String) -> String? {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty &&
                !line.hasPrefix("==>") &&
                !line.hasPrefix("✔") &&
                !line.hasPrefix("✖") &&
                !line.hasPrefix("ℹ") &&
                !line.hasPrefix("Downloading") &&
                !line.hasPrefix("Downloaded") &&
                !line.hasPrefix("Fetching") &&
                !line.hasPrefix("Cloning") &&
                !line.contains("JSON API") &&
                !line.contains("Already up to date")
            }
        return lines.first
    }

    /// 对所有已开启检查更新的服务触发一次更新检测
    public func checkUpdatesForAllServices() {
        let services = ServiceStore.shared.services.filter { $0.checkUpdateEnabled }
        guard !services.isEmpty else { return }
        print("[Supervisor] 正在对 \(services.count) 个已开启更新检测的服务触发后台检查...")
        Task { [weak self] in
            for s in services {
                await self?.checkUpdate(for: s)
            }
        }
    }

    /// 执行更新操作并在完成后重启服务
    public func performUpdate(for service: Service) async {
        guard let updateCmd = service.updateCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
              !updateCmd.isEmpty else {
            print("[-] 服务「\(service.name)」未配置更新命令")
            return
        }

        if isUpdatingServices[service.id] == true || isBusy[service.id] == true {
            return
        }

        isUpdatingServices[service.id] = true
        defer { isUpdatingServices[service.id] = false }

        let wasRunning = (statuses[service.id] == .running)

        // 1. 若当前处于运行中，先优雅停止服务
        if wasRunning {
            print("[Supervisor] 正在停止服务「\(service.name)」以便执行更新...")
            await stopService(service)
        }

        // 2. 执行更新命令（适当提供充足超时，如 180 秒）
        print("[Supervisor] 开始执行服务「\(service.name)」的更新命令...")
        lastOutputs[service.id] = L("正在更新服务...\n$ \(updateCmd)", "Updating service...\n$ \(updateCmd)")

        let updateResult = await ProcessRunner.run(command: updateCmd, timeout: 180)
        lastOutputs[service.id] = updateResult.output

        if updateResult.isSuccess {
            print("[Supervisor] 服务「\(service.name)」更新成功")
            updatesAvailable[service.id] = false
            updateInfos[service.id] = nil

            // 3. 执行更新操作后 重启服务
            print("[Supervisor] 更新完成，正在重启服务「\(service.name)」...")
            await startService(service)
        } else {
            print("[-] 服务「\(service.name)」更新失败，退出码: \(updateResult.exitCode)")
            statuses[service.id] = .failed
            runtimes[service.id] = ServiceRuntimeInfo(
                status: .failed,
                pid: nil,
                uptime: L("更新失败 (退出码 \(updateResult.exitCode))", "Update failed (exit code \(updateResult.exitCode))")
            )
        }
    }

    /// 清理单个服务相关的动态缓存状态
    public func cleanupServiceState(id: String) {
        statuses.removeValue(forKey: id)
        runtimes.removeValue(forKey: id)
        isBusy.removeValue(forKey: id)
        lastOutputs.removeValue(forKey: id)
        updatesAvailable.removeValue(forKey: id)
        updateInfos.removeValue(forKey: id)
        isCheckingUpdates.removeValue(forKey: id)
        isUpdatingServices.removeValue(forKey: id)
        restartTimestamps.removeValue(forKey: id)
        isCircuitBroken.removeValue(forKey: id)
        healthCheckFailCounts.removeValue(forKey: id)
        pendingStartupLaunch.remove(id)
    }
}
