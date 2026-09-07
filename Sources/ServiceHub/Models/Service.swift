import Foundation
import SwiftUI

public enum ServiceStatus: String, Codable, CaseIterable {
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
        case .running: return "运行中"
        case .stopped: return "已停止"
        case .starting: return "正在启动"
        case .stopping: return "正在停止"
        case .failed: return "异常"
        case .probing: return "检测中"
        case .waitingPrecondition: return "等待前置条件"
        case .unknown: return "未知"
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

public enum PreconditionType: String, Codable, CaseIterable {
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
        case .none: return "无前置限制 (随时可启)"
        case .networkConnected: return "互联网已连通"
        case .networkDisconnected: return "网络已断开 (离线环境)"
        case .wifiConnected: return "Wi-Fi 已连接"
        case .wifiDisconnected: return "Wi-Fi 未连接 / 已断开"
        case .vpnActive: return "VPN / 代理隧道已连通"
        case .bluetoothOn: return "蓝牙已开启"
        case .bluetoothOff: return "蓝牙已关闭"
        case .bluetoothConnected: return "蓝牙设备已连接"
        case .acPower: return "已连接电源适配器 (插电)"
        case .onBattery: return "使用电池供电中"
        case .externalDisplay: return "已连接外接显示器"
        case .volumeMounted: return "指定外部磁盘/卷宗已挂载"
        case .portAvailable: return "指定本地端口可用 (未被占用)"
        case .hostReachable: return "指定主机/IP 地址可达"
        case .custom: return "自定义 Shell 检测命令"
        }
    }

    public var category: String {
        switch self {
        case .none: return "通用"
        case .networkConnected, .networkDisconnected, .wifiConnected, .wifiDisconnected, .vpnActive:
            return "网络设置"
        case .bluetoothOn, .bluetoothOff, .bluetoothConnected:
            return "蓝牙设置"
        case .acPower, .onBattery, .externalDisplay, .volumeMounted:
            return "电源与硬件"
        case .portAvailable, .hostReachable, .custom:
            return "高级与自定义"
        }
    }

    public var shortName: String {
        switch self {
        case .none: return ""
        case .networkConnected: return "需联网"
        case .networkDisconnected: return "需离线"
        case .wifiConnected: return "需Wi-Fi"
        case .wifiDisconnected: return "需断Wi-Fi"
        case .vpnActive: return "需VPN"
        case .bluetoothOn: return "需开蓝牙"
        case .bluetoothOff: return "需关蓝牙"
        case .bluetoothConnected: return "需连蓝牙"
        case .acPower: return "需插电"
        case .onBattery: return "需电池"
        case .externalDisplay: return "需外接屏"
        case .volumeMounted: return "需挂载盘"
        case .portAvailable: return "需端口空闲"
        case .hostReachable: return "需主机可达"
        case .custom: return "自定义前置"
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
            return "选填: 指定 Wi-Fi 名称 (SSID)，留空代表任意 Wi-Fi"
        case .bluetoothConnected:
            return "选填: 指定蓝牙设备名称 (如 AirPods Pro)，留空代表任意蓝牙设备"
        case .volumeMounted:
            return "必填: 挂载卷宗路径或名称 (如 /Volumes/Backup 或 Backup)"
        case .portAvailable:
            return "必填: 本地端口号 (如 3001, 8080)"
        case .hostReachable:
            return "必填: 目标主机名或 IP (如 192.168.50.1 或 baidu.com)"
        case .custom:
            return "必填: 检测命令，退出码为 0 则满足"
        default:
            return nil
        }
    }
}

public struct Service: Identifiable, Codable, Equatable, Hashable {
    public var id: String
    public var name: String
    public var icon: String
    public var appPath: String?
    public var autoStart: Bool
    public var precondition: PreconditionType
    public var preconditionParam: String?
    public var startCommand: String
    public var stopCommand: String?
    public var statusCommand: String?
    public var logPath: String?
    public var healthCheckURL: String?

    public init(
        id: String,
        name: String,
        icon: String = "gearshape",
        appPath: String? = nil,
        autoStart: Bool = true,
        precondition: PreconditionType = .none,
        preconditionParam: String? = nil,
        startCommand: String,
        stopCommand: String? = nil,
        statusCommand: String? = nil,
        logPath: String? = nil,
        healthCheckURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.appPath = appPath
        self.autoStart = autoStart
        self.precondition = precondition
        self.preconditionParam = preconditionParam
        self.startCommand = startCommand
        self.stopCommand = stopCommand
        self.statusCommand = statusCommand
        self.logPath = logPath
        self.healthCheckURL = healthCheckURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "gearshape"
        self.appPath = try container.decodeIfPresent(String.self, forKey: .appPath)
        self.autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? true
        self.precondition = try container.decodeIfPresent(PreconditionType.self, forKey: .precondition) ?? .none
        self.preconditionParam = try container.decodeIfPresent(String.self, forKey: .preconditionParam)
        self.startCommand = try container.decode(String.self, forKey: .startCommand)
        self.stopCommand = try container.decodeIfPresent(String.self, forKey: .stopCommand)
        self.statusCommand = try container.decodeIfPresent(String.self, forKey: .statusCommand)
        self.logPath = try container.decodeIfPresent(String.self, forKey: .logPath)
        self.healthCheckURL = try container.decodeIfPresent(String.self, forKey: .healthCheckURL)
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
