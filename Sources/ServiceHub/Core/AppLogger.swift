import Foundation
import os

/// ServiceHub 系统级统一日志记录器：
/// 1. 控制台标准输出 (stdout)
/// 2. macOS 原生系统统一日志 (os_log / Console.app)
/// 3. macOS 通用用户应用日志目录: ~/Library/Logs/ServiceHub/servicehub.log
public final class AppLogger: @unchecked Sendable {
    public static let shared = AppLogger()

    public let logURL: URL
    private let queue = DispatchQueue(label: "com.jockiller.servicehub.logger", qos: .utility)
    private let osLogger = Logger(subsystem: "com.jockiller.servicehub", category: "Supervisor")
    private let dateFormatter: DateFormatter
    private let maxFileSizeBytes: Int64 = 5 * 1024 * 1024 // 单个日志文件最大 5MB

    private init() {
        // macOS 通用用户日志目录 (~/Library/Logs/)
        let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let logsDir = libraryDir.appendingPathComponent("Logs/ServiceHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logURL = logsDir.appendingPathComponent("servicehub.log")

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        self.dateFormatter = df
    }

    public static var logFilePath: String {
        shared.logURL.path
    }

    public static func log(_ message: String) {
        shared.write(message)
    }

    public func write(_ message: String) {
        let now = Date()
        let timestampStr = dateFormatter.string(from: now)
        let line = "[\(timestampStr)] \(message)\n"

        // 1. 控制台标准输出
        print(line, terminator: "")

        // 2. 苹果系统统一日志 (Console.app 控制台可实时过滤查看)
        osLogger.notice("\(message, privacy: .public)")

        // 3. 异步排队写入本地持久化日志文件
        queue.async { [logURL = self.logURL, maxBytes = self.maxFileSizeBytes] in
            guard let data = line.data(using: .utf8) else { return }

            if FileManager.default.fileExists(atPath: logURL.path) {
                // 超限轮转保护：超过 5MB 时截断保留后半部分
                if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
                   let size = attrs[.size] as? Int64, size > maxBytes {
                    if let existingData = try? Data(contentsOf: logURL) {
                        let keepBytes = Int(maxBytes / 2)
                        let trimmed = existingData.suffix(keepBytes)
                        try? trimmed.write(to: logURL, options: .atomic)
                    }
                }

                if let handle = try? FileHandle(forWritingTo: logURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    _ = try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: logURL, options: .atomic)
            }
        }
    }
}
