import SwiftUI
import UniformTypeIdentifiers

enum ViewMode: String, CaseIterable {
    case card = "card"
    case list = "list"

    var title: String {
        switch self {
        case .card: return L("卡片", "Cards")
        case .list: return L("列表", "List")
        }
    }

    var icon: String {
        switch self {
        case .card: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

enum ServiceFilter: String, CaseIterable {
    case all = "all"
    case running = "running"
    case tunneled = "tunneled"
    case stopped = "stopped"

    var title: String {
        switch self {
        case .all: return L("全部", "All")
        case .running: return L("运行中", "Running")
        case .tunneled: return L("已映射公网 🌐", "Public 🌐")
        case .stopped: return L("已停止", "Stopped")
        }
    }
}

@MainActor
struct MainWindow: View {
    @ObservedObject var store = ServiceStore.shared
    @ObservedObject var supervisor = Supervisor.shared
    @ObservedObject var tunnelManager = CloudflareTunnelManager.shared
    // 观察语言变化：切换语言时立即刷新界面文案
    @ObservedObject var localization = Localization.shared

    @State private var viewMode: ViewMode = .card
    @State private var filter: ServiceFilter = .all
    @State private var searchText: String = ""
    @State private var isLogCollapsed: Bool = false

    @State private var showAddSheet = false
    @State private var showSettings = false
    @State private var serviceToEdit: Service? = nil
    @State private var serviceToDelete: Service? = nil

    @State private var alertMessage: String? = nil
    @State private var showAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // 上半部分顶部：安全过滤与状态标签栏
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(ServiceFilter.allCases, id: \.self) { f in
                        let count = countForFilter(f)
                        let isSelected = filter == f
                        Button(action: { filter = f }) {
                            HStack(spacing: 5) {
                                Text(f.title)
                                Text("\(count)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 4.5)
                                    .padding(.vertical, 1)
                                    .background(
                                        isSelected
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.primary.opacity(0.06)
                                    )
                                    .foregroundColor(
                                        isSelected
                                            ? .accentColor
                                            : (f == .tunneled && count > 0 ? .orange : .secondary)
                                    )
                                    .cornerRadius(4)
                            }
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Group {
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.accentColor.opacity(0.12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5)
                                            )
                                    }
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(isSelected ? .primary : .secondary)
                    }
                }
                .padding(3)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)

                Spacer()

                // 安全警示：若有公网暴露服务，显示警示与一键切断所有隧道按钮
                let tunneledCount = store.services.filter { tunnelManager.isTunnelActive(for: $0.id) }.count
                if tunneledCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundColor(.orange)
                        Text(L("当前 \(tunneledCount) 个服务已暴露公网", "\(tunneledCount) service(s) exposed publicly"))
                            .font(.caption2.bold())
                            .foregroundColor(.orange)

                        Button(L("切断全部公网", "Disconnect All")) {
                            tunnelManager.stopAllTunnels()
                        }
                        .proButton(tint: .red, isProminent: true, size: .mini)
                        .help(L("安全熔断：立即切断所有 Cloudflare 公网穿透映射", "Emergency kill switch: disconnect all Cloudflare tunnels"))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .proBar()

            Divider()

            // 上半部分：服务展示区 (Card / List)
            VStack(spacing: 0) {
                if store.services.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text(L("尚未添加任何服务", "No services yet"))
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Button(L("添加第一个服务", "Add Your First Service")) {
                            showAddSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredServices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text(L("未找到匹配的服务", "No matching services"))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if viewMode == .card {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270, maximum: 340), spacing: 14)], spacing: 14) {
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
                if isLogCollapsed || activeSelectedService == nil {
                    // 折叠态 / 无服务时的标题栏（整个标题栏区域可点击展开）
                    HStack(spacing: 10) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isLogCollapsed.toggle()
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: isLogCollapsed ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.secondary)

                                if let selected = activeSelectedService {
                                    ServiceIconView(service: selected, size: 16)
                                    Text(selected.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.primary)
                                    Text(L("日志控制台", "Log Console"))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                } else {
                                    Image(systemName: "terminal")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Text(L("日志控制台", "Log Console"))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.primary)
                                }
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(L("点击展开/折叠日志控制台", "Click to expand/collapse log console"))

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .proBar()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLogCollapsed.toggle()
                        }
                    }

                    Divider()
                }

                if !isLogCollapsed {
                    if let selected = activeSelectedService {
                        // 标题与搜索行合并：标题作为头部传入 LogView，搜索框前面的整个 title 区域点击均可折叠/展开
                        LogView(
                            service: selected,
                            header: AnyView(
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isLogCollapsed.toggle()
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.secondary)

                                        ServiceIconView(service: selected, size: 16)
                                        Text(selected.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.primary)
                                        Text(L("日志控制台", "Log Console"))
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                    .padding(.horizontal, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(L("点击折叠/展开日志控制台", "Click to collapse/expand log console"))
                            )
                        )
                        .frame(height: 240)
                    } else {
                        VStack(spacing: 8) {
                            Text(L("点击上方任意服务卡片查看其实时日志", "Select a service above to view its live logs"))
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
                .frame(width: 130)
            }

            ToolbarItem(placement: .automatic) {
                Button(action: { Task { await supervisor.probeAllServices() } }) {
                    Label(L("全部检测", "Probe All"), systemImage: "arrow.triangle.2.circlepath")
                }
                .help(L("重新检测所有服务状态与运行时长", "Re-probe status and uptime of all services"))
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { showAddSheet = true }) {
                    Label(L("添加服务", "Add Service"), systemImage: "plus")
                }
                .help(L("添加新服务", "Add a new service"))

                Button(action: { showSettings = true }) {
                    Label(L("偏好设置", "Settings"), systemImage: "gearshape")
                }
                .help(L("偏好设置与关于", "Settings & About"))

                Menu {
                    Button(L("导出服务配置备份 (YAML)...", "Export Config Backup (YAML)...")) {
                        exportBackup()
                    }
                    Button(L("从备份恢复配置 (YAML)...", "Restore from Backup (YAML)...")) {
                        importBackup()
                    }
                    Divider()
                    Button(L("在访达中定位配置文件 (services.yaml)", "Reveal services.yaml in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([store.configURL])
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
                .help(L("工具与配置备份", "Tools & Config Backup"))
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: L("搜索服务名称或 ID...", "Search services..."))
        .sheet(isPresented: $showAddSheet) {
            ServiceEditorSheet { newService in
                store.addService(newService)
                Task {
                    await supervisor.probeService(newService)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $serviceToEdit) { s in
            ServiceEditorSheet(serviceToEdit: s) { updated in
                store.updateService(updated)
                Task {
                    await supervisor.probeService(updated)
                }
            }
        }
        .alert(L("确定删除服务 \(serviceToDelete?.name ?? "") 吗？", "Delete service \(serviceToDelete?.name ?? "")?"), isPresented: Binding(
            get: { serviceToDelete != nil },
            set: { if !$0 { serviceToDelete = nil } }
        )) {
            Button(L("取消", "Cancel"), role: .cancel) { serviceToDelete = nil }
            Button(L("删除", "Delete"), role: .destructive) {
                if let s = serviceToDelete {
                    store.removeService(id: s.id)
                }
                serviceToDelete = nil
            }
        } message: {
            Text(L("删除后将不再对该服务进行状态监控与管理，但不会删除原程序或数据。", "The service will no longer be monitored or managed. The original program and data are not removed."))
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text(L("提示", "Notice")), message: Text(alertMessage ?? ""), dismissButton: .default(Text(L("确定", "OK"))))
        }
        .frame(minWidth: 860, minHeight: 600)
        .background(
            WindowAccessor { window in
                WindowManager.shared.registerMainWindow(window)
            }
        )
    }

    private var filteredServices: [Service] {
        var list = store.services

        // 1. 根据状态/公网映射过滤
        switch filter {
        case .all:
            break
        case .running:
            list = list.filter { supervisor.statuses[$0.id] == .running }
        case .tunneled:
            // 筛选条件：当前实际存在公网映射隧道的服务（仅看运行状态，不含"已配置自动映射但未运行"的）
            list = list.filter { tunnelManager.isTunnelActive(for: $0.id) }
        case .stopped:
            list = list.filter { supervisor.statuses[$0.id] != .running }
        }

        // 2. 根据搜索关键字过滤
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return list
        }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func countForFilter(_ f: ServiceFilter) -> Int {
        switch f {
        case .all:
            return store.services.count
        case .running:
            return store.services.filter { supervisor.statuses[$0.id] == .running }.count
        case .tunneled:
            return store.services.filter { tunnelManager.isTunnelActive(for: $0.id) }.count
        case .stopped:
            return store.services.filter { supervisor.statuses[$0.id] != .running }.count
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
        savePanel.title = L("导出 ServiceHub 配置备份", "Export ServiceHub Config Backup")
        savePanel.nameFieldStringValue = "services_backup_\(dateString()).yaml"
        let yamlType = UTType(filenameExtension: "yaml") ?? .plainText
        savePanel.allowedContentTypes = [yamlType, .plainText]

        if savePanel.runModal() == .OK, let targetURL = savePanel.url {
            do {
                try store.exportConfig(to: targetURL)
                alertMessage = L("配置备份导出成功！\n保存至: \(targetURL.path)", "Backup exported!\nSaved to: \(targetURL.path)")
                showAlert = true
            } catch {
                alertMessage = L("导出失败: \(error.localizedDescription)", "Export failed: \(error.localizedDescription)")
                showAlert = true
            }
        }
    }

    private func importBackup() {
        let openPanel = NSOpenPanel()
        openPanel.title = L("选择 ServiceHub 备份文件 (YAML)", "Choose ServiceHub Backup File (YAML)")
        let yamlType = UTType(filenameExtension: "yaml") ?? .plainText
        openPanel.allowedContentTypes = [yamlType, .plainText]
        openPanel.allowsMultipleSelection = false

        if openPanel.runModal() == .OK, let fileURL = openPanel.url {
            do {
                try store.importConfig(from: fileURL)
                Task {
                    await supervisor.probeAllServices()
                }
                alertMessage = L("配置已成功导入！当前共有 \(store.services.count) 个服务。", "Import successful! \(store.services.count) service(s) in total.")
                showAlert = true
            } catch {
                alertMessage = L("导入失败: \(error.localizedDescription)", "Import failed: \(error.localizedDescription)")
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
