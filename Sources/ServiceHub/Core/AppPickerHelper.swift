import Foundation
import AppKit
import UniformTypeIdentifiers

public struct AppMetadata {
    public let appName: String
    public let appPath: String
    public let executableName: String
    public let recommendedStartCmd: String
    public let recommendedStopCmd: String
    public let recommendedStatusCmd: String
}

public final class AppPickerHelper {
    /// 弹出选择 macOS 应用程序 (.app)
    @MainActor
    public static func pickApplication() -> AppMetadata? {
        let openPanel = NSOpenPanel()
        openPanel.title = "选择 macOS 应用程序"
        openPanel.prompt = "选取应用"
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications")
        openPanel.allowedContentTypes = [.application, .applicationBundle]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return nil
        }

        let bundle = Bundle(url: url)
        let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")

        let execName = bundle?.executableURL?.lastPathComponent
            ?? url.deletingPathExtension().lastPathComponent

        let appPath = url.path
        let startCmd = "open -a \"\(appPath)\""
        let stopCmd = "killall \"\(execName)\" 2>/dev/null || pkill -f \"\(execName)\""
        let statusCmd = "pgrep -x \"\(execName)\" >/dev/null 2>&1 || pgrep -f \"\(execName)\" >/dev/null 2>&1"

        return AppMetadata(
            appName: displayName,
            appPath: appPath,
            executableName: execName,
            recommendedStartCmd: startCmd,
            recommendedStopCmd: stopCmd,
            recommendedStatusCmd: statusCmd
        )
    }

    /// 弹出选择任意文件（脚本、二进制、日志文件等）
    @MainActor
    public static func pickFile(title: String = "选择文件") -> String? {
        let openPanel = NSOpenPanel()
        openPanel.title = title
        openPanel.prompt = "选取"
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return nil
        }
        return url.path
    }
}
