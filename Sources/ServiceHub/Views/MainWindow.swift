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
    @ObservedObject var settings = AppSettings.shared
    // 观察语言变化：切换语言时立即刷新界面文案
    @ObservedObject var localization = Localization.shared

    @Environment(\.colorScheme) private var colorScheme

    @State private var viewMode: ViewMode = .card
    @State private var filter: ServiceFilter = .all
    @State private var searchText: String = ""
    @State private var isLogCollapsed: Bool = false
    @State private var isSidebarCollapsed: Bool = false

    @State private var showAddSheet = false
    @State private var showAddGroupSheet = false
    @State private var showSettings = false
    @State private var serviceToEdit: Service? = nil
    @State private var serviceToDelete: Service? = nil
    @State private var groupToEdit: ServiceGroup? = nil
    @State private var groupToDelete: ServiceGroup? = nil
    @State private var isUngroupedCollapsed: Bool = false
    @State private var targetedDropServiceId: String? = nil
    @State private var targetedDropGroupId: String? = nil

    @State private var alertMessage: String? = nil
    @State private var showAlert = false

    var body: some View {
        ZStack {
            M3AmbientBackground()

            VStack(spacing: 0) {
                // Material 3 统一顶部控制栏（不跨入系统标题栏遮挡区，100% 可见可点）
                m3HeaderToolbarView

                Divider().opacity(0.35)

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
                        if store.groups.isEmpty {
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 235, maximum: 280), spacing: 12)], spacing: 14) {
                                    ForEach(filteredServices) { s in
                                        ServiceCardView(
                                            service: s,
                                            isSelected: store.selectedServiceId == s.id,
                                            isDraggable: isReorderingAllowed,
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
                                        .overlay(
                                            targetedDropServiceId == s.id
                                                ? RoundedRectangle(cornerRadius: ProTheme.cornerRadiusCard)
                                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                                                : nil
                                        )
                                        .dropDestination(for: String.self) { items, _ in
                                            guard isReorderingAllowed, let draggedId = items.first, draggedId != s.id else { return false }
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                store.moveService(serviceId: draggedId, toGroupId: nil, targetServiceId: s.id)
                                            }
                                            return true
                                        } isTargeted: { targeted in
                                            if isReorderingAllowed {
                                                targetedDropServiceId = targeted ? s.id : nil
                                            }
                                        }
                                    }
                                }
                                .padding(16)
                            }
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 16) {
                                    ForEach(store.groups) { group in
                                        let groupServices = filteredServices.filter { $0.groupId == group.id }
                                        if !groupServices.isEmpty || (filter == .all && searchText.isEmpty) {
                                            VStack(alignment: .leading, spacing: 8) {
                                                GroupHeaderView(
                                                    group: group,
                                                    services: groupServices,
                                                    isCollapsed: group.isCollapsed,
                                                    onToggleCollapse: {
                                                        store.toggleGroupCollapse(id: group.id)
                                                    },
                                                    onEditGroup: {
                                                        groupToEdit = group
                                                    },
                                                    onDeleteGroup: {
                                                        groupToDelete = group
                                                    }
                                                )

                                                if !group.isCollapsed {
                                                    if groupServices.isEmpty {
                                                        ZStack {
                                                            RoundedRectangle(cornerRadius: 10)
                                                                .strokeBorder(
                                                                    targetedDropGroupId == group.id ? Color.accentColor : Color.secondary.opacity(0.2),
                                                                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                                                                )
                                                                .background(
                                                                    targetedDropGroupId == group.id ? Color.accentColor.opacity(0.06) : Color.clear,
                                                                    in: RoundedRectangle(cornerRadius: 10)
                                                                )
                                                                .frame(height: 64)

                                                            HStack(spacing: 6) {
                                                                Image(systemName: "plus.circle")
                                                                    .font(.system(size: 13))
                                                                Text(L("拖拽卡片至此处加入该分组", "Drag cards here to add to this group"))
                                                                    .font(.system(size: 12))
                                                            }
                                                            .foregroundColor(targetedDropGroupId == group.id ? .accentColor : .secondary)
                                                        }
                                                        .padding(.horizontal, 16)
                                                        .dropDestination(for: String.self) { items, _ in
                                                            guard isReorderingAllowed, let draggedId = items.first else { return false }
                                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                                store.moveService(serviceId: draggedId, toGroupId: group.id, targetServiceId: nil)
                                                            }
                                                            return true
                                                        } isTargeted: { targeted in
                                                            if isReorderingAllowed {
                                                                targetedDropGroupId = targeted ? group.id : nil
                                                            }
                                                        }
                                                    } else {
                                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 235, maximum: 280), spacing: 12)], spacing: 14) {
                                                            ForEach(groupServices) { s in
                                                                ServiceCardView(
                                                                    service: s,
                                                                    isSelected: store.selectedServiceId == s.id,
                                                                    isDraggable: isReorderingAllowed,
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
                                                                .overlay(
                                                                    targetedDropServiceId == s.id
                                                                        ? RoundedRectangle(cornerRadius: ProTheme.cornerRadiusCard)
                                                                            .strokeBorder(Color.accentColor, lineWidth: 2)
                                                                        : nil
                                                                )
                                                                .dropDestination(for: String.self) { items, _ in
                                                                    guard isReorderingAllowed, let draggedId = items.first, draggedId != s.id else { return false }
                                                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                                        store.moveService(
                                                                            serviceId: draggedId,
                                                                            toGroupId: group.id,
                                                                            targetServiceId: s.id
                                                                        )
                                                                    }
                                                                    return true
                                                                } isTargeted: { targeted in
                                                                    if isReorderingAllowed {
                                                                        targetedDropServiceId = targeted ? s.id : nil
                                                                    }
                                                                }
                                                            }
                                                        }
                                                        .padding(.horizontal, 16)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // 未分组服务
                                    let knownGroupIds = Set(store.groups.map(\.id))
                                    let ungroupedServices = filteredServices.filter { s in
                                        s.groupId == nil || !knownGroupIds.contains(s.groupId!)
                                    }
                                    if !ungroupedServices.isEmpty {
                                        VStack(alignment: .leading, spacing: 8) {
                                            GroupHeaderView(
                                                group: nil,
                                                services: ungroupedServices,
                                                isCollapsed: isUngroupedCollapsed,
                                                onToggleCollapse: {
                                                    isUngroupedCollapsed.toggle()
                                                }
                                            )

                                            if !isUngroupedCollapsed {
                                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 235, maximum: 280), spacing: 12)], spacing: 14) {
                                                    ForEach(ungroupedServices) { s in
                                                        ServiceCardView(
                                                            service: s,
                                                            isSelected: store.selectedServiceId == s.id,
                                                            isDraggable: isReorderingAllowed,
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
                                                        .overlay(
                                                            targetedDropServiceId == s.id
                                                                ? RoundedRectangle(cornerRadius: ProTheme.cornerRadiusCard)
                                                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                                                                : nil
                                                        )
                                                        .dropDestination(for: String.self) { items, _ in
                                                            guard isReorderingAllowed, let draggedId = items.first, draggedId != s.id else { return false }
                                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                                store.moveService(serviceId: draggedId, toGroupId: nil, targetServiceId: s.id)
                                                            }
                                                            return true
                                                        } isTargeted: { targeted in
                                                            if isReorderingAllowed {
                                                                targetedDropServiceId = targeted ? s.id : nil
                                                            }
                                                        }
                                                    }
                                                }
                                                .padding(.horizontal, 16)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 14)
                            }
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
                        .proBar()
                    }
                }
            }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $showAddSheet) {
            ServiceEditorSheet { newService in
                store.addService(newService)
                Task {
                    await supervisor.probeService(newService)
                    if newService.checkUpdateEnabled {
                        await supervisor.checkUpdate(for: newService)
                    }
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
                    if updated.checkUpdateEnabled {
                        await supervisor.checkUpdate(for: updated)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddGroupSheet) {
            GroupEditorSheet { newGroup in
                store.addGroup(newGroup)
            }
        }
        .sheet(item: $groupToEdit) { g in
            GroupEditorSheet(groupToEdit: g) { updated in
                store.updateGroup(updated)
            }
        }
        .alert(L("确定删除分组「\(groupToDelete?.name ?? "")」吗？", "Delete group \"\(groupToDelete?.name ?? "")\"?"), isPresented: Binding(
            get: { groupToDelete != nil },
            set: { if !$0 { groupToDelete = nil } }
        )) {
            Button(L("取消", "Cancel"), role: .cancel) { groupToDelete = nil }
            Button(L("删除分组", "Delete Group"), role: .destructive) {
                if let g = groupToDelete {
                    store.deleteGroup(id: g.id)
                }
                groupToDelete = nil
            }
        } message: {
            Text(L("删除分组后，该分组内的服务将自动移至「未分组」，不会删除任何服务配置或数据。", "The services in this group will be moved to Ungrouped. No service configurations or data will be deleted."))
        }
        .alert(L("确定删除服务 \(serviceToDelete?.name ?? "") 吗？", "Delete service \(serviceToDelete?.name ?? "")?"), isPresented: Binding(
            get: { serviceToDelete != nil },
            set: { if !$0 { serviceToDelete = nil } }
        )) {
            Button(L("取消", "Cancel"), role: .cancel) { serviceToDelete = nil }
            Button(L("删除", "Delete"), role: .destructive) {
                if let s = serviceToDelete {
                    supervisor.cleanupServiceState(id: s.id)
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
        .preferredColorScheme(settings.appearanceMode.colorScheme)
    }

    private var isReorderingAllowed: Bool {
        filter == .all && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Material 3 统一顶部控制栏（集成状态筛选、卡片/列表切换、快捷操作按钮与搜索框）
    @ViewBuilder
    private var m3HeaderToolbarView: some View {
        let pillBg = ProTheme.cardBaseFill(colorScheme: colorScheme, isHovered: false, isSelected: false)
        let tunneledCount = store.services.filter { tunnelManager.isTunnelActive(for: $0.id) }.count

        HStack(spacing: 10) {
            // 留出左上角 macOS 红绿灯按钮宽度，使整排按钮直接位于标题栏同一行
            Spacer().frame(width: 68)

            // 1. 状态过滤分段胶囊 (全部 / 运行中 / 已映射公网 / 已停止)
            HStack(spacing: 4) {
                ForEach(ServiceFilter.allCases, id: \.self) { f in
                    let count = countForFilter(f)
                    let isSelected = filter == f
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.16)) {
                            filter = f
                        }
                    }) {
                        HStack(spacing: 5) {
                            Text(f.title)
                            Text("\(count)")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .opacity(isSelected ? 0.92 : 0.65)
                        }
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? .white : .secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5.5)
                        .background(
                            Group {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.accentColor)
                                }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3.5)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(pillBg))

            // 公网暴露安全熔断提示（如有）
            if tunneledCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(.orange)
                    Text(L("\(tunneledCount) 个公网暴露", "\(tunneledCount) Public"))
                        .font(.caption2.bold())
                        .foregroundColor(.orange)

                    Button(L("切断全部", "Stop All")) {
                        tunnelManager.stopAllTunnels()
                    }
                    .proButton(tint: .red, isProminent: true, size: .mini)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Spacer()

            // 2. 卡片 / 列表 M3 扁平分段切换器
            HStack(spacing: 2) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    let active = viewMode == mode
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.14)) {
                            viewMode = mode
                        }
                    }) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(active ? .primary : .secondary)
                            .frame(width: 30, height: 25)
                            .background(
                                Group {
                                    if active {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(ProTheme.innerContainerFill(colorScheme: colorScheme))
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                    .help(mode.title)
                }
            }
            .padding(3.5)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(pillBg))

            // 3. 操作图标组（全部检测 / 新建分组 / 添加服务 / 外观模式 / 偏好设置 / 更多）
            HStack(spacing: 2) {
                titlebarIconButton(symbol: "arrow.triangle.2.circlepath", tooltip: L("全部检测", "Probe All")) {
                    Task { await supervisor.probeAllServices() }
                }

                titlebarIconButton(symbol: "folder.badge.plus", tooltip: L("新建分组", "New Group")) {
                    showAddGroupSheet = true
                }

                titlebarIconButton(symbol: "plus", tooltip: L("添加服务", "Add Service")) {
                    showAddSheet = true
                }

                Menu {
                    ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                        Button {
                            settings.appearanceMode = mode
                        } label: {
                            Label(
                                mode.displayName,
                                systemImage: settings.appearanceMode == mode ? "checkmark.circle.fill" : mode.icon
                            )
                        }
                    }
                } label: {
                    Image(systemName: settings.appearanceMode.icon)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 25)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28, height: 25)
                .help(L("外观模式（跟随系统 / 浅色 / 深色）", "Appearance Mode"))

                titlebarIconButton(symbol: "gearshape", tooltip: L("偏好设置", "Settings")) {
                    showSettings = true
                }

                Menu {
                    Button(L("检查所有服务更新", "Check All Service Updates")) {
                        Task {
                            let services = store.services.filter { $0.checkUpdateEnabled }
                            guard !services.isEmpty else {
                                alertMessage = L("尚未对任何服务开启更新检测。", "No services have update checks enabled.")
                                showAlert = true
                                return
                            }
                            var updatedCount = 0
                            for s in services {
                                let res = await supervisor.checkUpdate(for: s)
                                if case .updateAvailable = res {
                                    updatedCount += 1
                                }
                            }
                            if updatedCount > 0 {
                                alertMessage = L("检查完成，发现 \(updatedCount) 个服务有可用更新。", "Check complete. \(updatedCount) service(s) have updates available.")
                            } else {
                                alertMessage = L("检查完成，所有服务均已是最新版本。", "Check complete. All services are up to date.")
                            }
                            showAlert = true
                        }
                    }
                    Divider()
                    Button(L("导出服务配置备份 (YAML)...", "Export Config Backup (YAML)...")) { exportBackup() }
                    Button(L("从备份恢复配置 (YAML)...", "Restore from Backup (YAML)...")) { importBackup() }
                    Divider()
                    Button(L("在访达中定位配置文件 (services.yaml)", "Reveal services.yaml in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([store.configURL])
                    }
                    Button(L("在访达中定位应用日志 (servicehub.log)", "Reveal servicehub.log in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: AppLogger.logFilePath)])
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 25)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28, height: 25)
                .help(L("工具与配置备份", "Tools & Config Backup"))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3.5)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(pillBg))

            // 4. 搜索输入框（M3 扁平圆角框）
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                TextField(L("搜索服务名称或 ID...", "Search services..."), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .frame(width: 185)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(pillBg))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .proBar()
    }

    @ViewBuilder
    private func titlebarIconButton(symbol: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
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
