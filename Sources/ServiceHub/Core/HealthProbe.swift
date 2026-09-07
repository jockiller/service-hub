import Foundation

public final class HealthProbe {
    /// 对服务进行健康检测
    public static func probe(service: Service) async -> ServiceStatus {
        // 1. 若配置了 HTTP 接口检查，优先尝试 HTTP 请求
        if let urlStr = service.healthCheckURL, let url = URL(string: urlStr) {
            if await checkHTTP(url: url) {
                return .running
            }
        }

        // 2. 若配置了 status 命令，使用该命令进行检测
        if let cmd = service.statusCommand, !cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let res = await ProcessRunner.run(command: cmd, timeout: 5)
            return res.isSuccess ? .running : .stopped
        }

        // 3. 未配置特定探测机制时，返回 unknown
        return .unknown
    }

    private static func checkHTTP(url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse {
                return (200...399).contains(httpRes.statusCode)
            }
        } catch {
            return false
        }
        return false
    }
}
