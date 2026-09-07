import SwiftUI

@main
struct ServiceHubApp: App {
    @StateObject private var store = ServiceStore.shared
    @StateObject private var supervisor = Supervisor.shared
    @StateObject private var settings = AppSettings.shared

    private var safeMenuBarBinding: Binding<Bool> {
        Binding(
            get: { settings.showMenuBarIcon },
            set: { val in
                if settings.showMenuBarIcon != val {
                    _ = settings.setShowMenuBarIcon(val)
                }
            }
        )
    }

    var body: some Scene {
        // 主程序窗口
        WindowGroup("ServiceHub", id: "main") {
            MainWindow()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
        }

        // 偏好设置窗口 (支持 ⌘,)
        Settings {
            SettingsView()
        }

        // 顶部菜单栏常驻图标 (使用安全防重绑定，彻底杜绝递归死循环)
        MenuBarExtra(isInserted: safeMenuBarBinding) {
            MenuBarView()
        } label: {
            let hasError = store.services.contains(where: { supervisor.statuses[$0.id] == .failed })
            let runningCount = store.services.filter { supervisor.statuses[$0.id] == .running }.count
            Image(systemName: hasError ? "exclamationmark.triangle.fill" : (runningCount > 0 ? "server.rack" : "circle.dotted"))
        }
        .menuBarExtraStyle(.window)
    }
}
