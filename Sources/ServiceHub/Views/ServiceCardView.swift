import SwiftUI

@MainActor
struct ServiceCardView: View {
    let service: Service
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @ObservedObject var supervisor = Supervisor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // 头部：左侧[图标 + 大名称/小ID]  右侧[状态Badge]
            HStack(alignment: .center, spacing: 10) {
                ServiceIconView(service: service, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    Text(service.id)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if supervisor.isBusy[service.id] == true {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(currentStatus.color)
                            .frame(width: 6, height: 6)
                        Text(currentStatus.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(currentStatus.color)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(currentStatus.color.opacity(0.12))
                    .cornerRadius(6)
                }
            }

            // 中部指标：PID、运行时长、熔断提示、前置条件标签
            HStack(spacing: 8) {
                if let pid = runtimeInfo.pid, currentStatus == .running {
                    Label("\(pid)", systemImage: "cpu")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary)
                }

                if let uptime = runtimeInfo.uptime, currentStatus == .running {
                    Label(uptime, systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if currentStatus == .waitingPrecondition {
                    Label(runtimeInfo.uptime ?? "等待条件", systemImage: "hourglass")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                } else if supervisor.isCircuitBroken[service.id] == true {
                    Label("已暂停保活", systemImage: "exclamationmark.octagon.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.red)
                } else if currentStatus == .stopped {
                    Text("未运行")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if service.precondition != .none && currentStatus != .running {
                    Text(service.precondition.shortName)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            .frame(height: 18)

            Divider()

            // 底部快捷操作按钮栏
            HStack(spacing: 6) {
                if currentStatus == .running {
                    Button(action: { Task { await supervisor.stopService(service) } }) {
                        Label("关闭", systemImage: "stop.fill")
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
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20, height: 20)
            }
        }
        .padding(11)
        // 核心视觉：根据运行状态与未运行状态做鲜明高对比底色
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(cardBorderColor, lineWidth: isSelected ? 2 : 1)
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

    /// 根据运行中/已停止等状态分配高对比度底色
    private var cardBackgroundColor: Color {
        switch currentStatus {
        case .running:
            // 运行中：带有轻微清爽的翡翠绿/强调色呼吸感底色
            return Color.green.opacity(0.06).opacity(1.0)
        case .waitingPrecondition:
            // 等待前置条件：带有温和的暖橙色底色
            return Color.orange.opacity(0.06)
        case .failed:
            // 异常/熔断：微淡红色底色
            return Color.red.opacity(0.07)
        default:
            // 已停止/未启动：采用中性暗灰/低调底色，与运行状态形成极强反差
            return Color(NSColor.windowBackgroundColor).opacity(0.65)
        }
    }

    /// 边框描边颜色
    private var cardBorderColor: Color {
        if isSelected {
            return Color.accentColor
        }
        switch currentStatus {
        case .running:
            return Color.green.opacity(0.28)
        case .waitingPrecondition:
            return Color.orange.opacity(0.3)
        case .failed:
            return Color.red.opacity(0.35)
        default:
            return Color.secondary.opacity(0.12)
        }
    }
}
