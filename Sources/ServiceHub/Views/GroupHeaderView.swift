import SwiftUI

@MainActor
struct GroupHeaderView: View {
    let group: ServiceGroup?
    let services: [Service]
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    var onEditGroup: (() -> Void)? = nil
    var onDeleteGroup: (() -> Void)? = nil

    @ObservedObject var supervisor = Supervisor.shared
    @ObservedObject var localization = Localization.shared
    @State private var isHovered: Bool = false
    @State private var showStartConfirm: Bool = false
    @State private var showStopConfirm: Bool = false

    private var groupName: String {
        group?.name ?? L("未分组", "Ungrouped")
    }

    private var groupIcon: String {
        group?.icon.isEmpty == false ? (group?.icon ?? "folder") : "folder"
    }

    private var runningCount: Int {
        services.filter { supervisor.statuses[$0.id] == .running }.count
    }

    private var totalCount: Int {
        services.count
    }

    var body: some View {
        HStack(spacing: 8) {
            // 折叠/展开按钮与标题区
            Button(action: onToggleCollapse) {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .animation(.easeInOut(duration: 0.18), value: isCollapsed)

                    Image(systemName: group != nil ? groupIcon : "tray")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)

                    Text(groupName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    // 计数与状态 Badge
                    HStack(spacing: 4) {
                        Text("\(totalCount)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)

                        if runningCount > 0 {
                            Text("•")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 5, height: 5)
                                Text(L("\(runningCount) 运行中", "\(runningCount) running"))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05), in: Capsule())
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // 批量控制按钮与分组菜单
            if !services.isEmpty {
                HStack(spacing: 4) {
                    // 一键启动
                    let canStart = runningCount < totalCount
                    Button(action: {
                        showStartConfirm = true
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                            Text(L("一键启动", "Start All"))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(canStart ? .accentColor : .secondary.opacity(0.5))
                    .background(canStart ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                    .disabled(!canStart)
                    .help(L("一键启动该组所有未运行的服务", "Start all stopped services in this group"))

                    // 一键停止
                    let canStop = runningCount > 0
                    Button(action: {
                        showStopConfirm = true
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 8))
                            Text(L("一键停止", "Stop All"))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(canStop ? .red : .secondary.opacity(0.5))
                    .background(canStop ? Color.red.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                    .disabled(!canStop)
                    .help(L("一键停止该组所有正在运行的服务", "Stop all running services in this group"))
                }
            }

            // 分组管理菜单（仅针对自定义分组，未分组不展示）
            if group != nil {
                Menu {
                    if let onEdit = onEditGroup {
                        Button(action: onEdit) {
                            Label(L("编辑分组...", "Edit Group..."), systemImage: "pencil")
                        }
                    }

                    if let onDelete = onDeleteGroup {
                        Divider()
                        Button(role: .destructive, action: onDelete) {
                            Label(L("删除分组", "Delete Group"), systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .background(Color.primary.opacity(isHovered ? 0.08 : 0.03), in: RoundedRectangle(cornerRadius: 4))
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .help(L("分组设置", "Group Options"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.02))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .alert(
            L("确定启动分组「\(groupName)」中的全部服务吗？", "Start all services in group \"\(groupName)\"?"),
            isPresented: $showStartConfirm
        ) {
            Button(L("取消", "Cancel"), role: .cancel) {}
            Button(L("启动全部", "Start All")) {
                supervisor.startServices(in: group?.id)
            }
        } message: {
            Text(L("将启动该分组内尚未运行的 \(totalCount - runningCount) 个服务。", "Will start \(totalCount - runningCount) stopped service(s) in this group."))
        }
        .alert(
            L("确定停止分组「\(groupName)」中的全部服务吗？", "Stop all services in group \"\(groupName)\"?"),
            isPresented: $showStopConfirm
        ) {
            Button(L("取消", "Cancel"), role: .cancel) {}
            Button(L("停止全部", "Stop All"), role: .destructive) {
                supervisor.stopServices(in: group?.id)
            }
        } message: {
            Text(L("将停止该分组内正在运行的 \(runningCount) 个服务，相关端口与网络连接将被中断。", "Will stop \(runningCount) running service(s) in this group. Active connections will be closed."))
        }
    }
}
