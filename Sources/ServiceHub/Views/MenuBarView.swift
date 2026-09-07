import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store = ServiceStore.shared
    @ObservedObject var supervisor = Supervisor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶栏：标题与状态概览
            HStack {
                Image(systemName: "server.rack")
                    .foregroundColor(.accentColor)
                Text("ServiceHub 服务列表")
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
                .help("重新检测状态")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 核心列表：每条服务独立一个 item
            if store.services.isEmpty {
                VStack(spacing: 6) {
                    Text("尚未配置任何服务")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.services) { s in
                        let st = supervisor.statuses[s.id] ?? .unknown
                        let rt = supervisor.runtimes[s.id]
                        let isBusy = supervisor.isBusy[s.id] == true

                        HStack(spacing: 10) {
                            ServiceIconView(service: s, size: 26)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)

                                HStack(spacing: 6) {
                                    HStack(spacing: 3) {
                                        Circle()
                                            .fill(st.color)
                                            .frame(width: 6, height: 6)
                                        Text(st.displayName)
                                            .font(.system(size: 10))
                                            .foregroundColor(st.color)
                                    }

                                    if let pid = rt?.pid, st == .running {
                                        Text("PID: \(pid)")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }

                                    if let uptime = rt?.uptime, st == .running {
                                        Text("⏱ \(uptime)")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }

                            Spacer()

                            // 每一个服务独立的控制按钮组：启动 / 关闭 / 重启
                            if isBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 60)
                            } else if st == .running {
                                HStack(spacing: 6) {
                                    Button("关闭") {
                                        Task { await supervisor.stopService(s) }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("重启") {
                                        Task { await supervisor.restartService(s) }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            } else {
                                Button("启动") {
                                    Task { await supervisor.startService(s) }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                    }
                }
                .padding(12)
            }

            Divider()

            // 底部操作栏
            HStack {
                Button(action: openMainWindow) {
                    Label("打开主控制面板", systemImage: "macwindow")
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
        .frame(width: 360)
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
