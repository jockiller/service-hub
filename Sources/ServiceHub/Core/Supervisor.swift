import Foundation
import SwiftUI

@MainActor
public final class Supervisor: ObservableObject {
    public static let shared = Supervisor()

    @Published public var statuses: [String: ServiceStatus] = [:]
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
        probeTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
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

            let status = await HealthProbe.probe(service: s)
            if status != .unknown {
                let prevStatus = self.statuses[s.id]
                self.statuses[s.id] = status

                // 如果服务配置了自启动，但发现停止了，且之前不是手动停止
                if s.autoStart && status == .stopped && prevStatus == .running {
                    let failures = consecutiveFailures[s.id, default: 0]
                    if failures < 3 {
                        consecutiveFailures[s.id] = failures + 1
                        print("[Supervisor] 检测到服务 \(s.name) 异常退出，正在自动重拉 (第 \(failures + 1) 次)...")
                        await startService(s)
                    } else {
                        self.statuses[s.id] = .failed
                    }
                } else if status == .running {
                    consecutiveFailures[s.id] = 0
                }
            }
        }
    }

    /// 启动单个服务
    public func startService(_ service: Service) async {
        isBusy[service.id] = true
        statuses[service.id] = .starting

        let result = await ProcessRunner.run(command: service.startCommand, timeout: 30)
        lastOutputs[service.id] = result.output

        // 启动后等待 1 秒，让进程稳定，然后探活
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let newStatus = await HealthProbe.probe(service: service)
        statuses[service.id] = (newStatus == .unknown ? (result.isSuccess ? .running : .failed) : newStatus)
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

        let result = await ProcessRunner.run(command: stopCmd, timeout: 20)
        lastOutputs[service.id] = result.output

        try? await Task.sleep(nanoseconds: 800_000_000)
        let newStatus = await HealthProbe.probe(service: service)
        statuses[service.id] = (newStatus == .unknown ? (result.isSuccess ? .stopped : .failed) : newStatus)
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
        let status = await HealthProbe.probe(service: service)
        if status != .unknown {
            statuses[service.id] = status
        }
        isBusy[service.id] = false
    }
}
