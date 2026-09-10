import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let pid = ProcessInfo.processInfo.processIdentifier
        AppLogger.log("[App] ServiceHub 进程启动就绪 (PID: \(pid))，日志写入: \(AppLogger.logFilePath)")

        Task { @MainActor in
            // 等待系统环境与首轮配置就绪，确保开机自启无论窗口是否显示均必定执行
            try? await Task.sleep(nanoseconds: 800_000_000)
            Supervisor.shared.launchServicesAtStartup()

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            Supervisor.shared.checkUpdatesForAllServices()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.shared.openMainWindow()
        return false
    }

    func applicationDidResignActive(_ notification: Notification) {
        WindowManager.shared.handleAppDidResignActive()
    }
}

@main
struct ServiceHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = ServiceStore.shared
    @StateObject private var supervisor = Supervisor.shared
    @StateObject private var settings = AppSettings.shared

    init() {
        setupDockIcon()
    }

    private func setupDockIcon() {
        let bundleURL = Bundle.main.bundleURL
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        ]
        for url in candidates {
            if let u = url, let img = NSImage(contentsOf: u) {
                NSApplication.shared.applicationIconImage = img
                break
            }
        }
    }

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

        // 顶部菜单栏常驻图标 (使用黑白 Template 规范图标，支持安全防重绑定)
        MenuBarExtra(isInserted: safeMenuBarBinding) {
            MenuBarView()
        } label: {
            menuBarLabelView
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarLabelView: some View {
        let hasError = store.services.contains(where: { supervisor.statuses[$0.id] == .failed })
        let runningCount = store.services.filter { supervisor.statuses[$0.id] == .running }.count

        HStack(spacing: 3) {
            if let img = loadMenuBarTemplateImage() {
                Image(nsImage: img)
            } else {
                Image(systemName: "server.rack")
            }

            if hasError {
                Circle()
                    .fill(Color.red)
                    .frame(width: 4, height: 4)
            } else if runningCount > 0 {
                Circle()
                    .fill(Color.green)
                    .frame(width: 4, height: 4)
            }
        }
    }

    private func loadMenuBarTemplateImage() -> NSImage? {
        let bundleURL = Bundle.main.bundleURL
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
            bundleURL.appendingPathComponent("Contents/Resources/MenuBarIcon.png")
        ]
        for url in candidates {
            if let u = url, let img = NSImage(contentsOf: u) {
                img.isTemplate = true
                img.size = NSSize(width: 18, height: 18)
                return img
            }
        }
        return nil
    }
}
