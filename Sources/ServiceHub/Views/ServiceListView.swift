import SwiftUI

@MainActor
struct ServiceListView: View {
    let services: [Service]
    let selectedId: String?
    let onSelect: (Service) -> Void
    let onEdit: (Service) -> Void
    let onDelete: (Service) -> Void

    @ObservedObject var supervisor = Supervisor.shared
    @ObservedObject var tunnelManager = CloudflareTunnelManager.shared
    @ObservedObject var localization = Localization.shared

    @State private var serviceToStop: Service? = nil
    @State private var serviceToRestart: Service? = nil

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
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            Text(s.category.shortName)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(s.category.color)
                                .padding(.horizontal, 4.5)
                                .padding(.vertical, 1)
                                .background(s.category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 3.5))

                            Text(s.id)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(minWidth: 150, alignment: .leading)

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

                    // 启动时间 / 运行时长 / 前置条件
                    if let uptime = rt?.uptime, st == .running {
                        Label(uptime, systemImage: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 120, alignment: .leading)
                    } else if st == .waitingPrecondition {
                        Label(rt?.uptime ?? "等待条件", systemImage: "hourglass")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                            .frame(width: 120, alignment: .leading)
                    } else if s.precondition != .none {
                        Text("[\(s.precondition.shortName)]")
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

                    // 公网映射地址：显示分配的公网 URL，支持复制与浏览器跳转
                    if let pubUrl = tunnelManager.publicUrls[s.id] {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.system(size: 10))
                                .foregroundColor(.purple)
                            Text(pubUrl)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.purple)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(pubUrl)
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
                        }
                        .frame(maxWidth: 220, alignment: .leading)
                    } else if tunnelManager.isConnecting[s.id] == true {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text(tunnelManager.tunnelStates[s.id] ?? L("正在建立公网隧道...", "Establishing tunnel..."))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: 220, alignment: .leading)
                    }

                    Spacer()

                    // 操作按钮组
                    let isBusy = supervisor.isBusy[s.id] == true
                    if isBusy {
                        ProgressView().controlSize(.small)
                            .frame(width: 60)
                    } else if st == .running {
                        HStack(spacing: 6) {
                            Button(L("停止", "Stop")) {
                                serviceToStop = s
                            }
                            .liquidGlassButton(tint: .red)
                            .controlSize(.small)

                            Button(action: { serviceToRestart = s }) {
                                Text(L("重启", "Restart"))
                            }
                            .liquidGlassButton(tint: .blue)
                            .controlSize(.small)
                            .help(L("重启服务", "Restart service"))
                        }
                    } else {
                        Button(L("启动", "Start")) {
                            Task { await supervisor.startService(s) }
                        }
                        .liquidGlassButton(tint: .green)
                        .controlSize(.small)
                    }

                    if let webStr = s.webURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !webStr.isEmpty,
                       let url = URL(string: webStr) {
                        Button(action: { NSWorkspace.shared.open(url) }) {
                            Image(systemName: "safari")
                        }
                        .liquidGlassButton(tint: .blue)
                        .controlSize(.small)
                        .help(L("打开主页: \(webStr)", "Open homepage: \(webStr)"))
                    }

                    // 公网穿透操作与状态
                    let isTunneled = tunnelManager.isTunnelActive(for: s.id)
                    if isTunneled {
                        Button(action: { tunnelManager.stopTunnel(for: s.id) }) {
                            HStack(spacing: 3) {
                                Image(systemName: "globe.badge.chevron.backward")
                                Text(L("断开", "Disconnect"))
                            }
                        }
                        .liquidGlassButton(tint: .purple)
                        .controlSize(.small)
                        .help(L("已暴露至公网，点击切断", "Exposed to public; click to disconnect"))
                    } else {
                        Button(action: { tunnelManager.startTunnel(for: s) }) {
                            HStack(spacing: 3) {
                                Image(systemName: "globe")
                                Text(L("公网", "Public"))
                            }
                        }
                        .liquidGlassButton(tint: .purple)
                        .controlSize(.small)
                        .help(L("通过 Cloudflare Tunnel 一键穿透映射到公网", "Expose via Cloudflare Tunnel"))
                    }

                    Menu {
                        if let webStr = s.webURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !webStr.isEmpty,
                           let url = URL(string: webStr) {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Label(L("打开服务主页", "Open Homepage"), systemImage: "safari")
                            }
                            Divider()
                        }
                        Button(L("编辑服务配置...", "Edit Service...")) { onEdit(s) }
                        Button(L("刷新状态", "Refresh Status")) { Task { await supervisor.probeService(s) } }
                        Divider()
                        Button(L("删除服务", "Delete Service"), role: .destructive) { onDelete(s) }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 20)
                }
                .padding(.vertical, 4)
                .tag(s.id)
            }
        }
        .listStyle(.inset)
        .alert(L("确定关闭服务「\(serviceToStop?.name ?? "")」吗？", "Stop service \"\(serviceToStop?.name ?? "")\"?"), isPresented: Binding(
            get: { serviceToStop != nil },
            set: { if !$0 { serviceToStop = nil } }
        )) {
            Button(L("取消", "Cancel"), role: .cancel) { serviceToStop = nil }
            Button(L("关闭服务", "Stop Service"), role: .destructive) {
                if let s = serviceToStop {
                    Task { await supervisor.stopService(s) }
                }
                serviceToStop = nil
            }
        } message: {
            Text(L("关闭后该服务将停止运行，相关端口和本地/公网访问将被中断。", "The service process will be terminated and all active connections will be closed."))
        }
        .alert(L("确定重启服务「\(serviceToRestart?.name ?? "")」吗？", "Restart service \"\(serviceToRestart?.name ?? "")\"?"), isPresented: Binding(
            get: { serviceToRestart != nil },
            set: { if !$0 { serviceToRestart = nil } }
        )) {
            Button(L("取消", "Cancel"), role: .cancel) { serviceToRestart = nil }
            Button(L("重启服务", "Restart")) {
                if let s = serviceToRestart {
                    Task { await supervisor.restartService(s) }
                }
                serviceToRestart = nil
            }
        } message: {
            Text(L("重启期间服务将短暂中断，随后将自动重新启动。", "The service will be temporarily interrupted, then automatically restarted."))
        }
    }
}
