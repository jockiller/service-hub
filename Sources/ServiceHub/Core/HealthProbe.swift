import Foundation
import AppKit

public struct ProbeResult: Sendable {
    public let status: ServiceStatus
    public let pid: pid_t?
    public let launchDate: Date?
    public let uptimeString: String?

    public init(
        status: ServiceStatus,
        pid: pid_t? = nil,
        launchDate: Date? = nil,
        uptimeString: String? = nil
    ) {
        self.status = status
        self.pid = pid
        self.launchDate = launchDate
        self.uptimeString = uptimeString
    }
}

public final class HealthProbe {
    /// 对服务进行精准健康检测，并提取进程 PID 与启动时间
    public static func probe(service: Service) async -> ProbeResult {
        // 1. 若关联了 macOS 原生应用程序 (.app)，使用系统级 NSRunningApplication 100% 精确检测
        if let appPath = service.appPath, !appPath.isEmpty, FileManager.default.fileExists(atPath: appPath) {
            let bundle = Bundle(path: appPath)
            if let bundleId = bundle?.bundleIdentifier {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
                if let activeApp = runningApps.first(where: { !$0.isTerminated }) {
                    let pid = activeApp.processIdentifier
                    let launchDate = activeApp.launchDate
                    let uptime = formatUptime(since: launchDate)
                    return ProbeResult(status: .running, pid: pid, launchDate: launchDate, uptimeString: uptime)
                } else {
                    return ProbeResult(status: .stopped)
                }
            }
        }

        // 2. 若配置了 HTTP 探活，优先尝试 HTTP 请求
        if let urlStr = service.healthCheckURL, let url = URL(string: urlStr) {
            if await checkHTTP(url: url) {
                let pidInfo = await findPidForService(service: service)
                return ProbeResult(
                    status: .running,
                    pid: pidInfo.pid,
                    launchDate: pidInfo.launchDate,
                    uptimeString: pidInfo.uptime
                )
            }
        }

        // 3. 若配置了 status 状态命令，执行命令检测
        if let cmd = service.statusCommand, !cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let res = await ProcessRunner.run(command: cmd, timeout: 5)
            if res.isSuccess {
                let pidInfo = await findPidForService(service: service, commandOutput: res.output)
                return ProbeResult(
                    status: .running,
                    pid: pidInfo.pid,
                    launchDate: pidInfo.launchDate,
                    uptimeString: pidInfo.uptime
                )
            } else {
                return ProbeResult(status: .stopped)
            }
        }

        return ProbeResult(status: .unknown)
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

    /// 尝试定位服务的 PID 及进程启动时间
    private static func findPidForService(service: Service, commandOutput: String? = nil) async -> (pid: pid_t?, launchDate: Date?, uptime: String?) {
        var foundPid: pid_t? = nil

        // 1. 从命令输出中提取 PID（如输出中包含 PID: 12345 或 (PID: 12345)）
        if let out = commandOutput {
            if let regex = try? NSRegularExpression(pattern: #"(?:PID:?\s*|\()([0-9]{2,7})\b"#, options: .caseInsensitive),
               let match = regex.firstMatch(in: out, range: NSRange(out.startIndex..., in: out)),
               let range = Range(match.range(at: 1), in: out),
               let val = pid_t(out[range]) {
                if kill(val, 0) == 0 {
                    foundPid = val
                }
            }
        }

        // 2. 从日志所在目录寻找同名 .pid 文件 (如 gpt-load.pid, frpc.pid)
        if foundPid == nil, let logPath = service.logPath {
            let dir = URL(fileURLWithPath: logPath).deletingLastPathComponent()
            let candidates = ["\(service.id).pid", "pid", "\(URL(fileURLWithPath: logPath).deletingPathExtension().lastPathComponent).pid"]
            for name in candidates {
                let pidFileURL = dir.appendingPathComponent(name)
                if let content = try? String(contentsOf: pidFileURL, encoding: .utf8),
                   let val = pid_t(content.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    if kill(val, 0) == 0 {
                        foundPid = val
                        break
                    }
                }
            }
        }

        guard let validPid = foundPid else {
            return (nil, nil, nil)
        }

        // 3. 通过 ps 命令提取该 PID 的真实启动时间和已运行时长
        let psCmd = "ps -p \(validPid) -o etime=,lstart= 2>/dev/null"
        let psRes = await ProcessRunner.run(command: psCmd, timeout: 3)
        if psRes.isSuccess {
            let trimmed = psRes.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if let etime = parts.first {
                let formattedUptime = formatEtime(etime)
                return (validPid, nil, formattedUptime)
            }
        }

        return (validPid, nil, nil)
    }

    private static func formatEtime(_ etime: String) -> String {
        // etime 格式可能是: [[dd-]hh:]mm:ss
        let components = etime.components(separatedBy: "-")
        if components.count == 2 {
            return uptimeIsEnglish() ? "\(components[0])d \(components[1])" : "\(components[0])天 \(components[1])"
        }
        let timeParts = etime.components(separatedBy: ":")
        if timeParts.count == 3 {
            return uptimeIsEnglish() ? "\(timeParts[0])h \(timeParts[1])m" : "\(timeParts[0])小时 \(timeParts[1])分"
        } else if timeParts.count == 2 {
            return uptimeIsEnglish() ? "\(timeParts[0])m \(timeParts[1])s" : "\(timeParts[0])分 \(timeParts[1])秒"
        }
        return etime
    }

    private static func formatUptime(since date: Date?) -> String? {
        guard let date = date else { return nil }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return uptimeIsEnglish() ? "just now" : "刚刚"
        } else if interval < 3600 {
            return "\(Int(interval / 60)) \(uptimeIsEnglish() ? "min" : "分钟")"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            let mins = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours) \(uptimeIsEnglish() ? "h" : "小时") \(mins) \(uptimeIsEnglish() ? "m" : "分")"
        } else {
            let days = Int(interval / 86400)
            let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)
            return "\(days) \(uptimeIsEnglish() ? "d" : "天") \(hours) \(uptimeIsEnglish() ? "h" : "小时")"
        }
    }
}
