import SwiftUI

struct ServiceDetailView: View {
    let service: Service
    @ObservedObject var supervisor = Supervisor.shared
    @ObservedObject var store = ServiceStore.shared
    @ObservedObject var localization = Localization.shared

    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showStopConfirm = false
    @State private var showRestartConfirm = false
    @State private var showUpdateConfirm = false
    @State private var showAlreadyLatestAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // 顶部信息栏
            HStack(alignment: .center, spacing: 16) {
                ServiceIconView(service: service, size: 48)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(service.name)
                            .font(.title2.bold())
                        Text("(\(service.id))")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        // 状态 Badge
                        HStack(spacing: 5) {
                            StatusDotView(color: currentStatus.color, size: 7)
                            Text(currentStatus.displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(currentStatus.color)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(currentStatus.color.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(currentStatus.color.opacity(0.25), lineWidth: 0.5)
                        )
                        .cornerRadius(5)
                    }

                    HStack(spacing: 12) {
                        if service.launchOnAppStart {
                            Label(L("随应用启动", "Launch on app start"), systemImage: "play.circle")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        if service.autoStart {
                            Label(L("开机/启动自启守护", "Auto-start guard"), systemImage: "bolt.badge.automatic")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        if let threshold = service.healthCheckRestartThreshold, threshold > 0, service.healthCheckURL != nil {
                            Label(L("健康失败\(threshold)次重启", "Restart after \(threshold) health failures"), systemImage: "heart.badge.clock")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        if let healthURL = service.healthCheckURL {
                            Label(healthURL, systemImage: "link")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // 操作按钮组
                HStack(spacing: 8) {
                    if currentStatus == .running {
                        Button(action: { showStopConfirm = true }) {
                            Label(L("停止", "Stop"), systemImage: "stop.fill")
                        }
                        .proButton(tint: .red)
                        .disabled(isBusy)

                        Button(action: { showRestartConfirm = true }) {
                            Label(L("重启", "Restart"), systemImage: "arrow.clockwise")
                        }
                        .proButton(tint: .blue)
                        .disabled(isBusy)
                    } else {
                        Button(action: { Task { await supervisor.startService(service) } }) {
                            Label(L("启动", "Start"), systemImage: "play.fill")
                        }
                        .proButton(tint: .green)
                        .disabled(isBusy)
                    }

                    if supervisor.isUpdatingServices[service.id] == true {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            Text(L("更新中...", "Updating..."))
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(6)
                    } else if supervisor.updatesAvailable[service.id] == true {
                        Button(action: { showUpdateConfirm = true }) {
                            Label(L("更新并重启", "Update & Restart"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        .proButton(tint: .blue)
                    }

                    Button(action: { Task { await supervisor.refreshService(service) } }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .proButton(tint: .secondary)
                    .disabled(isBusy)
                    .help(L("刷新状态", "Refresh status"))

                    Menu {
                        Button(L("编辑服务配置...", "Edit Service...")) {
                            showEditSheet = true
                        }
                        Button(L("刷新状态", "Refresh Status")) {
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
                        Button(role: .destructive, action: { showDeleteAlert = true }) {
                            Label(L("删除服务", "Delete Service"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // 可用更新提示栏
            if supervisor.updatesAvailable[service.id] == true {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundColor(.blue)
                    Text(L("检测到新版本: \(supervisor.updateInfos[service.id] ?? "")", "New version detected: \(supervisor.updateInfos[service.id] ?? "")"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.blue)
                    Spacer()
                    Button(L("立即更新并重启", "Update & Restart")) {
                        showUpdateConfirm = true
                    }
                    .proButton(tint: .blue)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.08))

                Divider()
            }

            // 最近命令输出通知栏（如果有）
            if let output = supervisor.lastOutputs[service.id], !output.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text(L("最新操作返回: \(output.components(separatedBy: .newlines).first ?? "")", "Last output: \(output.components(separatedBy: .newlines).first ?? "")"))
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Spacer()
                    Button(L("清除", "Clear")) {
                        supervisor.lastOutputs[service.id] = nil
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.08))

                Divider()
            }

            // 日志主视图
            LogView(service: service)
        }
        .sheet(isPresented: $showEditSheet) {
            ServiceEditorSheet(serviceToEdit: service) { updated in
                store.updateService(updated)
                Task {
                    if updated.checkUpdateEnabled {
                        await supervisor.checkUpdate(for: updated)
                    }
                }
            }
        }
        .alert(L("确定删除服务 \(service.name) 吗？", "Delete service \(service.name)?"), isPresented: $showDeleteAlert) {
            Button(L("取消", "Cancel"), role: .cancel) {}
            Button(L("删除", "Delete"), role: .destructive) {
                supervisor.cleanupServiceState(id: service.id)
                store.removeService(id: service.id)
            }
        } message: {
            Text(L("删除后将不再对该服务进行状态监控与生命周期管理，但不会删除原脚本或服务本身。", "The service will no longer be monitored or managed. The original scripts or the service itself are not removed."))
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
            Text(L("重启期间服务将短暂中断，随后将自动重新启动。", "The service will be temporarily interrupted, then automatically restarted."))
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

    private var isBusy: Bool {
        supervisor.isBusy[service.id] == true
    }
}
