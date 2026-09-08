import SwiftUI

@MainActor
struct LogView: View {
    let service: Service
    /// 可选头部内容（如控制台标题），与搜索行合并到同一行
    var header: AnyView? = nil
    @StateObject private var logTail = LogTail()

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏（标题与搜索合并为一行）
            HStack(spacing: 12) {
                if let header {
                    header
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1, height: 14)
                }

                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(L("过滤日志关键词...", "Filter logs..."), text: $logTail.filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !logTail.filterText.isEmpty {
                    Button(action: { logTail.filterText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

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
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 日志文本区域
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logTail.filteredLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(colorForLine(line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
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
