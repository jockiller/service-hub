import SwiftUI

@main
struct ServiceHubApp: App {
    @StateObject private var store = ServiceStore.shared
    @StateObject private var supervisor = Supervisor.shared

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

        // 顶部菜单栏常驻图标 (现代化 Popover Window 风格)
        MenuBarExtra {
            MenuBarView()
        } label: {
            let hasError = store.services.contains(where: { supervisor.statuses[$0.id] == .failed })
            let runningCount = store.services.filter { supervisor.statuses[$0.id] == .running }.count
            Image(systemName: hasError ? "exclamationmark.triangle.fill" : (runningCount > 0 ? "server.rack" : "circle.dotted"))
        }
        .menuBarExtraStyle(.window)
    }
}
