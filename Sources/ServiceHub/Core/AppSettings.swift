import Foundation
import ServiceManagement
import AppKit
import SwiftUI

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    @AppStorage("probeInterval") public var probeInterval: Double = 6.0
    @AppStorage("customConfigPath") public var customConfigPath: String = ""

    @Published public var hideDockIcon: Bool = UserDefaults.standard.bool(forKey: "hideDockIcon") {
        didSet {
            UserDefaults.standard.set(hideDockIcon, forKey: "hideDockIcon")
        }
    }

    @Published public var showMenuBarIcon: Bool = (UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon")
        }
    }

    @Published public var isLaunchAtLoginEnabled: Bool = false

    public let appVersion: String = {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "v\(ver)"
    }()

    public init() {
        checkLaunchAtLoginStatus()
        if hideDockIcon {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.applyDockActivationPolicy()
            }
        }
    }

    public func applyDockActivationPolicy() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            WindowManager.shared.isChangingActivationPolicy = true

            let visibleWindows = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }

            if self.hideDockIcon {
                NSApp.setActivationPolicy(.accessory)
            } else {
                NSApp.setActivationPolicy(.regular)
            }

            // 保持当前所有已可见的主窗口与设置界面不因策略变更而瞬间消失
            for win in visibleWindows {
                win.makeKeyAndOrderFront(nil)
                win.orderFrontRegardless()
            }
            NSApp.activate(ignoringOtherApps: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                WindowManager.shared.isChangingActivationPolicy = false
            }
        }
    }

    public func setHideDockIcon(_ hide: Bool) -> Bool {
        // 安全保护：不能在状态栏图标未开启时同时隐藏 Dock 图标，否则用户无法唤起主窗口
        if hide && !showMenuBarIcon {
            return false
        }
        if self.hideDockIcon != hide {
            self.hideDockIcon = hide
            applyDockActivationPolicy()
        }
        return true
    }

    public func setShowMenuBarIcon(_ show: Bool) -> Bool {
        // 安全保护：不能在隐藏 Dock 的同时关闭状态栏图标
        if !show && hideDockIcon {
            return false
        }
        if self.showMenuBarIcon != show {
            self.showMenuBarIcon = show
        }
        return true
    }

    public func checkLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            self.isLaunchAtLoginEnabled = (status == .enabled)
        }
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                checkLaunchAtLoginStatus()
            } catch {
                print("[-] 设置开机自启动失败: \(error.localizedDescription)")
                self.isLaunchAtLoginEnabled = enabled
            }
        }
    }
}
