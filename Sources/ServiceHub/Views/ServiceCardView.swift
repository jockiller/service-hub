import SwiftUI

struct ServiceCardView: View {
    let service: Service
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @ObservedObject var supervisor = Supervisor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶部：图标 + 状态徽章 + 忙碌转轮
            HStack(alignment: .top) {
                ServiceIconView(service: service, size: 36)

                Spacer()

                if supervisor.isBusy[service.id] == true {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    // 状态 Badge
                    HStack(spacing: 5) {
                        Circle()
                            .fill(currentStatus.color)
                            .frame(width: 7, height: 7)
                        Text(currentStatus.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(currentStatus.color)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(currentStatus.color.opacity(0.12))
                    .cornerRadius(8)
                }
            }

            // 中部：服务名称与 ID
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(service.id)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // 核心指标：PID 与 启动时间 / 运行时长
            HStack(spacing: 12) {
                if let pid = runtimeInfo.pid, currentStatus == .running {
                    Label("PID: \(pid)", systemImage: "cpu")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                } else {
                    Label("PID: --", systemImage: "cpu")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                if let uptime = runtimeInfo.uptime, currentStatus == .running {
                    Label(uptime, systemImage: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 2)

            Divider()

            // 底部快捷操作栏
            HStack(spacing: 6) {
                if currentStatus == .running {
                    Button(action: { Task { await supervisor.stopService(service) } }) {
                        Label("停止", systemImage: "stop.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isBusy)

                    Button(action: { Task { await supervisor.restartService(service) } }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isBusy)
                    .help("重启服务")
                } else {
                    Button(action: { Task { await supervisor.startService(service) } }) {
                        Label("启动", systemImage: "play.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isBusy)
                }

                Spacer()

                Menu {
                    Button("编辑服务配置...") {
                        onEdit()
                    }
                    Button("手动刷新状态") {
                        Task { await supervisor.probeService(service) }
                    }
                    Divider()
                    Button("删除服务", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    private var currentStatus: ServiceStatus {
        supervisor.statuses[service.id] ?? .unknown
    }

    private var runtimeInfo: ServiceRuntimeInfo {
        supervisor.runtimes[service.id] ?? ServiceRuntimeInfo(status: currentStatus)
    }

    private var isBusy: Bool {
        supervisor.isBusy[service.id] == true
    }
}
