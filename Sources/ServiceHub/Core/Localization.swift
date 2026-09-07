import Foundation
import SwiftUI

/// 应用界面语言
public enum AppLanguage: String, CaseIterable {
    case system = "system"
    case chinese = "zh-Hans"
    case english = "en"

    var displayName: String {
        switch self {
        case .system:
            let isEn = UserDefaults.standard.string(forKey: "appLanguage") == AppLanguage.english.rawValue
                || (UserDefaults.standard.string(forKey: "appLanguage") == nil
                    && !Locale.preferredLanguages.first!.lowercased().hasPrefix("zh"))
            return isEn ? "System" : "跟随系统"
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }
}

/// 轻量本地化中心：
/// - 默认跟随系统语言（中文系统 → 中文，其他 → English）
/// - 用户可在设置中强制指定语言，立即生效
@MainActor
public final class Localization: ObservableObject {
    public static let shared = Localization()

    /// 当前生效语言（已解析 system）
    @Published public private(set) var language: AppLanguage

    /// 用户偏好（含 system 选项），持久化到 UserDefaults
    var preference: AppLanguage {
        get {
            AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appLanguage")
            language = resolve(newValue)
        }
    }

    private init() {
        let pref = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
        language = Self.resolveStatic(pref)
    }

    private func resolve(_ pref: AppLanguage) -> AppLanguage {
        Self.resolveStatic(pref)
    }

    private static func resolveStatic(_ pref: AppLanguage) -> AppLanguage {
        guard pref == .system else { return pref }
        let langs = Locale.preferredLanguages
        if let first = langs.first, first.lowercased().hasPrefix("zh") {
            return .chinese
        }
        return .english
    }
}

/// 取当前语言的字符串。键为中文原文；英文缺失时回退中文。
public func L(_ zh: String, _ en: String) -> String {
    MainActor.assumeIsolated {
        Localization.shared.language == .english ? en : zh
    }
}

// MARK: - 非 MainActor 上下文的语言辅助
// 这些辅助函数可在任意并发上下文安全调用（UserDefaults 读取是线程安全的），
// 用于 ProcessRunner / HealthProbe 等后台执行的环境。

/// 当前生效语言是否为英文（线程安全读取）
public func isEnglishUI() -> Bool {
    let pref = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
    let resolved: AppLanguage
    if pref == .system {
        resolved = (Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true) ? .chinese : .english
    } else {
        resolved = pref
    }
    return resolved == .english
}

/// uptime 相关时间单位使用英文
func uptimeIsEnglish() -> Bool { isEnglishUI() }

/// ProcessRunner 超时提示
func timeoutSuffix() -> String {
    isEnglishUI() ? "Command timed out" : "命令执行超时"
}

/// ProcessRunner 启动失败前缀
func startFailedPrefix() -> String {
    isEnglishUI() ? "Start command failed: " : "启动命令失败: "
}

/// DockerScanner 错误信息
func dockerDaemonMsg() -> String {
    isEnglishUI()
        ? "Docker daemon is not running. Please start Docker Desktop or OrbStack first."
        : "Docker 守护进程未启动，请先打开 Docker Desktop 或 OrbStack"
}

func dockerNotInstalledMsg() -> String {
    isEnglishUI()
        ? "Docker environment not detected on this machine. Please install Docker first."
        : "本机未检测到 Docker 环境，请先安装 Docker"
}

func dockerCallFailedMsg() -> String {
    isEnglishUI() ? "Docker invocation failed" : "Docker 调用失败"
}