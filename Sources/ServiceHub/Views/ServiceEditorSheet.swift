import SwiftUI

@MainActor
struct ServiceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let serviceToEdit: Service?
    let onSave: (Service) -> Void
    // 观察语言变化
    @ObservedObject var localization = Localization.shared

    @State private var id: String = ""
    @State private var name: String = ""
    @State private var icon: String = "gearshape"
    @State private var appPath: String = ""
    @State private var autoStart: Bool = true
    @State private var launchOnAppStart: Bool = true
    @State private var maxRestarts: Int = 3
    @State private var restartWindowSeconds: Int = 60
    @State private var precondition: PreconditionType = .none
    @State private var preconditionParam: String = ""
    @State private var startCommand: String = ""
    @State private var stopCommand: String = ""
    @State private var statusCommand: String = ""
    @State private var logPath: String = ""
    @State private var healthCheckURL: String = ""
    @State private var healthCheckRestartEnabled: Bool = false
    @State private var healthCheckRestartThreshold: Int = 3
    @State private var webURL: String = ""
    @State private var openWebURLOnStart: Bool = false
    @State private var tunnelEnabled: Bool = false
    @State private var tunnelMode: TunnelMode = .quick
    @State private var tunnelCustomDomain: String = ""
    @State private var tunnelToken: String = ""
    @State private var tunnelTarget: String = ""

    // 0: 自定义, 1: Brew, 2: App, 3: Docker
    @State private var selectedTemplate: Int = 0

    // 扫描状态
    @State private var scannedBrewServices: [BrewServiceItem] = []
    @State private var isScanningBrew = false
    @State private var selectedBrewItem: BrewServiceItem? = nil

    @State private var scannedDockerContainers: [DockerContainerItem] = []
    @State private var isScanningDocker = false
    @State private var dockerScanError: String? = nil
    @State private var selectedDockerContainer: DockerContainerItem? = nil

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
            // 顶栏
            HStack {
                Text(serviceToEdit == nil ? L("添加服务", "Add Service") : L("编辑服务", "Edit Service"))
                    .font(.headline)
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }
                    .proButton()
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 模板切换（新建时）
                    if serviceToEdit == nil {
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("", selection: $selectedTemplate) {
                                Text(L("自定义", "Custom")).tag(0)
                                Text("Homebrew").tag(1)
                                Text(L("应用程序", "Application")).tag(2)
                                Text("Docker").tag(3)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: selectedTemplate) { val in
                                handleTemplateChange(val)
                            }
                        }

                        // Brew 快速选择
                        if selectedTemplate == 1 {
                            HStack {
                                if isScanningBrew {
                                    ProgressView().controlSize(.small)
                                    Text(L("正在扫描 Homebrew 服务...", "Scanning Homebrew services...")).font(.caption).foregroundColor(.secondary)
                                } else if scannedBrewServices.isEmpty {
                                    Text(L("未检测到 Homebrew 服务", "No Homebrew services found")).font(.caption).foregroundColor(.secondary)
                                } else {
                                    Picker(L("服务:", "Service:"), selection: $selectedBrewItem) {
                                        Text(L("选择已安装的 Brew 服务", "Select a Brew service")).tag(BrewServiceItem?.none)
                                        ForEach(scannedBrewServices, id: \.self) { item in
                                            Text("\(item.name) (\(item.isStarted ? L("运行中", "running") : L("已停止", "stopped")))").tag(BrewServiceItem?.some(item))
                                        }
                                    }
                                    .onChange(of: selectedBrewItem) { item in
                                        if let item = item { applyBrewItem(item) }
                                    }
                                }
                                Spacer()
                                Button(action: scanBrewServices) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .proCard(statusColor: .secondary, cornerRadius: 8)
                        }

                        // App 快速选择
                        if selectedTemplate == 2 {
                            HStack {
                                Text(L("从本地选取应用程序 (.app)", "Choose an application (.app) from disk"))
                                    .font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Button(L("选取应用...", "Choose App...")) {
                                    pickAppAction()
                                }
                                .proButton(isProminent: true)
                                .controlSize(.small)
                            }
                            .padding(8)
                            .proCard(statusColor: .secondary, cornerRadius: 8)
                        }

                        // Docker 快速选择 —— 仅允许选择本机已存在的容器，不支持手填名称
                        if selectedTemplate == 3 {
                            HStack {
                                if isScanningDocker {
                                    ProgressView().controlSize(.small)
                                    Text(L("正在扫描 Docker 容器...", "Scanning Docker containers...")).font(.caption).foregroundColor(.secondary)
                                } else if let err = dockerScanError {
                                    Label(err, systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                        .lineLimit(2)
                                } else if scannedDockerContainers.isEmpty {
                                    Label(L("未发现任何 Docker 容器", "No Docker containers found"), systemImage: "shippingbox")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Picker(L("容器:", "Container:"), selection: $selectedDockerContainer) {
                                        Text(L("选择本地 Docker 容器", "Select a Docker container")).tag(DockerContainerItem?.none)
                                        ForEach(scannedDockerContainers, id: \.self) { c in
                                            Text("\(c.name) (\(c.isRunning ? L("运行中", "running") : L("已停止", "stopped")))").tag(DockerContainerItem?.some(c))
                                        }
                                    }
                                    .onChange(of: selectedDockerContainer) { item in
                                        if let item = item { applyDockerItem(item) }
                                    }
                                }
                                Spacer()
                                Button(action: scanDockerContainers) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                .buttonStyle(.plain)
                                .help(L("重新扫描本机容器", "Rescan containers"))
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }

                    // 基础信息
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("基础信息", "Basics"))
                            .font(.caption.bold()).foregroundColor(.secondary)

                        HStack {
                            Text(L("服务 ID:", "Service ID:")).frame(width: 90, alignment: .trailing)
                            TextField(L("如 gpt-load, redis", "e.g. gpt-load, redis"), text: $id)
                                .textFieldStyle(.roundedBorder)
                                .disabled(serviceToEdit != nil)
                        }

                        HStack {
                            Text(L("显示名称:", "Display Name:")).frame(width: 90, alignment: .trailing)
                            TextField(L("服务名称", "Service name"), text: $name)
                                .textFieldStyle(.roundedBorder)
                        }

                        if !appPath.isEmpty && FileManager.default.fileExists(atPath: appPath) {
                            HStack(spacing: 8) {
                                Text(L("图标:", "Icon:")).frame(width: 90, alignment: .trailing)
                                Image(nsImage: NSWorkspace.shared.icon(forFile: appPath))
                                    .resizable().frame(width: 24, height: 24)
                                Text(L("使用 App 原生图标", "Using native app icon")).font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Button(L("清除", "Clear")) { appPath = "" }
                                    .buttonStyle(.plain).font(.caption).foregroundColor(.secondary)
                            }
                        } else {
                            HStack {
                                Text(L("图标:", "Icon:")).frame(width: 90, alignment: .trailing)
                                Picker("", selection: $icon) {
                                    ForEach(availableIcons, id: \.self) { ic in
                                        Label(ic, systemImage: ic).tag(ic)
                                    }
                                }
                                .frame(maxWidth: 180)
                            }
                        }

                        HStack {
                            Text(L("自动保活:", "Keep-alive:")).frame(width: 90, alignment: .trailing)
                            Toggle(L("异常退出后自动重启", "Auto-restart on crash"), isOn: $autoStart)
                        }

                        HStack {
                            Text(L("随应用启动:", "Launch on app start:")).frame(width: 90, alignment: .trailing)
                            Toggle(L("ServiceHub 启动时自动拉起该服务", "Start this service when ServiceHub launches"), isOn: $launchOnAppStart)
                        }

                        if autoStart {
                            HStack(spacing: 6) {
                                Text(L("熔断保护:", "Circuit breaker:")).frame(width: 90, alignment: .trailing)
                                Stepper(L("\(restartWindowSeconds)s 内", "within \(restartWindowSeconds)s"), value: $restartWindowSeconds, in: 10...600, step: 10)
                                    .frame(width: 100)
                                Stepper(L("超 \(maxRestarts) 次则停", "stop after \(maxRestarts) tries"), value: $maxRestarts, in: 1...10)
                                    .frame(width: 110)
                            }
                            .font(.system(size: 12))
                        }

                        HStack(alignment: .top) {
                            Text(L("前置条件:", "Precondition:")).frame(width: 90, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 4) {
                                Picker("", selection: $precondition) {
                                    Section(L("通用", "General")) {
                                        Label(PreconditionType.none.displayName, systemImage: PreconditionType.none.systemIcon).tag(PreconditionType.none)
                                    }
                                    Section(L("网络", "Network")) {
                                        Label(PreconditionType.networkConnected.displayName, systemImage: PreconditionType.networkConnected.systemIcon).tag(PreconditionType.networkConnected)
                                        Label(PreconditionType.wifiConnected.displayName, systemImage: PreconditionType.wifiConnected.systemIcon).tag(PreconditionType.wifiConnected)
                                        Label(PreconditionType.wifiDisconnected.displayName, systemImage: PreconditionType.wifiDisconnected.systemIcon).tag(PreconditionType.wifiDisconnected)
                                        Label(PreconditionType.networkDisconnected.displayName, systemImage: PreconditionType.networkDisconnected.systemIcon).tag(PreconditionType.networkDisconnected)
                                        Label(PreconditionType.vpnActive.displayName, systemImage: PreconditionType.vpnActive.systemIcon).tag(PreconditionType.vpnActive)
                                    }
                                    Section(L("硬件与电源", "Hardware & Power")) {
                                        Label(PreconditionType.acPower.displayName, systemImage: PreconditionType.acPower.systemIcon).tag(PreconditionType.acPower)
                                        Label(PreconditionType.onBattery.displayName, systemImage: PreconditionType.onBattery.systemIcon).tag(PreconditionType.onBattery)
                                        Label(PreconditionType.externalDisplay.displayName, systemImage: PreconditionType.externalDisplay.systemIcon).tag(PreconditionType.externalDisplay)
                                        Label(PreconditionType.volumeMounted.displayName, systemImage: PreconditionType.volumeMounted.systemIcon).tag(PreconditionType.volumeMounted)
                                        Label(PreconditionType.bluetoothOn.displayName, systemImage: PreconditionType.bluetoothOn.systemIcon).tag(PreconditionType.bluetoothOn)
                                        Label(PreconditionType.bluetoothConnected.displayName, systemImage: PreconditionType.bluetoothConnected.systemIcon).tag(PreconditionType.bluetoothConnected)
                                    }
                                    Section(L("高级", "Advanced")) {
                                        Label(PreconditionType.portAvailable.displayName, systemImage: PreconditionType.portAvailable.systemIcon).tag(PreconditionType.portAvailable)
                                        Label(PreconditionType.hostReachable.displayName, systemImage: PreconditionType.hostReachable.systemIcon).tag(PreconditionType.hostReachable)
                                        Label(PreconditionType.custom.displayName, systemImage: PreconditionType.custom.systemIcon).tag(PreconditionType.custom)
                                    }
                                }
                                .frame(maxWidth: 280)

                                if let prompt = precondition.paramPrompt {
                                    TextField(prompt, text: $preconditionParam)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    }

                    Divider()

                    // 控制命令
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("控制命令", "Commands"))
                            .font(.caption.bold()).foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Text(L("启动命令:", "Start command:")).frame(width: 90, alignment: .trailing)
                            TextField(L("如 /path/to/start.sh 或 open -a App", "e.g. /path/to/start.sh or open -a App"), text: $startCommand)
                                .textFieldStyle(.roundedBorder)
                            Button(action: {
                                if let path = AppPickerHelper.pickFile(title: L("选择启动文件", "Choose Start File")) {
                                    startCommand = path
                                }
                            }) {
                                Text(L("浏览...", "Browse..."))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .proButton()
                            .controlSize(.small)
                            .fixedSize()
                            .layoutPriority(1)
                        }

                        HStack(spacing: 8) {
                            Text(L("停止命令:", "Stop command:")).frame(width: 90, alignment: .trailing)
                            TextField(L("选填，如 /path/to/stop.sh", "Optional, e.g. /path/to/stop.sh"), text: $stopCommand)
                                .textFieldStyle(.roundedBorder)
                            Button(action: {
                                if let path = AppPickerHelper.pickFile(title: L("选择停止脚本", "Choose Stop Script")) {
                                    stopCommand = path
                                }
                            }) {
                                Text(L("浏览...", "Browse..."))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .proButton()
                            .controlSize(.small)
                            .fixedSize()
                            .layoutPriority(1)
                        }

                        HStack(spacing: 8) {
                            Text(L("状态命令:", "Status command:")).frame(width: 90, alignment: .trailing)
                            TextField(L("选填，退出码 0 视为运行中", "Optional; exit code 0 means running"), text: $statusCommand)
                                .textFieldStyle(.roundedBorder)
                            Button(action: {
                                if let path = AppPickerHelper.pickFile(title: L("选择状态检测脚本", "Choose Status Script")) {
                                    statusCommand = path
                                }
                            }) {
                                Text(L("浏览...", "Browse..."))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .proButton()
                            .controlSize(.small)
                            .fixedSize()
                            .layoutPriority(1)
                        }
                    }

                    Divider()

                    // 主页与日志
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("主页与探活", "Homepage & Health"))
                            .font(.caption.bold()).foregroundColor(.secondary)

                        HStack {
                            Text(L("服务主页:", "Homepage:")).frame(width: 90, alignment: .trailing)
                            TextField(L("选填，如 http://localhost:3001", "Optional, e.g. http://localhost:3001"), text: $webURL)
                                .textFieldStyle(.roundedBorder)

                            if !webURL.trimmingCharacters(in: .whitespaces).isEmpty,
                               let url = URL(string: webURL) {
                                Button(L("打开", "Open")) { NSWorkspace.shared.open(url) }
                                    .proButton()
                                    .controlSize(.small)
                            }
                        }

                        HStack {
                            Spacer().frame(width: 90)
                            Toggle(L("启动成功后自动在浏览器打开", "Open in browser after start"), isOn: $openWebURLOnStart)
                                .font(.system(size: 11))
                        }

                        HStack {
                            Text(L("HTTP 探活:", "HTTP health check:")).frame(width: 90, alignment: .trailing)
                            TextField(L("选填，如 http://127.0.0.1:3001/health", "Optional, e.g. http://127.0.0.1:3001/health"), text: $healthCheckURL)
                                .textFieldStyle(.roundedBorder)
                        }

                        if !healthCheckURL.trimmingCharacters(in: .whitespaces).isEmpty {
                            HStack {
                                Text(L("失败重启:", "Restart on failure:")).frame(width: 90, alignment: .trailing)
                                Toggle(L("健康检查连续失败 N 次后强制重启 (即使进程仍在运行)", "Force restart after N consecutive health check failures (even if process is alive)"), isOn: $healthCheckRestartEnabled)
                                    .font(.system(size: 11))
                            }
                            if healthCheckRestartEnabled {
                                HStack(spacing: 6) {
                                    Text(L("失败阈值:", "Failure threshold:")).frame(width: 90, alignment: .trailing)
                                    Stepper(L("\(healthCheckRestartThreshold) 次", "\(healthCheckRestartThreshold) time(s)"), value: $healthCheckRestartThreshold, in: 2...30)
                                        .frame(width: 100)
                                    Text(L("每 6s 探测一次，连续失败达到该次数即重启", "Probed every 6s; restarts when consecutive failures reach this count"))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .font(.system(size: 12))
                            }
                        }

                        HStack(spacing: 8) {
                            Text(L("日志路径:", "Log path:")).frame(width: 90, alignment: .trailing)
                            TextField(L("选填，日志文件绝对路径", "Optional, absolute path to log file"), text: $logPath)
                                .textFieldStyle(.roundedBorder)
                            Button(action: {
                                if let path = AppPickerHelper.pickFile(title: L("选择日志文件", "Choose Log File")) {
                                    logPath = path
                                }
                            }) {
                                Text(L("浏览...", "Browse..."))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .proButton()
                            .controlSize(.small)
                            .fixedSize()
                            .layoutPriority(1)
                        }
                    }

                    Divider()

                    // Cloudflare Tunnel —— 依赖服务主页作为穿透目标，须先配置主页
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("公网映射 (Cloudflare Tunnel)", "Public URL (Cloudflare Tunnel)"))
                            .font(.caption.bold()).foregroundColor(.secondary)

                        if webURL.trimmingCharacters(in: .whitespaces).isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                Text(L("请先在上方填写「服务主页」，公网穿透将把该地址暴露到公网", "Fill in the Homepage above first — the tunnel exposes that address to the public internet"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            HStack {
                                Text(L("公网穿透:", "Tunnel:")).frame(width: 90, alignment: .trailing)
                                Toggle(L("随服务启动自动开启", "Start automatically with the service"), isOn: $tunnelEnabled)
                            }

                            if tunnelEnabled {
                            HStack {
                                Text(L("模式:", "Mode:")).frame(width: 90, alignment: .trailing)
                                Picker("", selection: $tunnelMode) {
                                    ForEach(TunnelMode.allCases, id: \.self) { m in
                                        Text(m.displayName).tag(m)
                                    }
                                }
                                .frame(maxWidth: 280)
                            }

                            if tunnelMode == .token {
                                HStack {
                                    Text(L("自定义域名:", "Custom domain:")).frame(width: 90, alignment: .trailing)
                                    TextField(L("如 gpt.mydomain.com", "e.g. gpt.mydomain.com"), text: $tunnelCustomDomain)
                                        .textFieldStyle(.roundedBorder)
                                }

                                HStack {
                                    Text("Token:").frame(width: 90, alignment: .trailing)
                                    SecureField("Cloudflare Tunnel Token", text: $tunnelToken)
                                        .textFieldStyle(.roundedBorder)
                                    Button(L("获取 Token ↗", "Get Token ↗")) {
                                        if let u = URL(string: "https://one.dash.cloudflare.com/") {
                                            NSWorkspace.shared.open(u)
                                        }
                                    }
                                    .proButton()
                                    .controlSize(.small)
                                }
                            }

                                HStack {
                                    Text(L("本地目标:", "Local target:")).frame(width: 90, alignment: .trailing)
                                    TextField(L("选填，默认使用服务主页或 127.0.0.1:3001", "Optional; defaults to homepage or 127.0.0.1:3001"), text: $tunnelTarget)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    }

                    // 启动命令测试
                    if !startCommand.trimmingCharacters(in: .whitespaces).isEmpty {
                        Divider()
                        HStack {
                            Button(action: testRunCommand) {
                                if isTesting {
                                    ProgressView().controlSize(.small)
                                    Text(L("执行中...", "Running..."))
                                } else {
                                    Label(L("测试运行启动命令", "Test Start Command"), systemImage: "play.circle")
                                }
                            }
                            .proButton()
                            .controlSize(.small)
                            .disabled(isTesting)
                            Spacer()
                        }

                        if let output = testOutput {
                            ScrollView {
                                Text(output)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                            }
                            .frame(height: 80)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(5)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // 底部保存按钮
            HStack {
                Spacer()
                Button(L("保存", "Save")) {
                    saveAction()
                }
                .proButton(isProminent: true)
                .disabled(id.trimmingCharacters(in: .whitespaces).isEmpty ||
                          name.trimmingCharacters(in: .whitespaces).isEmpty ||
                          startCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 560, height: 600)
        .onAppear {
            if let s = serviceToEdit {
                id = s.id
                name = s.name
                icon = s.icon
                appPath = s.appPath ?? ""
                autoStart = s.autoStart
                launchOnAppStart = s.launchOnAppStart
                maxRestarts = s.maxRestarts
                restartWindowSeconds = s.restartWindowSeconds
                precondition = s.precondition
                preconditionParam = s.preconditionParam ?? ""
                startCommand = s.startCommand
                stopCommand = s.stopCommand ?? ""
                statusCommand = s.statusCommand ?? ""
                logPath = s.logPath ?? ""
                healthCheckURL = s.healthCheckURL ?? ""
                if let t = s.healthCheckRestartThreshold, t > 0 {
                    healthCheckRestartEnabled = true
                    healthCheckRestartThreshold = t
                } else {
                    // 关闭状态保留已保存的阈值原值（仅首次编辑时用默认 3），避免静默改写用户配置
                    healthCheckRestartEnabled = false
                }
                webURL = s.webURL ?? ""
                openWebURLOnStart = s.openWebURLOnStart
                if let tc = s.tunnelConfig {
                    tunnelEnabled = tc.enabled
                    tunnelMode = tc.mode
                    tunnelCustomDomain = tc.customDomain ?? ""
                    tunnelToken = tc.token ?? ""
                    tunnelTarget = tc.targetURL ?? ""
                }
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
        name = trimmed.capitalized
        icon = item.recommendedIcon
        startCommand = "/opt/homebrew/bin/brew services start \(trimmed)"
        stopCommand = "/opt/homebrew/bin/brew services stop \(trimmed)"
        statusCommand = "/opt/homebrew/bin/brew services list | grep \"\(trimmed)\" | grep started"
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
        name = trimmed.capitalized
        icon = "shippingbox.fill"
        let dockerPath = DockerScanner.findDockerPath()
        startCommand = "\(dockerPath) start \(trimmed)"
        stopCommand = "\(dockerPath) stop \(trimmed)"
        statusCommand = "\(dockerPath) inspect -f '{{.State.Running}}' \(trimmed) | grep -q \"true\""
    }

    @MainActor
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
            testOutput = L("退出码: \(res.exitCode)\n\(res.output)", "Exit code: \(res.exitCode)\n\(res.output)")
        }
    }

    private func saveAction() {
        var tc: TunnelConfig? = nil
        // 公网穿透依赖服务主页作为穿透目标：未配置主页时忽略隧道配置
        if tunnelEnabled && !webURL.trimmingCharacters(in: .whitespaces).isEmpty {
            tc = TunnelConfig(
                enabled: true,
                mode: tunnelMode,
                token: tunnelToken.isEmpty ? nil : tunnelToken.trimmingCharacters(in: .whitespacesAndNewlines),
                customDomain: tunnelCustomDomain.isEmpty ? nil : tunnelCustomDomain.trimmingCharacters(in: .whitespacesAndNewlines),
                targetURL: tunnelTarget.isEmpty ? nil : tunnelTarget.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let resolvedCategory: ServiceCategory
        if let existing = serviceToEdit?.serviceType {
            resolvedCategory = existing
        } else {
            switch selectedTemplate {
            case 1: resolvedCategory = .homebrew
            case 2: resolvedCategory = .application
            case 3: resolvedCategory = .docker
            default: resolvedCategory = .script
            }
        }

        let service = Service(
            id: id.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon,
            appPath: appPath.isEmpty ? nil : appPath.trimmingCharacters(in: .whitespacesAndNewlines),
            autoStart: autoStart,
            launchOnAppStart: launchOnAppStart,
            maxRestarts: maxRestarts,
            restartWindowSeconds: restartWindowSeconds,
            precondition: precondition,
            preconditionParam: preconditionParam.isEmpty ? nil : preconditionParam.trimmingCharacters(in: .whitespacesAndNewlines),
            startCommand: startCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            stopCommand: stopCommand.isEmpty ? nil : stopCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            statusCommand: statusCommand.isEmpty ? nil : statusCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            logPath: logPath.isEmpty ? nil : logPath.trimmingCharacters(in: .whitespacesAndNewlines),
            healthCheckURL: healthCheckURL.isEmpty ? nil : healthCheckURL.trimmingCharacters(in: .whitespacesAndNewlines),
            healthCheckRestartThreshold: (healthCheckRestartEnabled && !healthCheckURL.trimmingCharacters(in: .whitespaces).isEmpty) ? healthCheckRestartThreshold : nil,
            webURL: webURL.isEmpty ? nil : webURL.trimmingCharacters(in: .whitespacesAndNewlines),
            openWebURLOnStart: openWebURLOnStart,
            tunnelConfig: tc,
            serviceType: resolvedCategory
        )
        onSave(service)
        dismiss()
    }
}
