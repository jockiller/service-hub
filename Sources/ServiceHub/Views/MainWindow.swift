import SwiftUI
import UniformTypeIdentifiers

enum ViewMode: String, CaseIterable {
    case card = "card"
    case list = "list"

    var title: String {
        switch self {
        case .card: return "卡片"
        case .list: return "列表"
        }
    }

    var icon: String {
        switch self {
        case .card: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

struct MainWindow: View {
    @ObservedObject var store = ServiceStore.shared
    @ObservedObject var supervisor = Supervisor.shared

    @State private var viewMode: ViewMode = .card
    @State private var searchText: String = ""
    @State private var isLogCollapsed: Bool = false

    @State private var showAddSheet = false
    @State private var serviceToEdit: Service? = nil
    @State private var serviceToDelete: Service? = nil

    @State private var alertMessage: String? = nil
    @State private var showAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // 上半部分：服务展示区 (Card / List)
            VStack(spacing: 0) {
                if store.services.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 44))
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
                } else if filteredServices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("未找到匹配的服务")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if viewMode == .card {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 320), spacing: 14)], spacing: 14) {
                                ForEach(filteredServices) { s in
                                    ServiceCardView(
                                        service: s,
                                        isSelected: store.selectedServiceId == s.id,
                                        onSelect: {
                                            store.selectedServiceId = s.id
                                        },
                                        onEdit: {
                                            serviceToEdit = s
                                        },
                                        onDelete: {
                                            serviceToDelete = s
                                        }
                                    )
                                }
                            }
                            .padding(16)
                        }
                    } else {
                        ServiceListView(
                            services: filteredServices,
                            selectedId: store.selectedServiceId,
                            onSelect: { s in
                                store.selectedServiceId = s.id
                            },
                            onEdit: { s in
                                serviceToEdit = s
                            },
                            onDelete: { s in
                                serviceToDelete = s
                            }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // 下半部分：底部固定日志控制台
            VStack(spacing: 0) {
                // 控制台顶栏
                HStack(spacing: 10) {
                    Button(action: { isLogCollapsed.toggle() }) {
                        Image(systemName: isLogCollapsed ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isLogCollapsed ? "展开日志控制台" : "折叠日志控制台")

                    if let selected = activeSelectedService {
                        ServiceIconView(service: selected, size: 16)
                        Text(selected.name)
                            .font(.system(size: 12, weight: .medium))
                        Text("日志控制台")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "terminal")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("日志控制台")
                            .font(.system(size: 12, weight: .medium))
                    }

                    Spacer()

                    // 当前选中服务的快速启停小按钮
                    if let selected = activeSelectedService {
                        let st = supervisor.statuses[selected.id] ?? .unknown
                        let busy = supervisor.isBusy[selected.id] == true
                        if busy {
                            ProgressView().controlSize(.small)
                        } else if st == .running {
                            Button(action: { Task { await supervisor.stopService(selected) } }) {
                                Label("停止", systemImage: "stop.fill")
                                    .font(.system(size: 10))
                            }
                            .controlSize(.small)

                            Button(action: { Task { await supervisor.restartService(selected) } }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                            }
                            .controlSize(.small)
                            .help("重启")
                        } else {
                            Button(action: { Task { await supervisor.startService(selected) } }) {
                                Label("启动", systemImage: "play.fill")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))

                if !isLogCollapsed {
                    Divider()
                    if let selected = activeSelectedService {
                        LogView(service: selected)
                            .frame(height: 240)
                    } else {
                        VStack(spacing: 8) {
                            Text("点击上方任意服务卡片查看其实时日志")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(Color(NSColor.textBackgroundColor))
                    }
                }
            }
        }
        // 顶部工具栏
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Label(mode.title, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            ToolbarItem(placement: .principal) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索服务名称、ID...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .frame(minWidth: 200, maxWidth: 300)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { Task { await supervisor.probeAllServices() } }) {
                    Label("全部检测", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("重新检测所有服务状态与运行时长")

                Button(action: { showAddSheet = true }) {
                    Label("添加服务", systemImage: "plus")
                }
                .help("添加新服务")

                Menu {
                    Button("导出服务配置备份 (YAML)...") {
                        exportBackup()
                    }
                    Button("从备份恢复配置 (YAML)...") {
                        importBackup()
                    }
                    Divider()
                    Button("在访达中定位配置文件 (services.yaml)") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.configURL])
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("工具与配置备份")
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
        .sheet(item: $serviceToEdit) { s in
            ServiceEditorSheet(serviceToEdit: s) { updated in
                store.updateService(updated)
                Task {
                    await supervisor.probeService(updated)
                }
            }
        }
        .alert("确定删除服务 \(serviceToDelete?.name ?? "") 吗？", isPresented: Binding(
            get: { serviceToDelete != nil },
            set: { if !$0 { serviceToDelete = nil } }
        )) {
            Button("取消", role: .cancel) { serviceToDelete = nil }
            Button("删除", role: .destructive) {
                if let s = serviceToDelete {
                    store.removeService(id: s.id)
                }
                serviceToDelete = nil
            }
        } message: {
            Text("删除后将不再对该服务进行状态监控与管理，但不会删除原程序或数据。")
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("提示"), message: Text(alertMessage ?? ""), dismissButton: .default(Text("确定")))
        }
        .frame(minWidth: 860, minHeight: 600)
    }

    private var filteredServices: [Service] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return store.services
        }
        return store.services.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var activeSelectedService: Service? {
        if let id = store.selectedServiceId, let s = store.services.first(where: { $0.id == id }) {
            return s
        }
        return store.services.first
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
                alertMessage = "配置已成功导入！当前共有 \(store.services.count) 个服务。"
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
