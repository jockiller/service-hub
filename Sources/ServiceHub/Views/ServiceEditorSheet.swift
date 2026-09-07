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
    @State private var maxRestarts: Int = 3
    @State private var restartWindowSeconds: Int = 60
    @State private var precondition: PreconditionType = .none
    @State private var preconditionParam: String = ""
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

    // Docker 扫描状态
    @State private var scannedDockerContainers: [DockerContainerItem] = []
    @State private var isScanningDocker = false
    @State private var dockerScanError: String? = nil
    @State private var selectedDockerContainer: DockerContainerItem? = nil
    @State private var manualDockerName: String = ""

    // 测试运行状态
    @State private var isTesting = false
    @State private var testOutput: String? = nil

    private let availableIcons = [
        "gearshape", "bolt.fill", "network", "cylinder.split.1x2.fill",
        "cylinder.fill", "antenna.radiowaves.left.and.right", "server.rack",
        "shield.fill", "cpu", "memorychip", "terminal.fill", "globe",
        "app.fill", "tray.2.fill", "macwindow", "shippingbox.fill", "cube.box.fill"
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
                                Text("Docker 容器").tag(3)
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

                        // 模板 3: Docker 容器纳管面板
                        if selectedTemplate == 3 {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("已扫描到本地 Docker 容器:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button(action: scanDockerContainers) {
                                        if isScanningDocker {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Label("重新扫描", systemImage: "arrow.triangle.2.circlepath")
                                                .font(.caption)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }

                                if isScanningDocker {
                                    HStack {
                                        ProgressView().controlSize(.small)
                                        Text("正在扫描本地 Docker 容器列表...")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                } else if let err = dockerScanError {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(err)
                                            .font(.caption)
                                            .foregroundColor(.orange)

                                        HStack {
                                            TextField("手动输入 Docker 容器名称 (如 my-redis)", text: $manualDockerName)
                                                .textFieldStyle(.roundedBorder)
                                            Button("应用") {
                                                applyManualDocker(manualDockerName)
                                            }
                                            .disabled(manualDockerName.trimmingCharacters(in: .whitespaces).isEmpty)
                                        }
                                    }
                                } else if scannedDockerContainers.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("当前本地暂无容器，支持手动输入容器名快速纳管:")
                                            .font(.caption).foregroundColor(.secondary)
                                        HStack {
                                            TextField("输入容器名称", text: $manualDockerName)
                                                .textFieldStyle(.roundedBorder)
                                            Button("应用") {
                                                applyManualDocker(manualDockerName)
                                            }
                                            .disabled(manualDockerName.trimmingCharacters(in: .whitespaces).isEmpty)
                                        }
                                    }
                                } else {
                                    Picker("选择容器:", selection: $selectedDockerContainer) {
                                        Text("—— 请选择要纳管的 Docker 容器 ——").tag(DockerContainerItem?.none)
                                        ForEach(scannedDockerContainers, id: \.self) { c in
                                            Text("\(c.name) [\(c.image)] (\(c.isRunning ? "运行中" : "已停止"))").tag(DockerContainerItem?.some(c))
                                        }
                                    }
                                    .onChange(of: selectedDockerContainer) { item in
                                        if let item = item {
                                            applyDockerItem(item)
                                        }
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
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

                        if autoStart {
                            HStack(spacing: 8) {
                                Text("短时间熔断:").frame(width: 110, alignment: .trailing)
                                Text("在")
                                Stepper("\(restartWindowSeconds) 秒内", value: $restartWindowSeconds, in: 10...600, step: 10)
                                    .frame(width: 120)
                                Text("连续重试超")
                                Stepper("\(maxRestarts) 次", value: $maxRestarts, in: 1...10)
                                    .frame(width: 90)
                                Text("则停止保活")
                            }
                            .font(.system(size: 12))

                            HStack {
                                Spacer().frame(width: 110)
                                Text("若短时间内频繁崩溃达到该上限，将自动暂停保活防止拖垮系统，直到手动启动成功")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(alignment: .top) {
                            Text("启动前置条件:").frame(width: 110, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 6) {
                                Picker("", selection: $precondition) {
                                    Section("通用") {
                                        Label(PreconditionType.none.displayName, systemImage: PreconditionType.none.systemIcon)
                                            .tag(PreconditionType.none)
                                    }
                                    Section("网络环境") {
                                        Label(PreconditionType.networkConnected.displayName, systemImage: PreconditionType.networkConnected.systemIcon)
                                            .tag(PreconditionType.networkConnected)
                                        Label(PreconditionType.wifiConnected.displayName, systemImage: PreconditionType.wifiConnected.systemIcon)
                                            .tag(PreconditionType.wifiConnected)
                                        Label(PreconditionType.wifiDisconnected.displayName, systemImage: PreconditionType.wifiDisconnected.systemIcon)
                                            .tag(PreconditionType.wifiDisconnected)
                                        Label(PreconditionType.networkDisconnected.displayName, systemImage: PreconditionType.networkDisconnected.systemIcon)
                                            .tag(PreconditionType.networkDisconnected)
                                        Label(PreconditionType.vpnActive.displayName, systemImage: PreconditionType.vpnActive.systemIcon)
                                            .tag(PreconditionType.vpnActive)
                                    }
                                    Section("蓝牙设置") {
                                        Label(PreconditionType.bluetoothOn.displayName, systemImage: PreconditionType.bluetoothOn.systemIcon)
                                            .tag(PreconditionType.bluetoothOn)
                                        Label(PreconditionType.bluetoothOff.displayName, systemImage: PreconditionType.bluetoothOff.systemIcon)
                                            .tag(PreconditionType.bluetoothOff)
                                        Label(PreconditionType.bluetoothConnected.displayName, systemImage: PreconditionType.bluetoothConnected.systemIcon)
                                            .tag(PreconditionType.bluetoothConnected)
                                    }
                                    Section("电源与外设") {
                                        Label(PreconditionType.acPower.displayName, systemImage: PreconditionType.acPower.systemIcon)
                                            .tag(PreconditionType.acPower)
                                        Label(PreconditionType.onBattery.displayName, systemImage: PreconditionType.onBattery.systemIcon)
                                            .tag(PreconditionType.onBattery)
                                        Label(PreconditionType.externalDisplay.displayName, systemImage: PreconditionType.externalDisplay.systemIcon)
                                            .tag(PreconditionType.externalDisplay)
                                        Label(PreconditionType.volumeMounted.displayName, systemImage: PreconditionType.volumeMounted.systemIcon)
                                            .tag(PreconditionType.volumeMounted)
                                    }
                                    Section("高级检测") {
                                        Label(PreconditionType.portAvailable.displayName, systemImage: PreconditionType.portAvailable.systemIcon)
                                            .tag(PreconditionType.portAvailable)
                                        Label(PreconditionType.hostReachable.displayName, systemImage: PreconditionType.hostReachable.systemIcon)
                                            .tag(PreconditionType.hostReachable)
                                        Label(PreconditionType.custom.displayName, systemImage: PreconditionType.custom.systemIcon)
                                            .tag(PreconditionType.custom)
                                    }
                                }
                                .frame(maxWidth: 320)

                                if let prompt = precondition.paramPrompt {
                                    VStack(alignment: .leading, spacing: 3) {
                                        TextField(prompt, text: $preconditionParam)
                                            .textFieldStyle(.roundedBorder)
                                        Text(prompt)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.top, 2)
                                } else if precondition != .none {
                                    Text("守护引擎将在条件达成（如 Wi-Fi/外网连接成功）后才自动触发启动")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
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
                maxRestarts = s.maxRestarts
                restartWindowSeconds = s.restartWindowSeconds
                precondition = s.precondition
                preconditionParam = s.preconditionParam ?? ""
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
        } else if val == 3 {
            icon = "shippingbox.fill"
            scanDockerContainers()
        } else {
            icon = "gearshape"
        }
    }

    private func scanDockerContainers() {
        isScanningDocker = true
        dockerScanError = nil
        Task {
            let res = await DockerScanner.scanContainers()
            isScanningDocker = false
            if res.success {
                scannedDockerContainers = res.containers
            } else {
                dockerScanError = res.error
            }
        }
    }

    private func applyDockerItem(_ item: DockerContainerItem) {
        let trimmed = item.name.replacingOccurrences(of: "/", with: "")
        id = trimmed
        name = "\(trimmed.capitalized) (Docker)"
        icon = "shippingbox.fill"
        let dockerPath = DockerScanner.findDockerPath()
        startCommand = "\(dockerPath) start \(trimmed)"
        stopCommand = "\(dockerPath) stop \(trimmed)"
        statusCommand = "\(dockerPath) inspect -f '{{.State.Running}}' \(trimmed) | grep -q \"true\""
    }

    private func applyManualDocker(_ rawName: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "")
        guard !trimmed.isEmpty else { return }
        id = trimmed
        name = "\(trimmed.capitalized) (Docker)"
        icon = "shippingbox.fill"
        let dockerPath = DockerScanner.findDockerPath()
        startCommand = "\(dockerPath) start \(trimmed)"
        stopCommand = "\(dockerPath) stop \(trimmed)"
        statusCommand = "\(dockerPath) inspect -f '{{.State.Running}}' \(trimmed) | grep -q \"true\""
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
            maxRestarts: maxRestarts,
            restartWindowSeconds: restartWindowSeconds,
            precondition: precondition,
            preconditionParam: preconditionParam.isEmpty ? nil : preconditionParam.trimmingCharacters(in: .whitespacesAndNewlines),
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
