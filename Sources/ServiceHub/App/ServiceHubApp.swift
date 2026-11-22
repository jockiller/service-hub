import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static weak var shared: AppDelegate?
    private static var bypassQuitConfirmation = false

    private var termSignalSource: DispatchSourceSignal?
    private var workspacePowerOffObserver: NSObjectProtocol?
    private var isShowingQuitAlert = false
    private var isSystemPoweringOff = false
    private var shuttingDown = false

    /// 菜单栏面板退出按钮或收到 SIGTERM 时直接退出，不再弹确认框
    @MainActor
    static func quitImmediately() {
        bypassQuitConfirmation = true
        if shared?.isShowingQuitAlert == true {
            NSApp.abortModal()
            return
        }
        NSApp.terminate(nil)
    }

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let pid = ProcessInfo.processInfo.processIdentifier
        AppLogger.log("[App] ServiceHub 进程启动就绪 (PID: \(pid))，日志写入: \(AppLogger.logFilePath)")

        installSignalHandler()
        installWorkspacePowerOffObserver()
        MainActor.assumeIsolated {
            WindowManager.shared.syncActivationPolicy()
            if !AppSettings.shared.showMenuBarIcon {
                WindowManager.shared.openMainWindow()
            }
        }

        Task { @MainActor in
            // 等待系统环境与首轮配置就绪，确保开机自启无论窗口是否显示均必定执行
            try? await Task.sleep(nanoseconds: 800_000_000)
            Supervisor.shared.launchServicesAtStartup()

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            Supervisor.shared.checkUpdatesForAllServices()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            let quitReason = Self.currentQuitReason
            let isSystemSessionQuit = QuitPrompt.isSystemSessionTermination(quitReason)
            let skipConfirmation = Self.bypassQuitConfirmation
                || shuttingDown
                || isSystemPoweringOff
                || isSystemSessionQuit
            Self.bypassQuitConfirmation = false

            if !skipConfirmation {
                if isShowingQuitAlert {
                    NSApp.activate()
                    return .terminateCancel
                }
                if !confirmQuit() {
                    return .terminateCancel
                }
            } else if isShowingQuitAlert {
                NSApp.abortModal()
            }
            if isSystemSessionQuit && !shuttingDown {
                AppLogger.log("[App] 收到系统会话退出事件 (reason=\(Self.fourCharString(quitReason)))，直接退出")
            }
            shuttingDown = true
            CloudflareTunnelManager.shared.stopAllTunnels()
            return .terminateNow
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.shared.openMainWindow()
        return false
    }

    private func installSignalHandler() {
        // 用空处理函数而非 SIG_IGN：避免子进程继承 SIG_IGN
        signal(SIGTERM) { _ in }
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { Self.quitImmediately() }
        }
        source.resume()
        termSignalSource = source
    }

    private func installWorkspacePowerOffObserver() {
        workspacePowerOffObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { Self.handleSystemPowerOff() }
        }
    }

    @MainActor
    private static func handleSystemPowerOff() {
        guard let delegate = shared else { return }
        if !delegate.isSystemPoweringOff {
            AppLogger.log("[App] 收到系统关机/重启/注销通知 (willPowerOffNotification)，跳过退出确认")
        }
        delegate.isSystemPoweringOff = true
        CloudflareTunnelManager.shared.stopAllTunnels()
        if delegate.isShowingQuitAlert {
            NSApp.abortModal()
        }
    }

    private static var currentQuitReason: OSType? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEQuitApplication)
        else { return nil }
        let descriptor = event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))
            ?? event.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason))
        guard let descriptor else { return nil }
        let code = descriptor.enumCodeValue != 0 ? descriptor.enumCodeValue : descriptor.typeCodeValue
        return code != 0 ? code : nil
    }

    private static func fourCharString(_ code: OSType?) -> String {
        guard let code else { return "nil" }
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        if bytes.allSatisfy({ (0x20...0x7E).contains($0) }),
           let str = String(bytes: bytes, encoding: .ascii) {
            return "'\(str)'"
        }
        return String(format: "0x%08x", code)
    }

    @MainActor
    private func confirmQuit() -> Bool {
        for panel in NSApp.windows where panel.className.contains("MenuBarExtra") && panel.isVisible {
            panel.orderOut(nil)
        }

        let hasMainWindow = WindowManager.shared.isMainWindowVisible
        let hasOtherWindow = NSApp.windows.contains { win in
            win !== WindowManager.shared.mainWindow
                && (win.isVisible || win.isMiniaturized)
                && !(win is NSPanel)
                && !win.className.contains("MenuBarExtra")
                && win.styleMask.contains(.titled)
                && win.styleMask.contains(.closable)
        }
        let runningCount = Supervisor.shared.statuses.values.filter { $0 == .running }.count
        let busyCount = Supervisor.shared.isBusy.values.filter { $0 }.count
        let tunnelCount = ServiceStore.shared.services.filter {
            CloudflareTunnelManager.shared.isTunnelActive(for: $0.id)
        }.count

        let prompt = QuitPrompt(
            hasOpenWindow: hasMainWindow || hasOtherWindow,
            onlyMainWindow: hasMainWindow && !hasOtherWindow,
            showMenuBarIcon: AppSettings.shared.showMenuBarIcon,
            runningCount: runningCount,
            busyCount: busyCount,
            tunnelCount: tunnelCount
        )

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        for option in prompt.options {
            let button = alert.addButton(withTitle: option.title)
            if option.isDestructive {
                button.hasDestructiveAction = true
            }
            if option.action == .cancel {
                button.keyEquivalent = "\u{1b}"
            }
        }

        isShowingQuitAlert = true
        defer { isShowingQuitAlert = false }
        NSApp.activate()
        let response = alert.runModal()
        if Self.bypassQuitConfirmation || shuttingDown || isSystemPoweringOff {
            Self.bypassQuitConfirmation = false
            return true
        }
        switch prompt.action(for: response) {
        case .quit:
            return true
        case .closeWindows:
            WindowManager.shared.closeMainWindow()
            WindowManager.shared.closeOtherRegularWindows()
            return false
        case .cancel:
            return false
        }
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
        // 顶部菜单栏常驻图标 (使用黑白 Template 规范图标，支持安全防重绑定)
        MenuBarExtra(isInserted: safeMenuBarBinding) {
            MenuBarView()
                .preferredColorScheme(settings.appearanceMode.colorScheme)
        } label: {
            menuBarLabelView
        }
        .menuBarExtraStyle(.window)

        // 偏好设置窗口 (支持 ⌘,)
        Settings {
            SettingsView()
                .preferredColorScheme(settings.appearanceMode.colorScheme)
        }
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

struct QuitPrompt: Equatable {
    enum Action: Equatable {
        case closeWindows
        case quit
        case cancel
    }

    struct Option: Equatable {
        let title: String
        let action: Action
        var isDestructive = false
    }

    let title: String
    let message: String
    let options: [Option]

    init(
        hasOpenWindow: Bool,
        onlyMainWindow: Bool,
        showMenuBarIcon: Bool,
        runningCount: Int,
        busyCount: Int,
        tunnelCount: Int
    ) {
        title = L("要退出 ServiceHub 吗？", "Quit ServiceHub?")
        let quitTitle = L("退出 ServiceHub", "Quit ServiceHub")
        let busyPrefix = busyCount > 0
            ? L("当前有 \(busyCount) 个服务正在执行启停或操作，退出可能会中断该操作。\n\n",
                "\(busyCount) service(s) currently have an operation in progress. Quitting may interrupt it.\n\n")
            : ""

        let monitoringSummary: String = {
            if runningCount > 0 && tunnelCount > 0 {
                return L(
                    "退出应用将停止对 \(runningCount) 个运行中服务的守护监控，并切断 \(tunnelCount) 个公网映射。",
                    "Quitting will stop monitoring \(runningCount) running service(s) and close \(tunnelCount) public tunnel(s)."
                )
            } else if runningCount > 0 {
                return L(
                    "退出应用将停止对 \(runningCount) 个运行中服务的守护监控。",
                    "Quitting will stop monitoring \(runningCount) running service(s)."
                )
            } else if tunnelCount > 0 {
                return L(
                    "退出应用将切断 \(tunnelCount) 个公网映射。",
                    "Quitting will close \(tunnelCount) public tunnel(s)."
                )
            } else {
                return L(
                    "退出后 ServiceHub 将从菜单栏移除。",
                    "ServiceHub will be removed from the menu bar."
                )
            }
        }()

        if hasOpenWindow && showMenuBarIcon {
            let closeTitle = onlyMainWindow
                ? L("仅关闭主面板", "Close Panel Only")
                : L("仅关闭窗口", "Close Windows Only")
            let target = onlyMainWindow
                ? L("主控制面板", "the main panel")
                : L("当前窗口", "the open windows")

            if runningCount > 0 || tunnelCount > 0 {
                message = "\(busyPrefix)\(monitoringSummary)\n\n" + L(
                    "如果只是想关掉\(target)，请选择「\(closeTitle)」，ServiceHub 会继续在菜单栏运行。",
                    "If you only want to dismiss \(target), choose \"\(closeTitle)\" to keep ServiceHub running in the menu bar."
                )
            } else {
                message = "\(busyPrefix)" + L(
                    "如果只是想关掉\(target)，请选择「\(closeTitle)」，ServiceHub 会继续留在菜单栏。",
                    "If you only want to dismiss \(target), choose \"\(closeTitle)\" to keep ServiceHub in the menu bar."
                )
            }

            options = [
                Option(title: closeTitle, action: .closeWindows),
                Option(title: quitTitle, action: .quit, isDestructive: true),
                Option(title: L("取消", "Cancel"), action: .cancel),
            ]
        } else {
            message = "\(busyPrefix)\(monitoringSummary)"
            options = [
                Option(title: quitTitle, action: .quit, isDestructive: true),
                Option(title: L("取消", "Cancel"), action: .cancel),
            ]
        }
    }

    func action(for response: NSApplication.ModalResponse) -> Action {
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard options.indices.contains(index) else { return .cancel }
        return options[index].action
    }

    static func isSystemSessionTermination(_ reason: OSType?) -> Bool {
        guard let reason else { return false }
        return reason == OSType(kAEShutDown)
            || reason == OSType(kAERestart)
            || reason == OSType(kAEQuitAll)
            || reason == OSType(kAELogOut)
            || reason == OSType(kAEReallyLogOut)
            || reason == OSType(kAEShowRestartDialog)
            || reason == OSType(kAEShowShutdownDialog)
    }
}
