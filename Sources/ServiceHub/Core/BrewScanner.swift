import Foundation

public struct BrewServiceItem: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let status: String
    public let isStarted: Bool

    public var recommendedIcon: String {
        let lower = name.lowercased()
        if lower.contains("redis") || lower.contains("memcached") {
            return "cylinder.split.1x2.fill"
        } else if lower.contains("maria") || lower.contains("mysql") || lower.contains("postgres") || lower.contains("mongo") {
            return "cylinder.fill"
        } else if lower.contains("nginx") || lower.contains("caddy") || lower.contains("apache") || lower.contains("httpd") {
            return "globe"
        } else if lower.contains("kafka") || lower.contains("rabbit") || lower.contains("mq") {
            return "tray.2.fill"
        } else if lower.contains("dns") || lower.contains("unbound") {
            return "network"
        }
        return "server.rack"
    }
}

public final class BrewScanner {
    public static func scanInstalledServices() async -> [BrewServiceItem] {
        // 执行 brew services list --json
        let cmd = "/opt/homebrew/bin/brew services list --json 2>/dev/null || /usr/local/bin/brew services list --json 2>/dev/null"
        let res = await ProcessRunner.run(command: cmd, timeout: 6)

        guard res.isSuccess, let data = res.output.data(using: .utf8) else {
            return []
        }

        struct RawBrewItem: Decodable {
            let name: String
            let status: String?
        }

        do {
            let rawList = try JSONDecoder().decode([RawBrewItem].self, from: data)
            return rawList.map { item in
                let st = item.status ?? "none"
                return BrewServiceItem(
                    name: item.name,
                    status: st,
                    isStarted: (st == "started")
                )
            }
        } catch {
            print("[-] 解析 Homebrew 服务列表失败: \(error.localizedDescription)")
            return []
        }
    }
}
