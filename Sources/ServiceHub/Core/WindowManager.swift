import SwiftUI
import AppKit

@MainActor
public final class WindowManager: NSObject, NSWindowDelegate {
    public static let shared = WindowManager()

    public private(set) weak var mainWindow: NSWindow?

    override private init() {
        super.init()
    }

    public func registerMainWindow(_ window: NSWindow) {
        self.mainWindow = window
        window.delegate = self
    }

    // MARK: - NSWindowDelegate
    /// 当开启了顶部状态栏常驻图标时，点击主窗口红叉按钮 (或按 ⌘W) 不销毁窗口，仅执行 orderOut 隐藏
    /// 这样既保留了窗口的所有状态、滚动位置和搜索框输入，又能在点击「打开主控制面板」时 0 延迟秒开
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if AppSettings.shared.showMenuBarIcon {
            sender.orderOut(nil)
            return false
        }
        return true
    }

    /// 彻底唤起并置顶主控制面板窗口（完美适配 accessory 隐藏 Dock 模式）
    public func openMainWindow(openWindowAction: OpenWindowAction? = nil) {
        // 1. 优先检查已持有的 mainWindow
        if let window = mainWindow {
            bringWindowToFront(window)
            return
        }

        // 2. 检查 NSApp.windows 中是否存在主窗口 (避开状态栏组件、Popover 与辅助面板)
        for window in NSApp.windows {
            if isMainWindowCandidate(window) {
                registerMainWindow(window)
                bringWindowToFront(window)
                return
            }
        }

        // 3. 若窗口当前已被销毁或尚未初始化，调用 SwiftUI 的 openWindowAction 触发重建
        openWindowAction?(id: "main")

        // 4. 延迟一拍再次扫描并置顶新生成的窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            for window in NSApp.windows {
                if self.isMainWindowCandidate(window) {
                    self.registerMainWindow(window)
                    self.bringWindowToFront(window)
                    break
                }
            }
        }
    }

    private func isMainWindowCandidate(_ window: NSWindow) -> Bool {
        if window is NSPanel { return false }
        let className = String(describing: type(of: window))
        if className.contains("StatusBar") || className.contains("Popover") { return false }
        return window.styleMask.contains(.titled)
    }

    private func bringWindowToFront(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 帮助 SwiftUI 捕获底层 NSWindow 实例的微型透明组件
public struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    public init(onWindow: @escaping (NSWindow) -> Void) {
        self.onWindow = onWindow
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindow(window)
            }
        }
    }
}
