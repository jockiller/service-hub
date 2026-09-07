import SwiftUI

struct ServiceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let serviceToEdit: Service?
    let onSave: (Service) -> Void

    @State private var id: String = ""
    @State private var name: String = ""
    @State private var icon: String = "gearshape"
    @State private var autoStart: Bool = true
    @State private var startCommand: String = ""
    @State private var stopCommand: String = ""
    @State private var statusCommand: String = ""
    @State private var logPath: String = ""
    @State private var healthCheckURL: String = ""

    @State private var selectedTemplate: Int = 0 // 0: 自定义脚本, 1: Homebrew 服务
    @State private var brewServiceName: String = ""

    @State private var isTesting = false
    @State private var testOutput: String? = nil

    private let availableIcons = [
        "gearshape", "bolt.fill", "network", "cylinder.split.1x2.fill",
        "antenna.radiowaves.left.and.right", "server.rack", "shield.fill",
        "cpu", "memorychip", "terminal.fill", "globe", "leaf.fill"
    ]

    init(serviceToEdit: Service? = nil, onSave: @escaping (Service) -> Void) {
        self.serviceToEdit = serviceToEdit
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            // 头部
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
                    // 模板选择（仅新建时显示）
                    if serviceToEdit == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("快速模板")
                                .font(.subheadline).foregroundColor(.secondary)
                            Picker("", selection: $selectedTemplate) {
                                Text("自定义脚本 / 程序").tag(0)
                                Text("Homebrew 服务").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: selectedTemplate) { val in
                                applyTemplate(val)
                            }
                        }

                        if selectedTemplate == 1 {
                            HStack {
                                TextField("Homebrew 服务名 (如 redis, mariadb, nginx)", text: $brewServiceName)
                                    .textFieldStyle(.roundedBorder)
                                Button("应用配置") {
                                    applyBrewService()
                                }
                                .disabled(brewServiceName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }

                    // 基本信息
                    VStack(alignment: .leading, spacing: 10) {
                        Text("基础信息")
                            .font(.subheadline).foregroundColor(.secondary)

                        HStack {
                            Text("服务标识 (ID):").frame(width: 110, alignment: .trailing)
                            TextField("如 gpt-load, frpc", text: $id)
                                .textFieldStyle(.roundedBorder)
                                .disabled(serviceToEdit != nil)
                        }

                        HStack {
                            Text("显示名称:").frame(width: 110, alignment: .trailing)
                            TextField("如 GPT-Load 服务", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("服务图标:").frame(width: 110, alignment: .trailing)
                            Picker("", selection: $icon) {
                                ForEach(availableIcons, id: \.self) { ic in
                                    Label(ic, systemImage: ic).tag(ic)
                                }
                            }
                            .frame(maxWidth: 200)
                        }

                        HStack {
                            Text("开机/启动自启:").frame(width: 110, alignment: .trailing)
                            Toggle("程序启动后自动拉起并守护", isOn: $autoStart)
                        }
                    }

                    Divider()

                    // 控制命令
                    VStack(alignment: .leading, spacing: 10) {
                        Text("控制与状态命令")
                            .font(.subheadline).foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("启动命令:").frame(width: 110, alignment: .trailing)
                                TextField("必填，如 /path/to/start.sh 或 brew services start xxx", text: $startCommand)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        HStack {
                            Text("停止命令:").frame(width: 110, alignment: .trailing)
                            TextField("选填，如 /path/to/stop.sh", text: $stopCommand)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("状态检测命令:").frame(width: 110, alignment: .trailing)
                            TextField("选填，返回 0 表示正常运行", text: $statusCommand)
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
                            TextField("选填，如 /var/log/xxx.log 或 /Users/.../app.log", text: $logPath)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("HTTP 探活地址:").frame(width: 110, alignment: .trailing)
                            TextField("选填，如 http://127.0.0.1:3001/health", text: $healthCheckURL)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    // 测试运行区
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
                                Text("测试输出:")
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
                Button("保存") {
                    saveAction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(id.trimmingCharacters(in: .whitespaces).isEmpty ||
                          name.trimmingCharacters(in: .whitespaces).isEmpty ||
                          startCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 540, minHeight: 580)
        .onAppear {
            if let s = serviceToEdit {
                id = s.id
                name = s.name
                icon = s.icon
                autoStart = s.autoStart
                startCommand = s.startCommand
                stopCommand = s.stopCommand ?? ""
                statusCommand = s.statusCommand ?? ""
                logPath = s.logPath ?? ""
                healthCheckURL = s.healthCheckURL ?? ""
            }
        }
    }

    private func applyTemplate(_ val: Int) {
        if val == 0 {
            // 自定义脚本
            icon = "gearshape"
        } else if val == 1 {
            icon = "cylinder.split.1x2.fill"
        }
    }

    private func applyBrewService() {
        let trimmed = brewServiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        id = trimmed
        name = "\(trimmed.capitalized) (Homebrew)"
        startCommand = "/opt/homebrew/bin/brew services start \(trimmed)"
        stopCommand = "/opt/homebrew/bin/brew services stop \(trimmed)"
        statusCommand = "/opt/homebrew/bin/brew services list | grep \(trimmed) | grep started"
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
