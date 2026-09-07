import Foundation

public enum PreconditionType: String, Codable, CaseIterable {
    case none = "none"
    case network = "network"
    case wifi = "wifi"
    case custom = "custom"

    public var displayName: String {
        switch self {
        case .none: return "无前置条件 (立即启动)"
        case .network: return "需要连接互联网 (外网已连通)"
        case .wifi: return "需要连接 Wi-Fi"
        case .custom: return "自定义命令检测 (退出码为 0)"
        }
    }

    public var shortName: String {
        switch self {
        case .none: return ""
        case .network: return "需联网"
        case .wifi: return "需Wi-Fi"
        case .custom: return "自定义前置条件"
        }
    }
}

public final class PreconditionChecker {
    /// 检查服务的前置条件是否已满足
    public static func check(service: Service) async -> (isSatisfied: Bool, reason: String) {
        switch service.precondition {
        case .none:
            return (true, "就绪")

        case .network:
            // 快速检测外网（利用 Apple Captive 探活接口，超时 2s）
            let cmd = "curl -sI -m 2 https://captive.apple.com/hotspot-detect.html >/dev/null 2>&1 || ping -c 1 -t 2 223.5.5.5 >/dev/null 2>&1"
            let res = await ProcessRunner.run(command: cmd, timeout: 3)
            if res.isSuccess {
                return (true, "外网已连通")
            } else {
                return (false, "等待外网连通")
            }

        case .wifi:
            // 检测本机是否接入了 Wi-Fi 网络
            let cmd = "/usr/sbin/networksetup -getairportnetwork en0 2>/dev/null"
            let res = await ProcessRunner.run(command: cmd, timeout: 3)
            if res.output.contains("Current Wi-Fi Network:") {
                let parts = res.output.components(separatedBy: "Current Wi-Fi Network:")
                let ssid = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return (true, "已连接 Wi-Fi: \(ssid)")
            } else {
                return (false, "等待连接 Wi-Fi")
            }

        case .custom:
            guard let customCmd = service.preconditionCustomCommand, !customCmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return (true, "未配置具体命令，默认就绪")
            }
            let res = await ProcessRunner.run(command: customCmd, timeout: 5)
            if res.isSuccess {
                return (true, "前置条件检测通过")
            } else {
                return (false, "等待前置条件满足 (命令退出码: \(res.exitCode))")
            }
        }
    }
}
