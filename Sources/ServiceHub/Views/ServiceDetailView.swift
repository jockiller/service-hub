import SwiftUI

struct ServiceDetailView: View {
    let service: Service
    @ObservedObject var supervisor = Supervisor.shared
    @ObservedObject var store = ServiceStore.shared
    @ObservedObject var localization = Localization.shared

    @State private var showEditSheet = false
    @State private var showDeleteAlert = false

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
                            Circle()
                                .fill(currentStatus.color)
                                .frame(width: 8, height: 8)
                            Text(currentStatus.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(currentStatus.color)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(currentStatus.color.opacity(0.12))
                        .cornerRadius(12)
                    }

                    HStack(spacing: 12) {
                        if service.autoStart {
                            Label(L("开机/启动自启守护", "Auto-start guard"), systemImage: "bolt.badge.automatic")
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
                        Button(action: { Task { await supervisor.stopService(service) } }) {
                            Label(L("停止", "Stop"), systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBusy)

                        Button(action: { Task { await supervisor.restartService(service) } }) {
                            Label(L("重启", "Restart"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                    } else {
                        Button(action: { Task { await supervisor.startService(service) } }) {
                            Label(L("启动", "Start"), systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy)
                    }

                    Button(action: { Task { await supervisor.refreshService(service) } }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                    .help(L("刷新状态", "Refresh status"))

                    Menu {
                        Button(L("编辑服务配置...", "Edit Service...")) {
                            showEditSheet = true
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
            }
        }
        .alert(L("确定删除服务 \(service.name) 吗？", "Delete service \(service.name)?"), isPresented: $showDeleteAlert) {
            Button(L("取消", "Cancel"), role: .cancel) {}
            Button(L("删除", "Delete"), role: .destructive) {
                store.removeService(id: service.id)
            }
        } message: {
            Text(L("删除后将不再对该服务进行状态监控与生命周期管理，但不会删除原脚本或服务本身。", "The service will no longer be monitored or managed. The original scripts or the service itself are not removed."))
        }
    }

    private var currentStatus: ServiceStatus {
        supervisor.statuses[service.id] ?? .unknown
    }

    private var isBusy: Bool {
        supervisor.isBusy[service.id] == true
    }
}
