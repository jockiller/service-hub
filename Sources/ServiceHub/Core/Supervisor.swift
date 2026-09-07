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
    /// 记录各服务在短时间内的自动重启尝试时间戳，用于滑动时间窗口熔断
    private var restartTimestamps: [String: [Date]] = [:]
    /// 记录各服务是否已被熔断暂停保活
    @Published public var isCircuitBroken: [String: Bool] = [:]

    public init() {
        startProbeLoop()
    }

    deinit {
        probeTimer?.invalidate()
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

    /// 彻底在后台 Task 线程池中异步探活，0 秒阻塞主线程
    public func triggerProbeAll() {
        let services = ServiceStore.shared.services
        Task.detached(priority: .utility) { [weak self] in
            for s in services {
                let probeRes = await HealthProbe.probe(service: s)
                await MainActor.run { [weak self] in
                    self?.applyProbeResult(probeRes, for: s)
                }
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
                    let failReason = "已熔断: \(service.restartWindowSeconds)s内失败\(history.count)次，已停保活"
                    self.runtimes[service.id] = ServiceRuntimeInfo(
                        status: .failed,
                        pid: nil,
                        uptime: failReason
                    )
                    lastOutputs[service.id] = "服务在 \(service.restartWindowSeconds) 秒内连续重启达到 \(service.maxRestarts) 次上限，已暂停自动保活保护系统。请排查原因后手动点击启动恢复。"
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
            lastOutputs[service.id] = "等待前置条件: \(preCheck.reason)"
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
        isBusy[service.id] = false
    }

    /// 重启服务
    public func restartService(_ service: Service) async {
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
