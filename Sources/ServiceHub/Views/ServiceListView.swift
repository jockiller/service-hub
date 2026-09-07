import SwiftUI

struct ServiceListView: View {
    let services: [Service]
    let selectedId: String?
    let onSelect: (Service) -> Void
    let onEdit: (Service) -> Void
    let onDelete: (Service) -> Void

    @ObservedObject var supervisor = Supervisor.shared

    var body: some View {
        List(selection: Binding(
            get: { selectedId },
            set: { if let id = $0, let s = services.first(where: { $0.id == id }) { onSelect(s) } }
        )) {
            ForEach(services) { s in
                HStack(spacing: 12) {
                    ServiceIconView(service: s, size: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text(s.id)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(minWidth: 140, alignment: .leading)

                    // 状态 Badge
                    let st = supervisor.statuses[s.id] ?? .unknown
                    HStack(spacing: 4) {
                        Circle()
                            .fill(st.color)
                            .frame(width: 7, height: 7)
                        Text(st.displayName)
                            .font(.system(size: 11))
                            .foregroundColor(st.color)
                    }
                    .frame(width: 80, alignment: .leading)

                    // 进程 PID
                    let rt = supervisor.runtimes[s.id]
                    if let pid = rt?.pid, st == .running {
                        Label("\(pid)", systemImage: "cpu")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 90, alignment: .leading)
                    } else {
                        Text("--")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 90, alignment: .leading)
                    }

                    // 启动时间 / 运行时长
                    if let uptime = rt?.uptime, st == .running {
                        Label(uptime, systemImage: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 120, alignment: .leading)
                    } else {
                        Text("--")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 120, alignment: .leading)
                    }

                    Spacer()

                    // 操作按钮组
                    let isBusy = supervisor.isBusy[s.id] == true
                    if isBusy {
                        ProgressView().controlSize(.small)
                            .frame(width: 60)
                    } else if st == .running {
                        HStack(spacing: 6) {
                            Button("停止") {
                                Task { await supervisor.stopService(s) }
                            }
                            .controlSize(.small)

                            Button(action: { Task { await supervisor.restartService(s) } }) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .controlSize(.small)
                            .help("重启")
                        }
                    } else {
                        Button("启动") {
                            Task { await supervisor.startService(s) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    Menu {
                        Button("编辑服务配置...") { onEdit(s) }
                        Button("刷新状态") { Task { await supervisor.probeService(s) } }
                        Divider()
                        Button("删除服务", role: .destructive) { onDelete(s) }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 20)
                }
                .padding(.vertical, 4)
                .tag(s.id)
            }
        }
        .listStyle(.inset)
    }
}
