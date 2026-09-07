import Foundation
import SwiftUI

public enum ServiceStatus: String, Codable, CaseIterable {
    case running = "running"
    case stopped = "stopped"
    case starting = "starting"
    case stopping = "stopping"
    case failed = "failed"
    case probing = "probing"
    case unknown = "unknown"

    public var displayName: String {
        switch self {
        case .running: return "运行中"
        case .stopped: return "已停止"
        case .starting: return "正在启动"
        case .stopping: return "正在停止"
        case .failed: return "异常"
        case .probing: return "检测中"
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
        case .unknown: return "questionmark.circle"
        }
    }
}

public struct Service: Identifiable, Codable, Equatable, Hashable {
    public var id: String
    public var name: String
    public var icon: String
    public var autoStart: Bool
    public var startCommand: String
    public var stopCommand: String?
    public var statusCommand: String?
    public var logPath: String?
    public var healthCheckURL: String?

    public init(
        id: String,
        name: String,
        icon: String = "gearshape",
        autoStart: Bool = true,
        startCommand: String,
        stopCommand: String? = nil,
        statusCommand: String? = nil,
        logPath: String? = nil,
        healthCheckURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.autoStart = autoStart
        self.startCommand = startCommand
        self.stopCommand = stopCommand
        self.statusCommand = statusCommand
        self.logPath = logPath
        self.healthCheckURL = healthCheckURL
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
