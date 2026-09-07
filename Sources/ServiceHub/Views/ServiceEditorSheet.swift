import SwiftUI

struct ServiceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let serviceToEdit: Service?
    let onSave: (Service) -> Void

    @State private var id: String = ""
    @State private var name: String = ""
    @State private var icon: String = "gearshape"
    @State private var appPath: String = ""
    @State private var autoStart: Bool = true
    @State private var startCommand: String = ""
    @State private var stopCommand: String = ""
    @State private var statusCommand: String = ""
    @State private var logPath: String = ""
    @State private var healthCheckURL: String = ""

    // 0: 自定义脚本/命令, 1: Homebrew 服务, 2: 选取 macOS 应用程序
    @State private var selectedTemplate: Int = 0

    // Homebrew 扫描状态
    @State private var scannedBrewServices: [BrewServiceItem] = []
    @State private var isScanningBrew = false
    @State private var selectedBrewItem: BrewServiceItem? = nil

    // 测试运行状态
    @State private var isTesting = false
    @State private var testOutput: String? = nil

    private let availableIcons = [
        "gearshape", "bolt.fill", "network", "cylinder.split.1x2.fill",
        "cylinder.fill", "antenna.radiowaves.left.and.right", "server.rack",
        "shield.fill", "cpu", "memorychip", "terminal.fill", "globe",
        "app.fill", "tray.2.fill", "macwindow"
    ]

    init(serviceToEdit: Service? = nil, onSave: @escaping (Service) -> Void) {
        self.serviceToEdit = serviceToEdit
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题
            HStack {
                Text(serviceToEdit == nil ? "添加新服务" : "编辑服务: \(serviceToEdit!.name)")
                    .font(.headline)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 模板选择（仅新建模式下展示）
                    if serviceToEdit == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("快速接入方式")
                                .font(.subheadline).foregroundColor(.secondary)
                            Picker("", selection: $selectedTemplate) {
                                Text("自定义脚本 / 命令").tag(0)
                                Text("Homebrew 服务").tag(1)
                                Text("选取应用程序 (.app)").tag(2)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: selectedTemplate) { val in
                                handleTemplateChange(val)
                            }
                        }

                        // 模板 1: Homebrew 扫描面板
                        if selectedTemplate == 1 {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("已扫描到本地 Brew 服务:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button(action: scanBrewServices) {
                                        if isScanningBrew {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Label("重新扫描", systemImage: "arrow.triangle.2.circlepath")
                                                .font(.caption)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }

                                if isScanningBrew {
                                    HStack {
                                        ProgressView().controlSize(.small)
                                        Text("正在扫描本地已安装的 Homebrew 服务...")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                } else if scannedBrewServices.isEmpty {
                                    Text("未检测到本地已安装的 Homebrew 服务（或 brew 未安装）")
                                        .font(.caption).foregroundColor(.secondary)
                                } else {
                                    Picker("选择服务:", selection: $selectedBrewItem) {
                                        Text("—— 请选择要纳管的 Brew 服务 ——").tag(BrewServiceItem?.none)
                                        ForEach(scannedBrewServices, id: \.self) { item in
                                            Text("\(item.name) (\(item.isStarted ? "运行中" : "已停止"))").tag(BrewServiceItem?.some(item))
                                        }
                                    }
                                    .onChange(of: selectedBrewItem) { item in
                                        if let item = item {
                                            applyBrewItem(item)
                                        }
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }

                        // 模板 2: 选取应用程序面板
                        if selectedTemplate == 2 {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("选取本地已安装的 macOS 应用程序")
                                            .font(.system(size: 13, weight: .medium))
                                        Text("自动提取应用名称、可执行文件并生成启动、停止与存活检测命令")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button(action: pickAppAction) {
                                        Label("浏览应用程序...", systemImage: "macwindow")
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding(12)
                            .background(Color.accentColor.opacity(0.08))
                            .cornerRadius(8)
                        }
                    }

                    // 基础信息字段
                    VStack(alignment: .leading, spacing: 10) {
                        Text("基础信息")
                            .font(.subheadline).foregroundColor(.secondary)

                        HStack {
                            Text("服务标识 (ID):").frame(width: 110, alignment: .trailing)
                            TextField("如 gpt-load, frpc, redis", text: $id)
                                .textFieldStyle(.roundedBorder)
                                .disabled(serviceToEdit != nil)
                        }

                        HStack {
                            Text("显示名称:").frame(width: 110, alignment: .trailing)
                            TextField("如 GPT-Load 代理网关", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }

                        if !appPath.isEmpty && FileManager.default.fileExists(atPath: appPath) {
                            HStack(spacing: 10) {
                                Text("应用图标:").frame(width: 110, alignment: .trailing)
                                let img = NSWorkspace.shared.icon(forFile: appPath)
                                Image(nsImage: img)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 32, height: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("使用应用自带原生图标")
                                        .font(.system(size: 12, weight: .medium))
                                    Text(appPath)
                                        .font(.caption2).foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("清除关联") {
                                    appPath = ""
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        } else {
                            HStack {
                                Text("服务图标:").frame(width: 110, alignment: .trailing)
                                Picker("", selection: $icon) {
                                    ForEach(availableIcons, id: \.self) { ic in
                                        Label(ic, systemImage: ic).tag(ic)
                                    }
                                }
                                .frame(maxWidth: 200)
                            }
                        }

                        HStack {
                            Text("自启与守护:").frame(width: 110, alignment: .trailing)
                            Toggle("ServiceHub 启动时自动拉起，并在异常退出时自动恢复", isOn: $autoStart)
                        }
                    }

                    Divider()

                    // 控制与状态命令
                    VStack(alignment: .leading, spacing: 10) {
                        Text("控制与状态命令")
                            .font(.subheadline).foregroundColor(.secondary)

                        HStack {
                            Text("启动命令:").frame(width: 110, alignment: .trailing)
                            TextField("必填，如 /path/run.sh start 或 open -a App", text: $startCommand)
                                .textFieldStyle(.roundedBorder)
                            Button("浏览文件...") {
                                if let path = AppPickerHelper.pickFile(title: "选择启动脚本或程序") {
                                    startCommand = path
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack {
                            Text("停止命令:").frame(width: 110, alignment: .trailing)
                            TextField("选填，如 /path/run.sh stop 或 killall App", text: $stopCommand)
                                .textFieldStyle(.roundedBorder)
                            Button("浏览文件...") {
                                if let path = AppPickerHelper.pickFile(title: "选择停止脚本") {
                                    stopCommand = path
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack {
                            Text("状态检测命令:").frame(width: 110, alignment: .trailing)
                            TextField("选填，退出码为 0 则视为正在运行", text: $statusCommand)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Divider()

                    // 日志与探活
                    VStack(alignment: .leading, spacing: 10) {
                        Text("日志与探活")
                            .font(.subheadline).foregroundColor(.secondary)

                        HStack {
                            Text("日志文件路径:").frame(width: 110, alignment: .trailing)
                            TextField("选填，如 /Users/.../app.log", text: $logPath)
                                .textFieldStyle(.roundedBorder)
                            Button("浏览日志...") {
                                if let path = AppPickerHelper.pickFile(title: "选择日志文件") {
                                    logPath = path
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack {
                            Text("HTTP 探活地址:").frame(width: 110, alignment: .trailing)
                            TextField("选填，如 http://127.0.0.1:3001/health", text: $healthCheckURL)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    // 启动命令测试运行区
                    if !startCommand.trimmingCharacters(in: .whitespaces).isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Button(action: testRunCommand) {
                                    if isTesting {
                                        ProgressView().controlSize(.small)
                                        Text("执行中...")
                                    } else {
                                        Image(systemName: "play.circle")
                                        Text("测试运行启动命令")
                                    }
                                }
                                .disabled(isTesting)

                                Spacer()
                            }

                            if let output = testOutput {
                                Text("测试返回:")
                                    .font(.caption).foregroundColor(.secondary)
                                ScrollView {
                                    Text(output)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                }
                                .frame(height: 100)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()

            // 底部保存按钮
            HStack {
                Spacer()
                Button("保存配置") {
                    saveAction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(id.trimmingCharacters(in: .whitespaces).isEmpty ||
                          name.trimmingCharacters(in: .whitespaces).isEmpty ||
                          startCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 580, minHeight: 620)
        .onAppear {
            if let s = serviceToEdit {
                id = s.id
                name = s.name
                icon = s.icon
                appPath = s.appPath ?? ""
                autoStart = s.autoStart
                startCommand = s.startCommand
                stopCommand = s.stopCommand ?? ""
                statusCommand = s.statusCommand ?? ""
                logPath = s.logPath ?? ""
                healthCheckURL = s.healthCheckURL ?? ""
            }
        }
    }

    private func handleTemplateChange(_ val: Int) {
        if val == 1 {
            icon = "server.rack"
            scanBrewServices()
        } else if val == 2 {
            icon = "app.fill"
            pickAppAction()
        } else {
            icon = "gearshape"
        }
    }

    private func scanBrewServices() {
        isScanningBrew = true
        Task {
            let list = await BrewScanner.scanInstalledServices()
            isScanningBrew = false
            scannedBrewServices = list
        }
    }

    private func applyBrewItem(_ item: BrewServiceItem) {
        let trimmed = item.name
        id = trimmed
        name = "\(trimmed.capitalized) (Homebrew)"
        icon = item.recommendedIcon
        startCommand = "/opt/homebrew/bin/brew services start \(trimmed)"
        stopCommand = "/opt/homebrew/bin/brew services stop \(trimmed)"
        statusCommand = "/opt/homebrew/bin/brew services list | grep \"\(trimmed)\" | grep started"
    }

    private func pickAppAction() {
        guard let meta = AppPickerHelper.pickApplication() else { return }
        id = meta.executableName.lowercased().replacingOccurrences(of: " ", with: "-")
        name = meta.appName
        icon = "app.fill"
        appPath = meta.appPath
        startCommand = meta.recommendedStartCmd
        stopCommand = meta.recommendedStopCmd
        statusCommand = meta.recommendedStatusCmd
    }

    private func testRunCommand() {
        isTesting = true
        testOutput = nil
        Task {
            let res = await ProcessRunner.run(command: startCommand, timeout: 10)
            isTesting = false
            testOutput = "退出码: \(res.exitCode)\n\(res.output)"
        }
    }

    private func saveAction() {
        let service = Service(
            id: id.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon,
            appPath: appPath.isEmpty ? nil : appPath.trimmingCharacters(in: .whitespacesAndNewlines),
            autoStart: autoStart,
            startCommand: startCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            stopCommand: stopCommand.isEmpty ? nil : stopCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            statusCommand: statusCommand.isEmpty ? nil : statusCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            logPath: logPath.isEmpty ? nil : logPath.trimmingCharacters(in: .whitespacesAndNewlines),
            healthCheckURL: healthCheckURL.isEmpty ? nil : healthCheckURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onSave(service)
        dismiss()
    }
}
