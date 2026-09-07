import Foundation
import SwiftUI

private final class FileWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private var lastOffset: UInt64 = 0
    private let url: URL
    private let onAppend: @Sendable (String) -> Void
    private let onReset: @Sendable () -> Void

    init(url: URL, onAppend: @escaping @Sendable (String) -> Void, onReset: @escaping @Sendable () -> Void) {
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
            let readSize: UInt64 = min(fileSize, 100 * 1024) // 预读 100KB
            handle.seek(toFileOffset: fileSize - readSize)
            let data = handle.readDataToEndOfFile()
            handle.closeFile()

            lastOffset = fileSize
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                onAppend(str)
            }
        } catch {
            return
        }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete], queue: .global(qos: .utility))
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
                    onAppend(str)
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
    @Published public var logContent: String = ""
    @Published public var filterText: String = ""
    @Published public var isFollowing: Bool = true

    private var watcher: FileWatcher?

    public init() {}

    public func loadLog(for path: String?) {
        watcher?.stop()
        watcher = nil
        logContent = ""

        guard let path = path, !path.isEmpty else {
            logContent = "（该服务未配置日志文件路径）"
            return
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            logContent = "（日志文件尚不存在: \(path)）"
            return
        }

        self.watcher = FileWatcher(
            url: url,
            onAppend: { [weak self] appendedText in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.logContent.append(appendedText)
                    if self.logContent.count > 300_000 {
                        self.logContent = String(self.logContent.suffix(200_000))
                    }
                }
            },
            onReset: { [weak self] in
                Task { @MainActor in
                    self?.loadLog(for: path)
                }
            }
        )
    }

    public func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    public var filteredLines: [String] {
        let all = logContent.components(separatedBy: .newlines)
        if filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return all
        }
        return all.filter { $0.localizedCaseInsensitiveContains(filterText) }
    }
}
