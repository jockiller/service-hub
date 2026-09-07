import Foundation
import Yams

@MainActor
public final class ServiceStore: ObservableObject {
    public static let shared = ServiceStore()

    @Published public var services: [Service] = []
    @Published public var selectedServiceId: String?

    private let fileManager = FileManager.default
    public let configURL: URL

    public init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ServiceHub", isDirectory: true)
        if !fileManager.fileExists(atPath: appDir.path) {
            try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        self.configURL = appDir.appendingPathComponent("services.yaml")
        load()
    }

    public func load() {
        if !fileManager.fileExists(atPath: configURL.path) {
            // 初次启动，内置默认配置（包含本机已有的 GPT-Load、FRP Client）
            self.services = defaultServices()
            save()
            return
        }

        do {
            let data = try Data(contentsOf: configURL)
            let decoder = YAMLDecoder()
            let config = try decoder.decode(ServiceConfigFile.self, from: data)
            self.services = config.services
        } catch {
            print("[-] 加载配置文件失败: \(error.localizedDescription)，尝试保留原有配置...")
        }
    }

    public func save() {
        let config = ServiceConfigFile(version: 1, services: services)
        do {
            let encoder = YAMLEncoder()
            let yamlString = try encoder.encode(config)
            try yamlString.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            print("[-] 保存配置文件失败: \(error.localizedDescription)")
        }
    }

    public func addService(_ service: Service) {
        services.removeAll(where: { $0.id == service.id })
        services.append(service)
        save()
        if selectedServiceId == nil {
            selectedServiceId = service.id
        }
    }

    public func updateService(_ service: Service) {
        if let idx = services.firstIndex(where: { $0.id == service.id }) {
            services[idx] = service
            save()
        }
    }

    public func removeService(id: String) {
        services.removeAll(where: { $0.id == id })
        if selectedServiceId == id {
            selectedServiceId = services.first?.id
        }
        save()
    }

    public func exportConfig(to destinationURL: URL) throws {
        let data = try Data(contentsOf: configURL)
        try data.write(to: destinationURL)
    }

    public func importConfig(from sourceURL: URL) throws {
        let data = try Data(contentsOf: sourceURL)
        let decoder = YAMLDecoder()
        let config = try decoder.decode(ServiceConfigFile.self, from: data)
        self.services = config.services
        save()
    }

    private func defaultServices() -> [Service] {
        return [
            Service(
                id: "gpt-load",
                name: "GPT-Load",
                icon: "bolt.fill",
                autoStart: true,
                startCommand: "/Users/jockiller/Documents/workspace/git_work/my/py3/ai/gpt_load/gpt_load start",
                stopCommand: "/Users/jockiller/Documents/workspace/git_work/my/py3/ai/gpt_load/gpt_load stop",
                statusCommand: "/Users/jockiller/Documents/workspace/git_work/my/py3/ai/gpt_load/gpt_load status",
                logPath: "/Users/jockiller/env/gpt_load/gpt-load.log",
                healthCheckURL: "http://127.0.0.1:3001/health"
            ),
            Service(
                id: "frpc",
                name: "FRP Client",
                icon: "network",
                autoStart: true,
                startCommand: "/Users/jockiller/Documents/workspace/git_work/my/py3/other/frp/frpc start",
                stopCommand: "/Users/jockiller/Documents/workspace/git_work/my/py3/other/frp/frpc stop",
                statusCommand: "/Users/jockiller/Documents/workspace/git_work/my/py3/other/frp/frpc status",
                logPath: "/Users/jockiller/env/frp/frpc.log"
            ),
            Service(
                id: "redis",
                name: "Redis (Homebrew)",
                icon: "cylinder.split.1x2.fill",
                autoStart: false,
                startCommand: "/opt/homebrew/bin/brew services start redis",
                stopCommand: "/opt/homebrew/bin/brew services stop redis",
                statusCommand: "/opt/homebrew/bin/brew services list | grep redis | grep started"
            )
        ]
    }
}
