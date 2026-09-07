import SwiftUI

@MainActor
struct LogView: View {
    let service: Service
    @StateObject private var logTail = LogTail()

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("过滤日志关键词...", text: $logTail.filterText)
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
                    Label("跟踪滚动", systemImage: "arrow.down.to.line")
                        .font(.system(size: 11))
                }
                .toggleStyle(.checkbox)

                if let logPath = service.logPath, FileManager.default.fileExists(atPath: logPath) {
                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: logPath)])
                    }) {
                        Label("在访达中显示", systemImage: "folder")
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
