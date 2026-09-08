import Foundation
import SwiftUI

private final class FileWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private var lastOffset: UInt64 = 0
    private let url: URL
    private let onAppend: @Sendable (String, UInt64) -> Void
    private let onReset: @Sendable () -> Void

    init(url: URL, onAppend: @escaping @Sendable (String, UInt64) -> Void, onReset: @escaping @Sendable () -> Void) {
        self.url = url
        self.onAppend = onAppend
        self.onReset = onReset
        start()
    }

    deinit {
        source?.cancel()
    }

    private func start() {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            let fileSize = handle.seekToEndOfFile()
            // 预读限制：最多读取末尾 64KB，彻底防止大文件一次性吃满内存
            let readSize: UInt64 = min(fileSize, 64 * 1024)
            handle.seek(toFileOffset: fileSize - readSize)
            let data = handle.readDataToEndOfFile()
            handle.closeFile()

            lastOffset = fileSize
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                onAppend(str, fileSize)
            }
        } catch {
            return
        }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete],
            queue: .global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            self?.readAppendedData()
        }
        src.setCancelHandler {
            close(fd)
        }
        src.resume()
        self.source = src
    }

    private func readAppendedData() {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            let currentSize = handle.seekToEndOfFile()
            if currentSize > lastOffset {
                handle.seek(toFileOffset: lastOffset)
                let data = handle.readDataToEndOfFile()
                lastOffset = currentSize
                if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                    onAppend(str, currentSize)
                }
            } else if currentSize < lastOffset {
                lastOffset = 0
                onReset()
            }
            handle.closeFile()
        } catch {}
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}

@MainActor
public final class LogTail: ObservableObject {
    /// 控制台最多展示并保留的最新日志行数（超过该限制自动丢弃老数据，内存恒定极小）
    public static let maxDisplayLines = 300

    /// 当前有界日志行数组
    @Published public var lines: [String] = []
    @Published public var filterText: String = ""
    @Published public var isFollowing: Bool = true
    /// 日志是否被截断（即只显示了末尾部分最新日志）
    @Published public var isTruncated: Bool = false
    /// 当前日志文件总大小（字节）
    @Published public var fileSize: UInt64 = 0
    /// 状态说明文案（如未配置路径、文件不存在等）
    @Published public var placeholderMessage: String? = nil

    private var watcher: FileWatcher?
    private var pendingPartialLine: String = ""

    public init() {}

    public func loadLog(for path: String?) {
        watcher?.stop()
        watcher = nil
        lines = []
        pendingPartialLine = ""
        isTruncated = false
        fileSize = 0
        placeholderMessage = nil

        guard let path = path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            placeholderMessage = L("（该服务未配置日志文件路径）", "(No log file path configured for this service)")
            return
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            placeholderMessage = L("（日志文件尚不存在: \(path)）", "(Log file does not exist yet: \(path))")
            return
        }

        self.watcher = FileWatcher(
            url: url,
            onAppend: { [weak self] appendedChunk, totalSize in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.fileSize = totalSize
                    self.appendRawChunk(appendedChunk, isInitial: self.lines.isEmpty && !self.isTruncated)
                }
            },
            onReset: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.loadLog(for: path)
                }
            }
        )
    }

    /// 追加新读取的文本块并维持有界行数
    private func appendRawChunk(_ chunk: String, isInitial: Bool) {
        let combined = pendingPartialLine + chunk
        let rawLines = combined.components(separatedBy: .newlines)

        // 最后一个元素可能是未读完的半行
        if chunk.hasSuffix("\n") {
            pendingPartialLine = ""
        } else {
            pendingPartialLine = rawLines.last ?? ""
        }

        let completeLines = chunk.hasSuffix("\n") ? rawLines : Array(rawLines.dropLast())
        guard !completeLines.isEmpty else { return }

        lines.append(contentsOf: completeLines)

        // 若总行数超过最大展示限制，裁剪最旧的历史行
        if lines.count > Self.maxDisplayLines {
            let overflow = lines.count - Self.maxDisplayLines
            lines.removeFirst(overflow)
            isTruncated = true
        } else if isInitial && fileSize > 64 * 1024 {
            // 首次读取且原文件大于 64KB，明确标记已被截断
            isTruncated = true
        }
    }

    /// 一键清屏：仅清空当前内存中的控制台显示，不删除物理磁盘文件
    public func clear() {
        lines.removeAll()
        pendingPartialLine = ""
    }

    public func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    /// 过滤后的日志行（直接基于有界数组 O(N) 过滤，无多余大字符串切割开销）
    public var filteredLines: [String] {
        if filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return lines
        }
        return lines.filter { $0.localizedCaseInsensitiveContains(filterText) }
    }
}
