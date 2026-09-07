import Foundation

public struct DockerContainerItem: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let image: String
    public let status: String
    public let isRunning: Bool
}

public final class DockerScanner {
    /// 寻找本机可用的 docker 可执行文件路径
    public static func findDockerPath() -> String {
        let candidates = [
            "/opt/homebrew/bin/docker",
            "/usr/local/bin/docker",
            "\(NSHomeDirectory())/.docker/bin/docker",
            "/usr/bin/docker"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "docker"
    }

    /// 扫描本地所有 Docker 容器（包含运行中与停止的容器）
    public static func scanContainers() async -> (success: Bool, containers: [DockerContainerItem], error: String?) {
        let dockerPath = findDockerPath()
        let cmd = "\(dockerPath) ps -a --format '{\"name\":\"{{.Names}}\",\"image\":\"{{.Image}}\",\"status\":\"{{.Status}}\",\"state\":\"{{.State}}\"}' 2>&1"
        let res = await ProcessRunner.run(command: cmd, timeout: 6)

        if !res.isSuccess {
            let out = res.output
            if out.contains("Cannot connect to the Docker daemon") || out.contains("docker daemon is not running") {
                return (false, [], "Docker 守护进程未启动，请先打开 Docker Desktop 或 OrbStack")
            } else if out.contains("command not found") || out.contains("No such file") {
                return (false, [], "本机未检测到 Docker 环境，请先安装 Docker")
            }
            return (false, [], out.components(separatedBy: .newlines).first ?? "Docker 调用失败")
        }

        struct RawContainer: Decodable {
            let name: String
            let image: String
            let status: String?
            let state: String?
        }

        var items: [DockerContainerItem] = []
        let lines = res.output.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        for line in lines {
            if let data = line.data(using: .utf8),
               let raw = try? JSONDecoder().decode(RawContainer.self, from: data) {
                let isRunning = (raw.state?.lowercased() == "running")
                items.append(DockerContainerItem(
                    name: raw.name,
                    image: raw.image,
                    status: raw.status ?? raw.state ?? "unknown",
                    isRunning: isRunning
                ))
            }
        }

        return (true, items, nil)
    }
}
