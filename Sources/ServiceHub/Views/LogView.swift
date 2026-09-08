import SwiftUI

@MainActor
struct LogView: View {
    let service: Service
    /// 可选头部内容（如控制台标题），与搜索行合并到同一行
    var header: AnyView? = nil
    @StateObject private var logTail = LogTail()

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏（标题、搜索、行数统计、清屏与操作按钮）
            HStack(spacing: 10) {
                if let header {
                    header
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1, height: 14)
                }

                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField(L("过滤日志关键词...", "Filter logs..."), text: $logTail.filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !logTail.filterText.isEmpty {
                    Button(action: { logTail.filterText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // 行数统计与截断指示
                if !logTail.lines.isEmpty {
                    Text(L("最新 \(logTail.lines.count) 行", "Latest \(logTail.lines.count) lines"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }

                // 一键清屏按钮
                Button(action: { logTail.clear() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("清空控制台当前日志（不影响物理原文件）", "Clear current console buffer (does not delete log file)"))
                .disabled(logTail.lines.isEmpty)

                Toggle(isOn: $logTail.isFollowing) {
                    Text(L("跟踪滚动", "Follow"))
                        .font(.system(size: 11))
                }
                .toggleStyle(.checkbox)

                if let logPath = service.logPath, FileManager.default.fileExists(atPath: logPath) {
                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: logPath)])
                    }) {
                        Label(L("在访达中显示", "Reveal in Finder"), systemImage: "folder")
                            .font(.system(size: 11))
                    }
                    .liquidGlassButton()
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 日志文本区域
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        // 顶部截断提示与完整日志引导条
                        if logTail.isTruncated {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text(L("已限制实时展示最新的 \(LogTail.maxDisplayLines) 行日志，以保持极速流畅与极低内存占用。",
                                       "Showing latest \(LogTail.maxDisplayLines) lines to ensure optimal performance and minimal memory."))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)

                                Spacer()

                                if let logPath = service.logPath, FileManager.default.fileExists(atPath: logPath) {
                                    Button(action: {
                                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: logPath)])
                                    }) {
                                        Text(L("打开完整原文件 ↗", "Open Full File ↗"))
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                            .padding(.bottom, 4)
                        }

                        if let placeholder = logTail.placeholderMessage, logTail.lines.isEmpty {
                            Text(placeholder)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.top, 12)
                        } else {
                            ForEach(Array(logTail.filteredLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(colorForLine(line))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                    }
                    .padding(10)
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: logTail.filteredLines.count) { _ in
                    if logTail.isFollowing, let lastIndex = logTail.filteredLines.indices.last {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
        }
        .onAppear {
            logTail.loadLog(for: service.logPath)
        }
        .onChange(of: service.logPath) { newPath in
            logTail.loadLog(for: newPath)
        }
    }

    private func colorForLine(_ line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("fail") || lower.contains("[e]") {
            return .red
        } else if lower.contains("warn") || lower.contains("[w]") {
            return .orange
        } else if lower.contains("info") || lower.contains("[i]") || lower.contains("success") {
            return .primary
        }
        return .secondary
    }
}
