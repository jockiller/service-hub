import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store = ServiceStore.shared
    @ObservedObject var supervisor = Supervisor.shared

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题与全局批量操作
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .foregroundColor(.accentColor)
                Text("ServiceHub")
                    .font(.system(size: 13, weight: .bold))

                let runningCount = store.services.filter { supervisor.statuses[$0.id] == .running }.count
                Text("\(runningCount)/\(store.services.count)")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(4)

                Spacer()

                Button("全部启动") {
                    Task { await supervisor.startAllServices() }
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("全部停止") {
                    Task { await supervisor.stopAllServices() }
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button(action: { Task { await supervisor.probeAllServices() } }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("刷新状态")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 核心服务列表区域
            ScrollView {
                VStack(spacing: 6) {
                    if store.services.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "server.rack")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("尚未添加任何服务")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                    } else {
                        ForEach(store.services) { s in
                            let st = supervisor.statuses[s.id] ?? .unknown
                            let rt = supervisor.runtimes[s.id]
                            let isBusy = supervisor.isBusy[s.id] == true

                            HStack(spacing: 10) {
                                ServiceIconView(service: s, size: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.name)
                                        .font(.system(size: 12, weight: .semibold))
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
                                            Text("PID:\(pid)")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }

                                        if let uptime = rt?.uptime, st == .running {
                                            Text("⏱\(uptime)")
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }

                                Spacer()

                                // 操作按钮组：启动 / 停止 / 重启
                                if isBusy {
                                    ProgressView().controlSize(.small)
                                        .frame(width: 50)
                                } else if st == .running {
                                    HStack(spacing: 5) {
                                        Button("停止") {
                                            Task { await supervisor.stopService(s) }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Button(action: { Task { await supervisor.restartService(s) } }) {
                                            Image(systemName: "arrow.clockwise")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .help("重启服务")
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
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.controlBackgroundColor))
                            )
                        }
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 380)

            Divider()

            // 底部操作区
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
