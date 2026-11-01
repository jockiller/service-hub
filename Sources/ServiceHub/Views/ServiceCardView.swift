import SwiftUI

@MainActor
struct ServiceCardView: View {
    let service: Service
    let isSelected: Bool
    var isDraggable: Bool = true
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @ObservedObject var supervisor = Supervisor.shared
    @ObservedObject var tunnelManager = CloudflareTunnelManager.shared
    @ObservedObject var localization = Localization.shared

    @Environment(\.colorScheme) private var colorScheme

    @State private var showStopConfirm = false
    @State private var showRestartConfirm = false
    @State private var showUpdateConfirm = false
    @State private var showAlreadyLatestAlert = false

    var body: some View {
        let isRunning = currentStatus == .running

        VStack(alignment: .leading, spacing: 9) {
            // 头部：左侧 [图标 + 大名称/小ID]  右侧 [状态胶囊]
            HStack(alignment: .center, spacing: 9) {
                ServiceIconView(service: service, size: 32)

                VStack(alignment: .leading, spacing: 2.5) {
                    Text(service.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(service.category.shortName)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(service.category.color)
                            .lineLimit(1)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(service.category.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                            .fixedSize()

                        Text(service.id)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    if supervisor.isUpdatingServices[service.id] == true {
                        HStack(spacing: 3) {
                            ProgressView().controlSize(.mini)
                            Text(L("更新中...", "Updating..."))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.blue)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 2.5)
                        .background(Color.blue.opacity(0.14), in: Capsule(style: .continuous))
                        .fixedSize()
                    } else if supervisor.updatesAvailable[service.id] == true {
                        Button(action: { showUpdateConfirm = true }) {
                            HStack(spacing: 2.5) {
                                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                    .font(.system(size: 9))
                                Text(L("可更新", "Update"))
                                    .font(.system(size: 9, weight: .bold))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.blue.opacity(0.16), in: Capsule(style: .continuous))
                            .foregroundColor(.blue)
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                        .help(supervisor.updateInfos[service.id] ?? L("有新版本可用，点击立即更新并重启", "New version available, click to update & restart"))
                    }

                    if supervisor.isBusy[service.id] == true {
                        ProgressView().controlSize(.small)
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(isRunning ? Color(red: 0.05, green: 0.22, blue: 0.10) : currentStatus.color)
                                .frame(width: 5.5, height: 5.5)
                            Text(currentStatus.displayName)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(isRunning ? Color(red: 0.05, green: 0.22, blue: 0.10) : currentStatus.color)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            isRunning
                                ? Color(red: 0.30, green: 0.88, blue: 0.52)
                                : currentStatus.color.opacity(0.14),
                            in: Capsule(style: .continuous)
                        )
                        .fixedSize()
                    }

                    if isDraggable {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.35))
                            .help(L("拖拽可调整卡片顺序或跨组移动", "Drag to reorder or move to another group"))
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            // 中部扁平指标标签行
            HStack(spacing: 6) {
                if tunnelManager.isTunnelActive(for: service.id) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.purple)
                        .frame(width: 2.5, height: 14)
                }

                if let pid = runtimeInfo.pid, isRunning {
                    ProBadgeView("\(pid)", icon: "cpu", tint: .primary, isMonospaced: true)
                }

                if let uptime = runtimeInfo.uptime, isRunning {
                    ProBadgeView(uptime, icon: "clock", tint: .secondary)
                } else if currentStatus == .waitingPrecondition {
                    ProBadgeView(runtimeInfo.uptime ?? L("等待条件", "Waiting"), icon: "hourglass", tint: .orange)
                } else if supervisor.isCircuitBroken[service.id] == true {
                    ProBadgeView(L("已暂停保活", "Keep-alive paused"), icon: "exclamationmark.octagon.fill", tint: .red)
                } else if currentStatus == .stopped {
                    Text(L("未运行", "Stopped"))
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if service.precondition != .none && !isRunning {
                    ProBadgeView(service.precondition.shortName, tint: .secondary)
                }
            }
            .frame(height: 20)

            // 公网映射状态槽位（保持等高对齐）
            HStack(spacing: 5) {
                if let pubUrl = tunnelManager.publicUrls[service.id] {
                    Image(systemName: "globe")
                        .font(.system(size: 10))
                        .foregroundColor(.purple)
                    Text(pubUrl)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.purple)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(pubUrl, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundColor(.purple.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help(L("复制公网链接", "Copy public URL"))

                    Button(action: {
                        if let u = URL(string: pubUrl) { NSWorkspace.shared.open(u) }
                    }) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 9))
                            .foregroundColor(.purple.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help(L("在浏览器打开公网链接", "Open public URL in browser"))
                } else if tunnelManager.isConnecting[service.id] == true {
                    ProgressView().controlSize(.mini)
                    Text(tunnelManager.tunnelStates[service.id] ?? L("正在建立公网隧道...", "Establishing tunnel..."))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(
                Group {
                    if tunnelManager.publicUrls[service.id] != nil {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.purple.opacity(0.12))
                    }
                }
            )

            Divider().opacity(0.35)

            // 底部快捷操作按钮栏
            HStack(spacing: 6) {
                if isRunning {
                    Button(action: { showStopConfirm = true }) {
                        HStack(spacing: 3.5) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9))
                            Text(L("关闭", "Stop"))
                        }
                    }
                    .proButton(tint: .red)
                    .controlSize(.small)
                    .disabled(isBusy)

                    Button(action: { showRestartConfirm = true }) {
                        Text(L("重启", "Restart"))
                    }
                    .proButton(tint: .blue)
                    .controlSize(.small)
                    .disabled(isBusy)
                    .help(L("重启服务", "Restart service"))
                } else {
                    Button(action: { Task { await supervisor.startService(service) } }) {
                        HStack(spacing: 3.5) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                            Text(L("启动", "Start"))
                        }
                    }
                    .proButton(tint: .accentColor, isProminent: true)
                    .controlSize(.small)
                    .disabled(isBusy)
                }

                if let webStr = service.webURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !webStr.isEmpty,
                   let url = URL(string: webStr) {
                    Button(action: { NSWorkspace.shared.open(url) }) {
                        Image(systemName: "safari")
                            .font(.system(size: 11))
                    }
                    .proButton(tint: .blue)
                    .controlSize(.small)
                    .help(L("打开服务主页: \(webStr)", "Open homepage: \(webStr)"))

                    let isTunneled = tunnelManager.isTunnelActive(for: service.id)
                    Button(action: toggleTunnel) {
                        HStack(spacing: 3) {
                            Image(systemName: isTunneled ? "globe.badge.chevron.backward" : "globe")
                                .font(.system(size: 10))
                            Text(isTunneled ? L("断开", "Disconnect") : L("公网", "Public"))
                                .font(.system(size: 10))
                        }
                    }
                    .proButton(tint: .purple)
                    .controlSize(.small)
                    .help(isTunneled ? L("点击断开当前公网映射", "Click to disconnect the public tunnel") : L("通过 Cloudflare 隧道一键将本地服务映射到公网", "Expose this service via a Cloudflare Tunnel"))
                }

                Spacer()

                Menu {
                    if let webStr = service.webURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !webStr.isEmpty,
                       let url = URL(string: webStr) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label(L("打开服务主页", "Open Homepage"), systemImage: "safari")
                        }
                        Divider()
                    }

