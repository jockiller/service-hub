import Foundation

public struct CommandResult {
    public let exitCode: Int32
    public let output: String
    public let isSuccess: Bool

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
        self.isSuccess = (exitCode == 0)
    }
}

public final class ProcessRunner {
    /// 执行 Shell 命令（带超时保护与完整的输出收集）
    public static func run(command: String, timeout: TimeInterval = 30) async -> CommandResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", command]

                // 注入常用环境变量，确保 brew、nvm 等命令在 GUI 中能正常找到
                var env = ProcessInfo.processInfo.environment
                let extraPaths = [
                    "/opt/homebrew/bin",
                    "/opt/homebrew/sbin",
                    "/usr/local/bin",
                    "/usr/bin",
                    "/bin",
                    "/usr/sbin",
                    "/sbin"
                ]
                let currentPath = env["PATH"] ?? ""
                env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
                process.environment = env

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                var timedOut = false
                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    timedOut = true
                    if process.isRunning {
                        process.terminate()
                    }
                }
                timer.resume()

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    timer.cancel()

                    let outputStr = String(data: data, encoding: .utf8) ?? ""
                    let exitCode = timedOut ? -999 : process.terminationStatus
                    let finalOutput = timedOut ? (outputStr + "\n[!] 命令执行超时 (\(Int(timeout))s)") : outputStr

                    continuation.resume(returning: CommandResult(exitCode: exitCode, output: finalOutput.trimmingCharacters(in: .whitespacesAndNewlines)))
                } catch {
                    timer.cancel()
                    continuation.resume(returning: CommandResult(exitCode: -1, output: "启动命令失败: \(error.localizedDescription)"))
                }
            }
        }
    }
}
