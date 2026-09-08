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
                            .frame(width: 7, height: 7)
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

            // 中部指标：公网竖条、PID、运行时长、熔断提示、前置条件标签
            HStack(spacing: 8) {
                // 公网暴露标识：左侧 3pt 紫色渐变竖条（比 Badge 更克制，不挤压头部）
                if tunnelManager.isTunnelActive(for: service.id) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            LinearGradient(
                                colors: [.purple, .pink],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3, height: 16)
                }

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
                    Label(runtimeInfo.uptime ?? L("等待条件", "Waiting"), systemImage: "hourglass")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                } else if supervisor.isCircuitBroken[service.id] == true {
                    Label(L("已暂停保活", "Keep-alive paused"), systemImage: "exclamationmark.octagon.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.red)
                } else if currentStatus == .stopped {
                    Text(L("未运行", "Stopped"))
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
                    }
                    .buttonStyle(.plain)
                    .help(L("复制公网链接", "Copy public URL"))

                    Button(action: {
                        if let u = URL(string: pubUrl) { NSWorkspace.shared.open(u) }
                    }) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 9))
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
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.purple.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.purple.opacity(0.25), lineWidth: 0.5)
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
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                    .disabled(isBusy)

                    Button(action: { showRestartConfirm = true }) {
                        Text(L("重启", "Restart"))
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
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
                    .buttonStyle(.bordered)
                    .tint(.green)
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
                    .buttonStyle(.bordered)
                    .tint(.blue)
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
                    .buttonStyle(.bordered)
                    .tint(.purple)
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
        // 苹果官方原生超薄材质容器与自适应边框
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
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

    private func toggleTunnel() {
        if tunnelManager.isTunnelActive(for: service.id) {
            tunnelManager.stopTunnel(for: service.id)
        } else {
            tunnelManager.startTunnel(for: service)
        }
    }
}
