import Foundation
import ServiceManagement
import AppKit
import SwiftUI

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    @AppStorage("probeInterval") public var probeInterval: Double = 6.0
    @AppStorage("hideDockIcon") public var hideDockIcon: Bool = false
    @AppStorage("showMenuBarIcon") public var showMenuBarIcon: Bool = true
    @AppStorage("customConfigPath") public var customConfigPath: String = ""

    @Published public var isLaunchAtLoginEnabled: Bool = false

    public let appVersion: String = {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "v\(ver)"
    }()

    public init() {
        checkLaunchAtLoginStatus()
        applyDockActivationPolicy()
    }

    public func applyDockActivationPolicy() {
        if hideDockIcon {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }

    public func setHideDockIcon(_ hide: Bool) -> Bool {
        // 安全保护：不能在状态栏图标未开启时同时隐藏 Dock 图标，否则用户无法唤起主窗口
        if hide && !showMenuBarIcon {
            return false
        }
        self.hideDockIcon = hide
        applyDockActivationPolicy()
        return true
    }

    public func setShowMenuBarIcon(_ show: Bool) -> Bool {
        // 安全保护：不能在隐藏 Dock 的同时关闭状态栏图标
        if !show && hideDockIcon {
            return false
        }
        self.showMenuBarIcon = show
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
