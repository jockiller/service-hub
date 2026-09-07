import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var store = ServiceStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var alertMessage: String? = nil
    @State private var showAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // 顶部关于横幅
            HStack(spacing: 16) {
                if let iconImg = NSApp.applicationIconImage {
                    Image(nsImage: iconImg)
                        .resizable()
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: "server.rack")
                        .font(.system(size: 38))
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("ServiceHub")
                        .font(.title2.bold())
                    Text("版本 \(settings.appVersion) · macOS 本地服务管理与守护控制中心")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(18)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // 设置主体
            Form {
                // 外观与图标显示
                Section {
                    Toggle("在顶部菜单栏显示状态图标", isOn: Binding(
                        get: { settings.showMenuBarIcon },
                        set: {
                            if !settings.setShowMenuBarIcon($0) {
                                alertMessage = "不能同时隐藏 Dock 图标和状态栏图标，否则将无法唤出应用主窗口！"
                                showAlert = true
                            }
                        }
                    ))

                    Toggle("隐藏 Dock 栏图标 (纯托盘模式)", isOn: Binding(
                        get: { settings.hideDockIcon },
                        set: {
                            if !settings.setHideDockIcon($0) {
                                alertMessage = "状态栏图标未开启，无法隐藏 Dock 图标，否则将无法操作程序！"
                                showAlert = true
                            }
                        }
                    ))

                    Text("提示: 开启「隐藏 Dock 栏图标」后，应用将仅常驻在屏幕右上角菜单栏，不占用 Dock 栏位置。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } header: {
                    Text("外观与图标显示")
                }

                // 启动与轮询
                Section {
                    Toggle("开机登录时自动启动 ServiceHub", isOn: Binding(
                        get: { settings.isLaunchAtLoginEnabled },
                        set: { settings.setLaunchAtLogin($0) }
                    ))

                    HStack {
                        Text("后台状态轮询检测频率:")
                        Spacer()
                        Picker("", selection: $settings.probeInterval) {
                            Text("3 秒 (高频即时)").tag(3.0)
                            Text("6 秒 (推荐平衡)").tag(6.0)
                            Text("10 秒 (省电)").tag(10.0)
                            Text("15 秒 (低频)").tag(15.0)
                        }
                        .frame(width: 150)
                    }
                } header: {
                    Text("启动与守护")
                }

                // 配置文件存储路径与网盘同步 (OneDrive / iCloud / 自定路径)
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("当前配置文件 (YAML) 路径:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            if !settings.customConfigPath.isEmpty {
                                Text("已启用自定义云同步路径")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }

                        Text(store.configURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(5)

                        HStack(spacing: 10) {
                            Button("修改存储位置 (如 OneDrive)...") {
                                chooseCustomPath()
                            }
                            .controlSize(.small)

                            if !settings.customConfigPath.isEmpty {
                                Button("恢复默认路径") {
                                    store.resetToDefaultConfigPath()
                                    alertMessage = "已成功恢复至默认存储路径！"
                                    showAlert = true
                                }
                                .controlSize(.small)
                            }

                            Spacer()

                            Button("在访达中显示") {
                                NSWorkspace.shared.activateFileViewerSelecting([store.configURL])
                            }
                            .controlSize(.small)
                        }

                        Text("说明: 支持将 services.yaml 指向 OneDrive、iCloud 或坚果云目录，实现多设备配置自动云同步与备份。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("服务配置存储与云备份")
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)

            Divider()

            // 底部按钮
            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 540, height: 530)
        .alert(isPresented: $showAlert) {
            Alert(title: Text("设置提示"), message: Text(alertMessage ?? ""), dismissButton: .default(Text("好的")))
        }
    }

    private func chooseCustomPath() {
        let savePanel = NSSavePanel()
        savePanel.title = "选择或新建 ServiceHub 配置文件路径"
        savePanel.nameFieldStringValue = "services.yaml"
        let yamlType = UTType(filenameExtension: "yaml") ?? .plainText
        savePanel.allowedContentTypes = [yamlType, .plainText]

        if savePanel.runModal() == .OK, let targetURL = savePanel.url {
            do {
                try store.changeConfigPath(to: targetURL, migrateExisting: true)
                alertMessage = "配置存储路径修改成功！\n已将现有服务配置自动迁移至:\n\(targetURL.path)"
                showAlert = true
            } catch {
                alertMessage = "修改失败: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
}
