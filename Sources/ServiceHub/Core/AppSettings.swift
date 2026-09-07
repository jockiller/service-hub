import Foundation
import ServiceManagement
import SwiftUI

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    @AppStorage("probeInterval") public var probeInterval: Double = 6.0
    @Published public var isLaunchAtLoginEnabled: Bool = false

    public let appVersion: String = {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "v\(ver)"
    }()

    public init() {
        checkLaunchAtLoginStatus()
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
