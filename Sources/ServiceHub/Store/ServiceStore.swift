import Foundation
import Yams

@MainActor
public final class ServiceStore: ObservableObject {
    public static let shared = ServiceStore()

    @Published public var services: [Service] = []
    @Published public var selectedServiceId: String?

    private let fileManager = FileManager.default

    public var defaultConfigURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ServiceHub", isDirectory: true)
        if !fileManager.fileExists(atPath: appDir.path) {
            try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        return appDir.appendingPathComponent("services.yaml")
    }

    /// 当前实际生效的配置文件路径（优先用户自定义的路径，如 OneDrive/iCloud/自定目录）
    public var configURL: URL {
        let custom = AppSettings.shared.customConfigPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return defaultConfigURL
    }

    public init() {
        load()
    }

    public func load() {
        let currentURL = self.configURL
        if !fileManager.fileExists(atPath: currentURL.path) {
            // 若当前文件不存在：仅在处于本地默认路径时初始化预设，云端路径（如 OneDrive/iCloud）可能开机短时未挂载，切勿覆写空数据
            if currentURL == defaultConfigURL {
                self.services = defaultServices()
                save()
            } else {
                AppLogger.log("[ServiceStore] 自定义配置文件暂不可访问或未就绪: \(currentURL.path)，保留现有服务配置")
            }
            return
        }

        do {
            let data = try Data(contentsOf: currentURL)
            let decoder = YAMLDecoder()
            let config = try decoder.decode(ServiceConfigFile.self, from: data)
            self.services = config.services
            AppLogger.log("[ServiceStore] 成功加载配置文件 (\(config.services.count) 个服务): \(currentURL.path)")
        } catch {
            AppLogger.log("[-] 加载配置文件失败: \(error.localizedDescription)")
        }
    }

    public func save() {
        let currentURL = self.configURL
        let dir = currentURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let config = ServiceConfigFile(version: 1, services: services)
        do {
            let encoder = YAMLEncoder()
            let yamlString = try encoder.encode(config)
            try yamlString.write(to: currentURL, atomically: true, encoding: .utf8)
        } catch {
            print("[-] 保存配置文件失败: \(error.localizedDescription)")
        }
    }

    /// 修改配置文件存储路径，支持自动将现有配置迁移至新路径
    public func changeConfigPath(to newURL: URL, migrateExisting: Bool) throws {
        let dir = newURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        if migrateExisting {
            let config = ServiceConfigFile(version: 1, services: services)
            let encoder = YAMLEncoder()
            let yamlString = try encoder.encode(config)
            try yamlString.write(to: newURL, atomically: true, encoding: .utf8)
        }

        AppSettings.shared.customConfigPath = newURL.path
        load()
    }

    /// 恢复为默认存储路径
    public func resetToDefaultConfigPath() {
        AppSettings.shared.customConfigPath = ""
        load()
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
        // 首次启动时的示例预设（仅作演示，请按需编辑为自己的服务）
        return [
            Service(
                id: "gpt-load",
                name: "GPT-Load",
                icon: "bolt.fill",
                autoStart: false,
                startCommand: "/path/to/gpt_load start",
                stopCommand: "/path/to/gpt_load stop",
                statusCommand: "pgrep -f gpt_load >/dev/null",
                logPath: "",
                healthCheckURL: "http://127.0.0.1:3001/health",
                webURL: "http://127.0.0.1:3001"
            ),
            Service(
                id: "frpc",
                name: "FRP Client",
                icon: "network",
                autoStart: false,
                startCommand: "/usr/local/bin/frpc start",
                stopCommand: "/usr/local/bin/frpc stop",
                statusCommand: "pgrep -f frpc >/dev/null",
                logPath: ""
            )
        ]
    }
}