                    Button(L("编辑服务配置...", "Edit Service...")) { onEdit() }
                    Button(L("手动刷新状态", "Refresh Status")) {
                        Task { await supervisor.probeService(service) }
                    }

                    Divider()
                    moveToGroupMenu

                    if service.checkUpdateEnabled {
                        Divider()
                        Button {
                            Task {
                                let res = await supervisor.checkUpdate(for: service)
                                switch res {
                                case .alreadyUpToDate: showAlreadyLatestAlert = true
                                case .updateAvailable: showUpdateConfirm = true
                                case .failed: break
                                }
                            }
                        } label: {
                            Label(
                                supervisor.isCheckingUpdates[service.id] == true
                                    ? L("正在检测更新...", "Checking for updates...")
                                    : L("检查更新", "Check for Updates"),
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .disabled(supervisor.isCheckingUpdates[service.id] == true || supervisor.isUpdatingServices[service.id] == true)

                        if supervisor.updatesAvailable[service.id] == true || (service.updateCommand != nil && !service.updateCommand!.isEmpty) {
                            Button { showUpdateConfirm = true } label: {
                                Label(L("立即更新并重启", "Update and Restart"), systemImage: "arrow.triangle.2.circlepath")
                            }
                            .disabled(supervisor.isUpdatingServices[service.id] == true)
                        }
                    }

                    Divider()
                    Button(L("删除服务", "Delete Service"), role: .destructive) { onDelete() }
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
        .padding(14)
        .proCard(statusColor: currentStatus.color, isSelected: isSelected, cornerRadius: ProTheme.cornerRadiusCard)
        .contentShape(RoundedRectangle(cornerRadius: ProTheme.cornerRadiusCard))
        .modifier(OptionalCardDraggable(id: service.id, enabled: isDraggable, service: service))
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            cardContextMenu
        }
        .alert(L("确定关闭服务「\(service.name)」吗？", "Stop service \"\(service.name)\"?"), isPresented: $showStopConfirm) {
            Button(L("取消", "Cancel"), role: .cancel) {}
            Button(L("关闭服务", "Stop Service"), role: .destructive) {
                Task { await supervisor.stopService(service) }
            }
        } message: {
            Text(L("关闭后该服务将停止运行，相关端口和本地/公网访问将被中断。", "The service process will be terminated and all active connections will be closed."))
        }
        .alert(L("确定重启服务「\(service.name)」吗？", "Restart service \"\(service.name)\"?"), isPresented: $showRestartConfirm) {
            Button(L("取消", "Cancel"), role: .cancel) {}
            Button(L("重启服务", "Restart")) {
                Task { await supervisor.restartService(service) }
            }
        } message: {
            Text(L("重启期间服务将短暂不可用，随后将自动重新启动。", "The service will be temporarily interrupted, then automatically restarted."))
        }
        .alert(L("已是最新版本", "Already Up to Date"), isPresented: $showAlreadyLatestAlert) {
            Button(L("确定", "OK"), role: .cancel) {}
        } message: {
            Text(L("服务「\(service.name)」当前已是最新版本，无需更新。", "Service \"\(service.name)\" is already up to date."))
        }
        .alert(L("确定更新服务「\(service.name)」吗？", "Update service \"\(service.name)\"?"), isPresented: $showUpdateConfirm) {
            Button(L("取消", "Cancel"), role: .cancel) {}
            Button(L("立即更新并重启", "Update & Restart")) {
                Task { await supervisor.performUpdate(for: service) }
            }
        } message: {
            if let info = supervisor.updateInfos[service.id], !info.isEmpty {
                Text(L("检测到更新内容: \(info)\n更新完成后将自动重启该服务。", "Detected update: \(info)\nThe service will be restarted automatically."))
            } else {
                Text(L("更新完成后将自动重启该服务。", "The service will be restarted automatically after updating."))
            }
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

    private func toggleTunnel() {
        if tunnelManager.isTunnelActive(for: service.id) {
            tunnelManager.stopTunnel(for: service.id)
        } else {
            tunnelManager.startTunnel(for: service)
        }
    }

    @ViewBuilder
    private var moveToGroupMenu: some View {
        Menu(L("移至分组", "Move to Group")) {
            Button(action: {
                ServiceStore.shared.setServiceGroup(serviceId: service.id, groupId: nil)
            }) {
                HStack {
                    Text(L("未分组", "Ungrouped"))
                    if service.groupId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            if !ServiceStore.shared.groups.isEmpty {
                Divider()
                ForEach(ServiceStore.shared.groups) { g in
                    Button(action: {
                        ServiceStore.shared.setServiceGroup(serviceId: service.id, groupId: g.id)
                    }) {
                        HStack {
                            Text(g.name)
                            if service.groupId == g.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var cardContextMenu: some View {
        if currentStatus == .running {
            Button(L("停止服务", "Stop Service")) {
                showStopConfirm = true
            }
            Button(L("重启服务", "Restart")) {
                showRestartConfirm = true
            }
        } else {
            Button(L("启动服务", "Start Service")) {
                Task { await supervisor.startService(service) }
            }
        }

        Divider()

        moveToGroupMenu

        Divider()

        if let webStr = service.webURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !webStr.isEmpty,
           let url = URL(string: webStr) {
            Button(L("打开服务主页", "Open Homepage")) {
                NSWorkspace.shared.open(url)
            }
        }

        Button(L("编辑服务配置...", "Edit Service...")) {
            onEdit()
        }

        Button(L("手动刷新状态", "Refresh Status")) {
            Task { await supervisor.probeService(service) }
        }

        Divider()

        Button(L("删除服务", "Delete Service"), role: .destructive) {
            onDelete()
        }
    }
}

// MARK: - 可选拖拽修饰器
private struct OptionalCardDraggable: ViewModifier {
    let id: String
    let enabled: Bool
    let service: Service

    func body(content: Content) -> some View {
        if enabled {
            content.draggable(id) {
                HStack(spacing: 8) {
                    ServiceIconView(service: service, size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text(service.id)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
            }
        } else {
            content
        }
    }
}
