import SwiftUI
import AppKit

@MainActor
public final class WindowManager: NSObject, NSWindowDelegate {
    public static let shared = WindowManager()

    public private(set) weak var mainWindow: NSWindow?
    /// 标记是否正在切换激活策略，防止在开关切换过程中意外触发失去焦点关闭
    public var isChangingActivationPolicy: Bool = false

    override private init() {
        super.init()
    }

    public func registerMainWindow(_ window: NSWindow) {
        self.mainWindow = window
        window.delegate = self
    }

    /// 当应用失去焦点时处理窗口自动隐藏（仅在「隐藏 Dock 图标」的附属模式下等待失去焦点后自动收起）
    public func handleAppDidResignActive() {
        guard !isChangingActivationPolicy else { return }
        guard AppSettings.shared.hideDockIcon else { return }

        // 如果当前有模态弹窗（如文件选择、确认对话框），不收起，避免中断用户操作
        if NSApp.modalWindow != nil { return }

        // 附属模式下主窗口失去焦点自动收起
        if let window = mainWindow, window.isVisible {
            window.orderOut(nil)
        }
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

    /// 彻底唤起并置顶主控制面板窗口（完美适配 accessory 隐藏 Dock 模式，严格单窗口防重）
    public func openMainWindow(openWindowAction: OpenWindowAction? = nil) {
        // 1. 扫描 NSApp.windows，确保只保留唯一主窗口，清理任何可能出现的副本
        var targetWindow: NSWindow? = mainWindow
        var extraWindows: [NSWindow] = []

        for window in NSApp.windows {
            if isMainWindowCandidate(window) {
                if targetWindow == nil {
                    targetWindow = window
                } else if targetWindow !== window {
                    extraWindows.append(window)
                }
            }
        }

        // 立即关闭任何多余的重复窗口
        for extra in extraWindows {
            extra.close()
        }

        if let window = targetWindow {
            registerMainWindow(window)
            bringWindowToFront(window)
            return
        }

        // 2. 若窗口当前已被销毁或尚未初始化，调用 SwiftUI 的 openWindowAction 触发重建
        openWindowAction?(id: "main")

        // 3. 延迟一拍再次扫描并置顶新生成的窗口，同时再次清理冗余
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            var first: NSWindow? = nil
            for window in NSApp.windows {
                if self.isMainWindowCandidate(window) {
                    if first == nil {
                        first = window
                    } else {
                        window.close()
                    }
                }
            }
            if let w = first {
                self.registerMainWindow(w)
                self.bringWindowToFront(w)
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
