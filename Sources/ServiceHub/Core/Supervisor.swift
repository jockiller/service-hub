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
    private var consecutiveFailures: [String: Int] = [:]

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
                await self?.probeAllServices()
            }
        }
        // 立即触发首次检测
        Task {
            await probeAllServices()
        }
    }

    /// 对所有已登记服务执行探活
    public func probeAllServices() async {
        let services = ServiceStore.shared.services
        for s in services {
            // 如果用户正在对其执行操作（如启动中/停止中），跳过本次后台轮询
            if isBusy[s.id] == true { continue }

            let probeRes = await HealthProbe.probe(service: s)
            applyProbeResult(probeRes, for: s)
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

            // 如果服务配置了自启动，但发现停止了，且之前不是手动停止
            if service.autoStart && res.status == .stopped && prevStatus == .running {
                let failures = consecutiveFailures[service.id, default: 0]
                if failures < 3 {
                    consecutiveFailures[service.id] = failures + 1
                    print("[Supervisor] 检测到服务 \(service.name) 异常退出，正在自动重拉 (第 \(failures + 1) 次)...")
                    Task {
                        await startService(service)
                    }
                } else {
                    self.statuses[service.id] = .failed
                    self.runtimes[service.id]?.status = .failed
                }
            } else if res.status == .running {
                consecutiveFailures[service.id] = 0
            }
        }
    }

    /// 启动单个服务
    public func startService(_ service: Service) async {
        isBusy[service.id] = true
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
