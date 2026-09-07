import Foundation
import AppKit

@MainActor
public final class CloudflareTunnelManager: ObservableObject {
    public static let shared = CloudflareTunnelManager()

    /// 已成功暴露到公网的服务及其分配的 URL (serviceId -> Public URL)
    @Published public var publicUrls: [String: String] = [:]
    /// 隧道的连接状态描述 (serviceId -> 状态文本)
    @Published public var tunnelStates: [String: String] = [:]
    /// 是否正在启动穿透进程 (serviceId -> Bool)
    @Published public var isConnecting: [String: Bool] = [:]

    private var processes: [String: Process] = [:]

    public init() {}

    /// 寻找可用的 cloudflared 可执行文件路径
    public static func findCloudflaredPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/cloudflared",
            "/usr/local/bin/cloudflared",
            "\(NSHomeDirectory())/Library/Application Support/ServiceHub/bin/cloudflared",
            "/usr/bin/cloudflared"
        ]
        for p in candidates {
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
        return nil
    }

    /// 本机是否已安装 cloudflared
    public var isCloudflaredInstalled: Bool {
        return CloudflareTunnelManager.findCloudflaredPath() != nil
    }

    /// 一键通过 Homebrew 安装 cloudflared
    public func installCloudflaredViaBrew() async -> Bool {
        let cmd = "/opt/homebrew/bin/brew install cloudflared || /usr/local/bin/brew install cloudflared"
        let res = await ProcessRunner.run(command: cmd, timeout: 180)
        return res.isSuccess && isCloudflaredInstalled
    }

    /// 启动公网穿透隧道
    public func startTunnel(for service: Service) {
        // 前置约束：公网穿透把本地服务暴露到公网，必须先配置服务主页作为穿透目标
        let hasWebURL = service.webURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        guard hasWebURL else {
            tunnelStates[service.id] = L("请先在服务配置中填写「服务主页」", "Configure the service homepage first")
            return
        }

        guard let binPath = CloudflareTunnelManager.findCloudflaredPath() else {
            tunnelStates[service.id] = L("未安装 cloudflared", "cloudflared not installed")
            return
        }

        // 停止先前的隧道（如果有）
        stopTunnel(for: service.id)

        isConnecting[service.id] = true
        tunnelStates[service.id] = L("正在建立 Cloudflare 加密隧道...", "Establishing Cloudflare tunnel...")

        let config = service.tunnelConfig ?? TunnelConfig(enabled: true, mode: .quick)
        let target = config.targetURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? config.targetURL!
            : service.webURL!

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binPath)

        if config.mode == .token, let token = config.token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Token 正式模式
            process.arguments = ["tunnel", "run", "--token", token.trimmingCharacters(in: .whitespacesAndNewlines)]
        } else {
            // 快速临时模式
            process.arguments = ["tunnel", "--url", target, "--no-autoupdate"]
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.publicUrls.removeValue(forKey: service.id)
                self.tunnelStates.removeValue(forKey: service.id)
                self.isConnecting.removeValue(forKey: service.id)
                self.processes.removeValue(forKey: service.id)
            }
        }

        // 异步逐行监听输出提取分配的域名
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

            // 正则提取 https://[a-zA-Z0-9-]+\.trycloudflare\.com
            if let regex = try? NSRegularExpression(pattern: #"https:\/\/[a-zA-Z0-9-]+\.trycloudflare\.com"#),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
               let range = Range(match.range, in: output) {
                let urlStr = String(output[range])
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.publicUrls[service.id] = urlStr
                    self.tunnelStates[service.id] = L("已暴露到公网", "Exposed to public")
                    self.isConnecting[service.id] = false
                    print("[CloudflareTunnel] 服务 \(service.name) 成功映射至: \(urlStr)")
                }
            } else if output.contains("Registered tunnel connection") {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.tunnelStates[service.id] = L("隧道连接已注册", "Tunnel connection registered")
                    self.isConnecting[service.id] = false
                }
            }
        }

        do {
            try process.run()
            processes[service.id] = process

            // 如果是 Token 模式且配置了自定义域名，直接登记生效
            if config.mode == .token {
                if let domain = config.customDomain?.trimmingCharacters(in: .whitespacesAndNewlines), !domain.isEmpty {
                    let fullURL = (domain.hasPrefix("http://") || domain.hasPrefix("https://")) ? domain : "https://\(domain)"
                    self.publicUrls[service.id] = fullURL
                    self.tunnelStates[service.id] = L("已绑定自定义域名", "Custom domain bound")
                } else {
                    self.tunnelStates[service.id] = L("Token 隧道已就绪", "Token tunnel ready")
                }
                self.isConnecting[service.id] = false
            }
        } catch {
            isConnecting[service.id] = false
            tunnelStates[service.id] = L("启动隧道失败: \(error.localizedDescription)", "Tunnel failed to start: \(error.localizedDescription)")
        }
    }

    /// 停止指定服务的公网穿透
    public func stopTunnel(for serviceId: String) {
        if let proc = processes[serviceId] {
            proc.terminate()
            processes.removeValue(forKey: serviceId)
        }
        publicUrls.removeValue(forKey: serviceId)
        tunnelStates.removeValue(forKey: serviceId)
        isConnecting.removeValue(forKey: serviceId)
    }

    /// 安全熔断：一键切断所有服务的公网穿透
    public func stopAllTunnels() {
        for (_, proc) in processes {
            proc.terminate()
        }
        processes.removeAll()
        publicUrls.removeAll()
        tunnelStates.removeAll()
        isConnecting.removeAll()
        print("[CloudflareTunnel] 安全保护: 已切断所有公网映射隧道")
    }

    /// 检查指定服务是否正在映射到公网
    public func isTunnelActive(for serviceId: String) -> Bool {
        return publicUrls[serviceId] != nil || processes[serviceId]?.isRunning == true
    }
}
