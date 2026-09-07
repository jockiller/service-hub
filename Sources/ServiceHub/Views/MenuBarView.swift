import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store = ServiceStore.shared
    @ObservedObject var supervisor = Supervisor.shared

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            HStack {
                Image(systemName: "server.rack")
                    .foregroundColor(.accentColor)
                Text("ServiceHub")
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                let runningCount = store.services.filter { supervisor.statuses[$0.id] == .running }.count
                Text("\(runningCount)/\(store.services.count) 运行中")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(4)

                Button(action: { Task { await supervisor.probeAllServices() } }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("刷新状态")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 服务列表
            ScrollView {
                VStack(spacing: 6) {
                    if store.services.isEmpty {
                        Text("暂无服务")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(20)
                    } else {
                        ForEach(store.services) { s in
                            let st = supervisor.statuses[s.id] ?? .unknown
                            let isBusy = supervisor.isBusy[s.id] == true

                            HStack(spacing: 8) {
                                ServiceIconView(service: s, size: 20)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(st.color)
                                            .frame(width: 6, height: 6)
                                        Text(st.displayName)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                if isBusy {
                                    ProgressView().controlSize(.small)
                                        .frame(width: 44)
                                } else if st == .running {
                                    Button("停止") {
                                        Task { await supervisor.stopService(s) }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Button("启动") {
                                        Task { await supervisor.startService(s) }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(NSColor.controlBackgroundColor))
                            )
                        }
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 320)

            Divider()

            // 底部操作区
            HStack {
                Button(action: openMainWindow) {
                    Label("打开主窗口", systemImage: "macwindow")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { NSApp.terminate(nil) }) {
                    Text("退出")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 290)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            if window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
