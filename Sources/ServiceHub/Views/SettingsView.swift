import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var store = ServiceStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 顶部关于横幅
            HStack(spacing: 16) {
                Image(systemName: "server.rack")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("ServiceHub")
                        .font(.title2.bold())
                    Text("版本 \(settings.appVersion) (macOS 原生服务管理与进程守护)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(18)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // 设置表单
            Form {
                Section {
                    Toggle("开机登录时自动启动 ServiceHub", isOn: Binding(
                        get: { settings.isLaunchAtLoginEnabled },
                        set: { settings.setLaunchAtLogin($0) }
                    ))
                    .help("利用 macOS 原生登录项机制，开机进入桌面后自动拉起 ServiceHub 并守护自启服务")

                    Text("提示: 开启后可在「系统设置 > 通用 > 登录项」中查看和统一管理。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } header: {
                    Text("启动与守护")
                }

                Section {
                    Picker("后台状态轮询检测频率:", selection: $settings.probeInterval) {
                        Text("3 秒 (高频即时)").tag(3.0)
                        Text("6 秒 (推荐平衡)").tag(6.0)
                        Text("10 秒 (省电)").tag(10.0)
                        Text("15 秒 (低频)").tag(15.0)
                    }
                    .frame(maxWidth: 240)
                } header: {
                    Text("检测频率")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("服务配置文件路径 (YAML):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(store.configURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(4)

                        HStack {
                            Button("在访达中显示") {
                                NSWorkspace.shared.activateFileViewerSelecting([store.configURL])
                            }
                            .controlSize(.small)

                            Spacer()

                            Text("共纳管 \(store.services.count) 个服务配置")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("配置文件存储")
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)

            Divider()

            // 底部关闭按钮
            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 430)
    }
}
