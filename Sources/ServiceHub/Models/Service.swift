import Foundation
import SwiftUI

public enum ServiceStatus: String, Codable, CaseIterable, Sendable {
    case running = "running"
    case stopped = "stopped"
    case starting = "starting"
    case stopping = "stopping"
    case failed = "failed"
    case probing = "probing"
    case waitingPrecondition = "waiting"
    case unknown = "unknown"

    public var displayName: String {
        switch self {
        case .running: return L("运行中", "Running")
        case .stopped: return L("已停止", "Stopped")
        case .starting: return L("正在启动", "Starting")
        case .stopping: return L("正在停止", "Stopping")
        case .failed: return L("异常", "Failed")
        case .probing: return L("检测中", "Probing")
        case .waitingPrecondition: return L("等待前置条件", "Waiting")
        case .unknown: return L("未知", "Unknown")
        }
    }

    public var color: Color {
        switch self {
        case .running: return .green
        case .stopped: return .secondary
        case .starting: return .blue
        case .stopping: return .orange
        case .failed: return .red
        case .probing: return .yellow
        case .waitingPrecondition: return .orange
        case .unknown: return .gray
        }
    }

    public var systemIcon: String {
        switch self {
        case .running: return "checkmark.circle.fill"
        case .stopped: return "stop.circle"
        case .starting: return "arrow.clockwise.circle"
        case .stopping: return "arrow.down.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .probing: return "waveform.path.ecg"
        case .waitingPrecondition: return "clock.badge.exclamationmark"
        case .unknown: return "questionmark.circle"
        }
    }
}

public enum PreconditionType: String, Codable, CaseIterable, Sendable {
    case none = "none"

    // 网络
    case networkConnected = "network_connected"
    case networkDisconnected = "network_disconnected"
    case wifiConnected = "wifi_connected"
    case wifiDisconnected = "wifi_disconnected"
    case vpnActive = "vpn_active"

    // 蓝牙
    case bluetoothOn = "bluetooth_on"
    case bluetoothOff = "bluetooth_off"
    case bluetoothConnected = "bluetooth_connected"

    // 电源与硬件
    case acPower = "ac_power"
    case onBattery = "on_battery"
    case externalDisplay = "external_display"
    case volumeMounted = "volume_mounted"

    // 高级
    case portAvailable = "port_available"
    case hostReachable = "host_reachable"
    case custom = "custom"

    public var displayName: String {
        switch self {
        case .none: return L("无前置限制 (随时可启)", "No restrictions (start anytime)")
        case .networkConnected: return L("互联网已连通", "Internet connected")
        case .networkDisconnected: return L("网络已断开 (离线环境)", "Network disconnected (offline)")
        case .wifiConnected: return L("Wi-Fi 已连接", "Wi-Fi connected")
        case .wifiDisconnected: return L("Wi-Fi 未连接 / 已断开", "Wi-Fi disconnected")
        case .vpnActive: return L("VPN / 代理隧道已连通", "VPN / proxy tunnel active")
        case .bluetoothOn: return L("蓝牙已开启", "Bluetooth on")
        case .bluetoothOff: return L("蓝牙已关闭", "Bluetooth off")
        case .bluetoothConnected: return L("蓝牙设备已连接", "Bluetooth device connected")
        case .acPower: return L("已连接电源适配器 (插电)", "AC power connected")
        case .onBattery: return L("使用电池供电中", "On battery power")
        case .externalDisplay: return L("已连接外接显示器", "External display connected")
        case .volumeMounted: return L("指定外部磁盘/卷宗已挂载", "External volume mounted")
        case .portAvailable: return L("指定本地端口可用 (未被占用)", "Local port available (not in use)")
        case .hostReachable: return L("指定主机/IP 地址可达", "Host / IP reachable")
        case .custom: return L("自定义 Shell 检测命令", "Custom shell check command")
        }
    }

    public var category: String {
        switch self {
        case .none: return L("通用", "General")
        case .networkConnected, .networkDisconnected, .wifiConnected, .wifiDisconnected, .vpnActive:
            return L("网络设置", "Network")
        case .bluetoothOn, .bluetoothOff, .bluetoothConnected:
            return L("蓝牙设置", "Bluetooth")
        case .acPower, .onBattery, .externalDisplay, .volumeMounted:
            return L("电源与硬件", "Power & Hardware")
        case .portAvailable, .hostReachable, .custom:
            return L("高级与自定义", "Advanced & Custom")
        }
    }

