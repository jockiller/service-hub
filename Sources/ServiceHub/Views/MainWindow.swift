import SwiftUI
import UniformTypeIdentifiers

struct MainWindow: View {
    @ObservedObject var store = ServiceStore.shared
    @ObservedObject var supervisor = Supervisor.shared

    @State private var showAddSheet = false
    @State private var showingExportPicker = false
    @State private var showingImportPicker = false
    @State private var alertMessage: String? = nil
    @State private var showAlert = false

    var body: some View {
        NavigationSplitView {
            // 左侧边栏：服务列表
            VStack(spacing: 0) {
                if store.services.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("尚未添加任何服务")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Button("添加第一个服务") {
                            showAddSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $store.selectedServiceId) {
                        ForEach(store.services) { s in
                            NavigationLink(value: s.id) {
                                ServiceRow(service: s)
                            }
                            .contextMenu {
                                Button("启动") { Task { await supervisor.startService(s) } }
                                Button("停止") { Task { await supervisor.stopService(s) } }
                                Button("重启") { Task { await supervisor.restartService(s) } }
                                Divider()
                                Button("删除", role: .destructive) {
                                    store.removeService(id: s.id)
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }

                Divider()

                // 左侧底部统计与辅助信息
                HStack {
                    let runningCount = store.services.filter { supervisor.statuses[$0.id] == .running }.count
                    Circle()
                        .fill(runningCount > 0 ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text("\(runningCount)/\(store.services.count) 个服务运行中")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([store.configURL])
                    }) {
                        Image(systemName: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("在访达中定位 services.yaml")
                }
                .padding(10)
                .background(Color(NSColor.windowBackgroundColor))
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            // 右侧详情区域
            if let selectedId = store.selectedServiceId,
               let service = store.services.first(where: { $0.id == selectedId }) {
                ServiceDetailView(service: service)
            } else if let first = store.services.first {
                ServiceDetailView(service: first)
                    .onAppear {
                        store.selectedServiceId = first.id
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("请从左侧选择服务")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { Task { await supervisor.probeAllServices() } }) {
                    Label("全部检测", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("重新检测所有服务运行状态")

                Button(action: { showAddSheet = true }) {
                    Label("添加服务", systemImage: "plus")
                }
                .help("添加新服务配置")

                Menu {
                    Button("导出服务配置备份 (YAML)...") {
                        exportBackup()
                    }
                    Button("从备份恢复配置 (YAML)...") {
                        importBackup()
                    }
                    Divider()
                    Button("打开配置文件所在目录") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.configURL])
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("配置备份与工具")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ServiceEditorSheet { newService in
                store.addService(newService)
                Task {
                    await supervisor.probeService(newService)
                }
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("提示"), message: Text(alertMessage ?? ""), dismissButton: .default(Text("确定")))
        }
        .frame(minWidth: 800, minHeight: 520)
    }

    private func exportBackup() {
        let savePanel = NSSavePanel()
        savePanel.title = "导出 ServiceHub 配置备份"
        savePanel.nameFieldStringValue = "services_backup_\(dateString()).yaml"
        let yamlType = UTType(filenameExtension: "yaml") ?? .plainText
        savePanel.allowedContentTypes = [yamlType, .plainText]

        if savePanel.runModal() == .OK, let targetURL = savePanel.url {
            do {
                try store.exportConfig(to: targetURL)
                alertMessage = "配置备份导出成功！\n保存至: \(targetURL.path)"
                showAlert = true
            } catch {
                alertMessage = "导出失败: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    private func importBackup() {
        let openPanel = NSOpenPanel()
        openPanel.title = "选择 ServiceHub 备份文件 (YAML)"
        let yamlType = UTType(filenameExtension: "yaml") ?? .plainText
        openPanel.allowedContentTypes = [yamlType, .plainText]
        openPanel.allowsMultipleSelection = false

        if openPanel.runModal() == .OK, let fileURL = openPanel.url {
            do {
                try store.importConfig(from: fileURL)
                Task {
                    await supervisor.probeAllServices()
                }
                alertMessage = "配置已成功导入并刷新！共导入 \(store.services.count) 个服务。"
                showAlert = true
            } catch {
                alertMessage = "导入失败: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
