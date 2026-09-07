import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var store = ServiceStore.shared
    // 观察语言变化：切换语言时立即刷新整个设置面板（含 Picker 显示与各处文案）
    @ObservedObject var localization = Localization.shared
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
                        .frame(width: 40, height: 40)
                } else {
                    Image(systemName: "server.rack")
                        .font(.system(size: 36))
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("ServiceHub")
                        .font(.title3.bold())
                    Text(L("版本 \(settings.appVersion)", "Version \(settings.appVersion)"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // 设置主体
            Form {
                // 界面语言
                Section {
                    HStack {
                        Text(L("界面语言:", "Language:"))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { Localization.shared.preference },
                            set: { Localization.shared.preference = $0 }
                        )) {
                            ForEach(AppLanguage.allCases, id: \.self) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .frame(width: 160)
                        .pickerStyle(.menu)
                    }
                } header: {
                    Text(L("通用", "General"))
                }

                // 外观与图标显示
                Section {
                    Toggle(L("在顶部菜单栏显示图标", "Show menu bar icon"), isOn: Binding(
                        get: { settings.showMenuBarIcon },
                        set: {
                            if !settings.setShowMenuBarIcon($0) {
                                alertMessage = L("不能同时隐藏 Dock 和菜单栏图标", "Dock icon and menu bar icon cannot be hidden at the same time")
                                showAlert = true
                            }
                        }
                    ))

                    Toggle(L("隐藏 Dock 栏图标", "Hide Dock icon"), isOn: Binding(
                        get: { settings.hideDockIcon },
                        set: {
                            if !settings.setHideDockIcon($0) {
                                alertMessage = L("菜单栏图标未开启，无法隐藏 Dock 图标", "Enable the menu bar icon before hiding the Dock icon")
                                showAlert = true
                            }
                        }
                    ))
                } header: {
                    Text(L("显示", "Display"))
                }

                // 启动与轮询
                Section {
                    Toggle(L("开机登录时自动启动", "Launch at login"), isOn: Binding(
                        get: { settings.isLaunchAtLoginEnabled },
                        set: { settings.setLaunchAtLogin($0) }
                    ))

                    HStack {
                        Text(L("状态检测频率:", "Probe interval:"))
                        Spacer()
                        Picker("", selection: $settings.probeInterval) {
                            Text(L("3 秒", "3s")).tag(3.0)
                            Text(L("6 秒 (默认)", "6s (default)")).tag(6.0)
                            Text(L("10 秒", "10s")).tag(10.0)
                            Text(L("15 秒", "15s")).tag(15.0)
                        }
                        .frame(width: 130)
                    }
                } header: {
                    Text(L("启动与检测", "Startup & Probing"))
                }

                // 配置文件存储路径
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L("配置文件路径:", "Config file path:"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            if !settings.customConfigPath.isEmpty {
                                Text(L("自定路径", "Custom path"))
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                            }
                        }

                        Text(store.configURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(5)

                        HStack(spacing: 8) {
                            Button(L("更改路径...", "Change Path...")) {
                                chooseCustomPath()
                            }
                            .controlSize(.small)

                            if !settings.customConfigPath.isEmpty {
                                Button(L("恢复默认", "Reset to Default")) {
                                    store.resetToDefaultConfigPath()
                                    alertMessage = L("已恢复至默认存储路径", "Restored to the default storage path")
                                    showAlert = true
                                }
                                .controlSize(.small)
                            }

                            Spacer()

                            Button(L("在访达中显示", "Reveal in Finder")) {
                                NSWorkspace.shared.activateFileViewerSelecting([store.configURL])
                            }
                            .controlSize(.small)
                        }
                    }
                } header: {
                    Text(L("配置存储", "Config Storage"))
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)

            Divider()

            // 底部按钮
            HStack {
                Spacer()
                Button(L("完成", "Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 440)
        .alert(isPresented: $showAlert) {
            Alert(title: Text(L("提示", "Notice")), message: Text(alertMessage ?? ""), dismissButton: .default(Text(L("好的", "OK"))))
        }
    }

    private func chooseCustomPath() {
        let savePanel = NSSavePanel()
        savePanel.title = L("选择或新建 ServiceHub 配置文件路径", "Choose or Create ServiceHub Config File Path")
        savePanel.nameFieldStringValue = "services.yaml"
        let yamlType = UTType(filenameExtension: "yaml") ?? .plainText
        savePanel.allowedContentTypes = [yamlType, .plainText]

        if savePanel.runModal() == .OK, let targetURL = savePanel.url {
            do {
                try store.changeConfigPath(to: targetURL, migrateExisting: true)
                alertMessage = L("配置存储路径修改成功！\n已将现有服务配置自动迁移至:\n\(targetURL.path)", "Config path updated!\nExisting services migrated to:\n\(targetURL.path)")
                showAlert = true
            } catch {
                alertMessage = L("修改失败: \(error.localizedDescription)", "Update failed: \(error.localizedDescription)")
                showAlert = true
            }
        }
    }
}