    public var shortName: String {
        switch self {
        case .none: return ""
        case .networkConnected: return L("需联网", "Net")
        case .networkDisconnected: return L("需离线", "Offline")
        case .wifiConnected: return L("需Wi-Fi", "Wi-Fi")
        case .wifiDisconnected: return L("需断Wi-Fi", "No Wi-Fi")
        case .vpnActive: return L("需VPN", "VPN")
        case .bluetoothOn: return L("需开蓝牙", "BT on")
        case .bluetoothOff: return L("需关蓝牙", "BT off")
        case .bluetoothConnected: return L("需连蓝牙", "BT device")
        case .acPower: return L("需插电", "AC")
        case .onBattery: return L("需电池", "Battery")
        case .externalDisplay: return L("需外接屏", "Display")
        case .volumeMounted: return L("需挂载盘", "Volume")
        case .portAvailable: return L("需端口空闲", "Port")
        case .hostReachable: return L("需主机可达", "Host")
        case .custom: return L("自定义前置", "Custom")
        }
    }

    public var systemIcon: String {
        switch self {
        case .none: return "bolt"
        case .networkConnected: return "globe"
        case .networkDisconnected: return "globe.badge.chevron.backward"
        case .wifiConnected: return "wifi"
        case .wifiDisconnected: return "wifi.slash"
        case .vpnActive: return "shield.lefthalf.filled"
        case .bluetoothOn: return "dot.radiowaves.left.and.right"
        case .bluetoothOff: return "slash.circle"
        case .bluetoothConnected: return "headphones"
        case .acPower: return "bolt.fill"
        case .onBattery: return "battery.75"
        case .externalDisplay: return "display"
        case .volumeMounted: return "internaldrive"
        case .portAvailable: return "door.left.hand.open"
        case .hostReachable: return "antenna.radiowaves.left.and.right"
        case .custom: return "terminal"
        }
    }

    /// 参数输入提示（返回 nil 表示该条件不需要额外参数）
    public var paramPrompt: String? {
        switch self {
        case .wifiConnected:
            return L("选填: 指定 Wi-Fi 名称 (SSID)，留空代表任意 Wi-Fi", "Optional: Wi-Fi name (SSID); empty means any Wi-Fi")
        case .bluetoothConnected:
            return L("选填: 指定蓝牙设备名称 (如 AirPods Pro)，留空代表任意蓝牙设备", "Optional: Bluetooth device name (e.g. AirPods Pro); empty means any device")
        case .volumeMounted:
            return L("必填: 挂载卷宗路径或名称 (如 /Volumes/Backup 或 Backup)", "Required: volume path or name (e.g. /Volumes/Backup or Backup)")
        case .portAvailable:
            return L("必填: 本地端口号 (如 3001, 8080)", "Required: local port (e.g. 3001, 8080)")
        case .hostReachable:
            return L("必填: 目标主机名或 IP (如 192.168.50.1 或 baidu.com)", "Required: hostname or IP (e.g. 192.168.50.1 or baidu.com)")
        case .custom:
            return L("必填: 检测命令，退出码为 0 则满足", "Required: check command; exit code 0 means satisfied")
        default:
            return nil
        }
    }
}

public enum TunnelMode: String, Codable, CaseIterable, Sendable {
    case quick = "quick"   // 快速临时公网域名 (*.trycloudflare.com)
    case token = "token"   // 正式自定域名 (使用 Cloudflare Zero Trust Token)

    public var displayName: String {
        switch self {
        case .quick: return L("临时公共域名 (*.trycloudflare.com 免费免密)", "Temporary public domain (*.trycloudflare.com, free)")
        case .token: return L("正式自定义域名 (填入 Cloudflare Token)", "Custom domain (with Cloudflare Token)")
        }
    }
}

public struct TunnelConfig: Codable, Equatable, Hashable, Sendable {
    public var enabled: Bool
    public var mode: TunnelMode
    public var token: String?
    public var customDomain: String?
    public var targetURL: String?

