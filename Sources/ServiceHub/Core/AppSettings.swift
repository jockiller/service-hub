import Foundation
import ServiceManagement
import AppKit
import SwiftUI

public enum AppAppearanceMode: String, CaseIterable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    @MainActor
    public var displayName: String {
        switch self {
        case .system: return L("跟随系统", "System")
        case .light: return L("浅色模式", "Light")
        case .dark: return L("深色模式", "Dark")
        }
    }

    public var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    @AppStorage("probeInterval") public var probeInterval: Double = 6.0
    @AppStorage("customConfigPath") public var customConfigPath: String = ""

    @Published public var appearanceMode: AppAppearanceMode = {
        let raw = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        return AppAppearanceMode(rawValue: raw) ?? .system
    }() {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
            applyWindowAppearance()
        }
    }

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
        DispatchQueue.main.async { [weak self] in
            self?.applyWindowAppearance()
        }
        if hideDockIcon {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.applyDockActivationPolicy()
            }
        }
    }

    public func applyWindowAppearance() {
        switch appearanceMode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
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

            for win in visibleWindows {
                win.makeKeyAndOrderFront(nil)
                win.orderFrontRegardless()
            }
            NSApp.activate()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                WindowManager.shared.isChangingActivationPolicy = false
            }
        }
    }

    public func setHideDockIcon(_ hide: Bool) -> Bool {
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
        if !show && hideDockIcon {
            return false
        }
        if self.showMenuBarIcon != show {
            self.showMenuBarIcon = show
        }
        return true
    }

    public func checkLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        self.isLaunchAtLoginEnabled = (status == .enabled)
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
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
