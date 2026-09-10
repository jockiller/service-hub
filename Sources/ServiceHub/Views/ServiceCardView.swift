import SwiftUI

@MainActor
struct ServiceCardView: View {
    let service: Service
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @ObservedObject var supervisor = Supervisor.shared
    @ObservedObject var tunnelManager = CloudflareTunnelManager.shared
    @ObservedObject var localization = Localization.shared

    @State private var showStopConfirm = false
    @State private var showRestartConfirm = false
    @State private var showUpdateConfirm = false
    @State private var showAlreadyLatestAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // 头部：左侧[图标 + 大名称/小ID]  右侧[状态Badge]
            HStack(alignment: .center, spacing: 10) {
                ServiceIconView(service: service, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(service.category.shortName)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(service.category.color)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(service.category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 3.5))

                        Text(service.id)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if supervisor.isUpdatingServices[service.id] == true {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text(L("更新中...", "Updating..."))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2.5)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(4.5)
                } else if supervisor.updatesAvailable[service.id] == true {
                    Button(action: {
                        showUpdateConfirm = true
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                .font(.system(size: 9))
                            Text(L("可更新", "Update"))
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 2.5)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(4.5)
                    }
                    .buttonStyle(.plain)
                    .help(supervisor.updateInfos[service.id] ?? L("有新版本可用，点击立即更新并重启", "New version available, click to update & restart"))
                }

                if supervisor.isBusy[service.id] == true {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    HStack(spacing: 4.5) {
                        StatusDotView(color: currentStatus.color, size: 6.5)
                        Text(currentStatus.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(currentStatus.color)
                    }
                    .padding(.horizontal, 6.5)
                    .padding(.vertical, 2.5)
                    .background(currentStatus.color.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5)
                            .strokeBorder(currentStatus.color.opacity(0.22), lineWidth: 0.5)
                    )
                    .cornerRadius(4.5)
                }
            }

            // 中部指标：公网竖条、PID、运行时长、熔断提示、前置条件标签
            HStack(spacing: 6) {
                // 公网暴露标识：左侧 2.5pt 紫色极简竖条
                if tunnelManager.isTunnelActive(for: service.id) {
                    RoundedRectangle(cornerRadius: 1.2)
                        .fill(Color.purple)
                        .frame(width: 2.5, height: 14)
                }

                if let pid = runtimeInfo.pid, currentStatus == .running {
                    ProBadgeView("\(pid)", icon: "cpu", tint: .primary, isMonospaced: true)
                }

                if let uptime = runtimeInfo.uptime, currentStatus == .running {
                    ProBadgeView(uptime, icon: "clock", tint: .secondary)
                } else if currentStatus == .waitingPrecondition {
                    ProBadgeView(runtimeInfo.uptime ?? L("等待条件", "Waiting"), icon: "hourglass", tint: .orange)
                } else if supervisor.isCircuitBroken[service.id] == true {
                    ProBadgeView(L("已暂停保活", "Keep-alive paused"), icon: "exclamationmark.octagon.fill", tint: .red)
                } else if currentStatus == .stopped {
                    Text(L("未运行", "Stopped"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if service.precondition != .none && currentStatus != .running {
                    ProBadgeView(service.precondition.shortName, tint: .secondary)
                }
            }
            .frame(height: 18)

            // 公网映射状态与分配的公网 URL —— 固定高度槽位：无论是否有隧道都占位 22pt，
            // 保证同一排卡片等高、底部按钮栏完全对齐，出现/消失时不再引起高度跳变
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
            .frame(height: 22)
            .background(
                Group {
                    if tunnelManager.publicUrls[service.id] != nil {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.purple.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Color.purple.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                }
            )

            Divider()

            // 底部快捷操作按钮栏
            HStack(spacing: 5) {
                if currentStatus == .running {
                    Button(action: { showStopConfirm = true }) {
                        HStack(spacing: 3) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9))
                            Text(L("关闭", "Stop"))
                                .font(.system(size: 11))
                        }
                    }
                    .proButton(tint: .red)
                    .controlSize(.small)
                    .disabled(isBusy)

                    Button(action: { showRestartConfirm = true }) {
                        Text(L("重启", "Restart"))
                            .font(.system(size: 11))
                    }
                    .proButton(tint: .blue)
                    .controlSize(.small)
                    .disabled(isBusy)
                    .help(L("重启服务", "Restart service"))
                } else {
                    Button(action: { Task { await supervisor.startService(service) } }) {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                            Text(L("启动", "Start"))
                                .font(.system(size: 11))
                        }
                    }
                    .proButton(tint: .green)
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
                }

                // 公网映射快捷按钮 —— 仅对配置了服务主页的服务开放
                let isTunneled = tunnelManager.isTunnelActive(for: service.id)
                let hasWebURL = service.webURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                if hasWebURL {
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

                    Button(L("编辑服务配置...", "Edit Service...")) {
                        onEdit()
                    }
                    Button(L("手动刷新状态", "Refresh Status")) {
                        Task { await supervisor.probeService(service) }
                    }

                    if service.checkUpdateEnabled {
                        Divider()
                        Button {
                            Task {
                                let res = await supervisor.checkUpdate(for: service)
                                switch res {
                                case .alreadyUpToDate:
                                    showAlreadyLatestAlert = true
                                case .updateAvailable:
                                    showUpdateConfirm = true
                                case .failed:
                                    break
                                }
                            }
                        } label: {
                            if supervisor.isCheckingUpdates[service.id] == true {
                                Label(L("正在检测更新...", "Checking for updates..."), systemImage: "arrow.clockwise")
                            } else {
                                Label(L("检查更新", "Check for Updates"), systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(supervisor.isCheckingUpdates[service.id] == true || supervisor.isUpdatingServices[service.id] == true)

                        if supervisor.updatesAvailable[service.id] == true || (service.updateCommand != nil && !service.updateCommand!.isEmpty) {
                            Button {
                                showUpdateConfirm = true
                            } label: {
                                Label(L("立即更新并重启", "Update and Restart"), systemImage: "arrow.triangle.2.circlepath")
                            }
                            .disabled(supervisor.isUpdatingServices[service.id] == true)
                        }
                    }

                    Divider()
                    Button(L("删除服务", "Delete Service"), role: .destructive) {
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
        .padding(12)
        // Raycast / Linear 风格精密专业卡片
        .proCard(statusColor: currentStatus.color, isSelected: isSelected, cornerRadius: ProTheme.cornerRadiusCard)
        .contentShape(RoundedRectangle(cornerRadius: ProTheme.cornerRadiusCard))
        .onTapGesture {
            onSelect()
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
}
