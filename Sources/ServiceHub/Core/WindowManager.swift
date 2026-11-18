import SwiftUI
import AppKit

@MainActor
public final class WindowManager: NSObject, NSWindowDelegate {
    public static let shared = WindowManager()

    public private(set) var mainWindow: NSWindow?
    private var windowCloseObserver: NSObjectProtocol?

    public var isMainWindowVisible: Bool {
        guard let mainWindow else { return false }
        return mainWindow.isVisible || mainWindow.isMiniaturized
    }

    override private init() {
        super.init()
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let closingWindow = notification.object as? NSWindow
            Task { @MainActor [weak self] in
                self?.syncActivationPolicy(excluding: closingWindow)
            }
        }
    }

    public func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === mainWindow {
            alignTrafficLights(in: window)
        }
    }

    public func windowDidEndLiveResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === mainWindow {
            alignTrafficLights(in: window)
        }
    }

    private func alignTrafficLights(in window: NSWindow) {
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (index, type) in buttons.enumerated() {
            guard let btn = window.standardWindowButton(type),
                  let superview = btn.superview else { continue }
            var frame = btn.frame
            frame.origin.x = 14 + CGFloat(index) * 20
            frame.origin.y = (superview.bounds.height - frame.height) / 2 - 5
            btn.setFrameOrigin(frame.origin)
        }
    }

    /// 根据当前窗口可见性与设置同步 Dock 图标策略：
    /// 有常规窗口打开时显示 Dock 图标（.regular）；主窗口关闭后，若开启了菜单栏图标与隐藏设置则退回 .accessory
    public func syncActivationPolicy(excluding closingWindow: NSWindow? = nil) {
        let settings = AppSettings.shared
        let hasMain = mainWindow.map { $0 !== closingWindow && ($0.isVisible || $0.isMiniaturized) } ?? false
        let hasOther = hasOtherVisibleRegularWindow(excluding: closingWindow)
        let shouldBeRegular = !settings.showMenuBarIcon || !settings.hideDockIcon || hasMain || hasOther
        let targetPolicy: NSApplication.ActivationPolicy = shouldBeRegular ? .regular : .accessory
        if NSApp.activationPolicy() != targetPolicy {
            NSApp.setActivationPolicy(targetPolicy)
        }
    }

    private func hasOtherVisibleRegularWindow(excluding target: NSWindow?) -> Bool {
        NSApp.windows.contains { win in
            win !== mainWindow &&
            win !== target &&
            (win.isVisible || win.isMiniaturized) &&
            !(win is NSPanel) &&
            !win.className.contains("MenuBarExtra") &&
            win.styleMask.contains(.titled)
        }
    }

    public func closeMainWindow() {
        guard let window = mainWindow, window.isVisible || window.isMiniaturized else { return }
        _ = windowShouldClose(window)
    }

    public func closeOtherRegularWindows() {
        for win in NSApp.windows {
            guard win !== mainWindow,
                  win.isVisible || win.isMiniaturized,
                  !(win is NSPanel),
                  !win.className.contains("MenuBarExtra"),
                  win.styleMask.contains(.titled),
                  win.styleMask.contains(.closable) else { continue }
            for sheet in win.sheets {
                win.endSheet(sheet, returnCode: .cancel)
            }
            win.close()
        }
    }

    // MARK: - NSWindowDelegate
    /// 当开启了顶部状态栏常驻图标时，点击主窗口红叉按钮 (或按 ⌘W) 不销毁窗口，仅执行 orderOut 隐藏
    /// 并按设置切回 .accessory 隐藏 Dock 图标，既保留窗口状态又能在下次打开时 0 延迟秒开
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        for sheet in sender.sheets {
            sender.endSheet(sheet, returnCode: .cancel)
        }
        sender.orderOut(nil)
        syncActivationPolicy(excluding: sender)
        return false
    }

    /// 彻底唤起并置顶主控制面板窗口（参考 gpt-load-mac：收起菜单栏弹窗、切到 .regular 显示 Dock、延后一拍激活置顶）
    public func openMainWindow() {
        let window = mainWindow ?? makeMainWindow()

        // 菜单栏面板不会因为本 App 的另一个窗口变成前台而自动收起，手动收掉
        for panel in NSApp.windows where panel.className.contains("MenuBarExtra") && panel.isVisible {
            panel.orderOut(nil)
        }

        // 切成普通 App 后要等下一轮再激活，否则窗口会落在当前前台 App 的下面
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            self.alignTrafficLights(in: window)
        }
    }

    private func makeMainWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ServiceHub"
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 860, height: 600)
        window.delegate = self
        window.contentView = NSHostingView(rootView: MainWindow())
        window.center()
        window.setFrameAutosaveName("ServiceHubMainWindow")
        alignTrafficLights(in: window)
        self.mainWindow = window
        return window
    }
}
