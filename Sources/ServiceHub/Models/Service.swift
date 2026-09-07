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

public struct Service: Identifiable, Codable, Equatable, Hashable {
    public var id: String
    public var name: String
    public var icon: String
    public var appPath: String?
    public var autoStart: Bool
    public var precondition: PreconditionType
    public var preconditionCustomCommand: String?
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
        preconditionCustomCommand: String? = nil,
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
        self.preconditionCustomCommand = preconditionCustomCommand
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
        self.preconditionCustomCommand = try container.decodeIfPresent(String.self, forKey: .preconditionCustomCommand)
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