    public init(
        enabled: Bool = false,
        mode: TunnelMode = .quick,
        token: String? = nil,
        customDomain: String? = nil,
        targetURL: String? = nil
    ) {
        self.enabled = enabled
        self.mode = mode
        self.token = token
        self.customDomain = customDomain
        self.targetURL = targetURL
    }
}

public struct Service: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var icon: String
    public var appPath: String?
    public var autoStart: Bool
    /// 随 ServiceHub 应用启动而自动拉起该服务（与 autoStart 守护互相独立）
    public var launchOnAppStart: Bool
    public var maxRestarts: Int
    public var restartWindowSeconds: Int
    public var precondition: PreconditionType
    public var preconditionParam: String?
    public var startCommand: String
    public var stopCommand: String?
    public var statusCommand: String?
    public var logPath: String?
    public var healthCheckURL: String?
    /// 健康检查失败 N 次后强制重启（即使 statusCommand 仍判活）
    /// nil 或 0 = 关闭该功能；需要配置了 healthCheckURL 才生效
    public var healthCheckRestartThreshold: Int?
    public var webURL: String?
    public var openWebURLOnStart: Bool
    public var tunnelConfig: TunnelConfig?

    public init(
        id: String,
        name: String,
        icon: String = "gearshape",
        appPath: String? = nil,
        autoStart: Bool = true,
        launchOnAppStart: Bool = true,
        maxRestarts: Int = 3,
        restartWindowSeconds: Int = 60,
        precondition: PreconditionType = .none,
        preconditionParam: String? = nil,
        startCommand: String,
        stopCommand: String? = nil,
        statusCommand: String? = nil,
        logPath: String? = nil,
        healthCheckURL: String? = nil,
        healthCheckRestartThreshold: Int? = nil,
        webURL: String? = nil,
        openWebURLOnStart: Bool = false,
        tunnelConfig: TunnelConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.appPath = appPath
        self.autoStart = autoStart
        self.launchOnAppStart = launchOnAppStart
        self.maxRestarts = maxRestarts
        self.restartWindowSeconds = restartWindowSeconds
        self.precondition = precondition
        self.preconditionParam = preconditionParam
        self.startCommand = startCommand
        self.stopCommand = stopCommand
        self.statusCommand = statusCommand
        self.logPath = logPath
        self.healthCheckURL = healthCheckURL
        self.healthCheckRestartThreshold = healthCheckRestartThreshold
        self.webURL = webURL
        self.openWebURLOnStart = openWebURLOnStart
        self.tunnelConfig = tunnelConfig
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "gearshape"
        self.appPath = try container.decodeIfPresent(String.self, forKey: .appPath)
        self.autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? true
        self.launchOnAppStart = try container.decodeIfPresent(Bool.self, forKey: .launchOnAppStart) ?? true
        self.maxRestarts = try container.decodeIfPresent(Int.self, forKey: .maxRestarts) ?? 3
        self.restartWindowSeconds = try container.decodeIfPresent(Int.self, forKey: .restartWindowSeconds) ?? 60
        self.precondition = try container.decodeIfPresent(PreconditionType.self, forKey: .precondition) ?? .none
        self.preconditionParam = try container.decodeIfPresent(String.self, forKey: .preconditionParam)
        self.startCommand = try container.decode(String.self, forKey: .startCommand)
        self.stopCommand = try container.decodeIfPresent(String.self, forKey: .stopCommand)
        self.statusCommand = try container.decodeIfPresent(String.self, forKey: .statusCommand)
        self.logPath = try container.decodeIfPresent(String.self, forKey: .logPath)
        self.healthCheckURL = try container.decodeIfPresent(String.self, forKey: .healthCheckURL)
        self.healthCheckRestartThreshold = try container.decodeIfPresent(Int.self, forKey: .healthCheckRestartThreshold)
        self.webURL = try container.decodeIfPresent(String.self, forKey: .webURL)
        self.openWebURLOnStart = try container.decodeIfPresent(Bool.self, forKey: .openWebURLOnStart) ?? false
        self.tunnelConfig = try container.decodeIfPresent(TunnelConfig.self, forKey: .tunnelConfig)
    }
}

public struct ServiceConfigFile: Codable {
    public var version: Int
    public var services: [Service]

    public init(version: Int = 1, services: [Service] = []) {
        self.version = version
        self.services = services
    }
}
