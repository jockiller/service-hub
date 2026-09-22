import Foundation

public struct ServiceGroup: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var icon: String
    public var isCollapsed: Bool
    public var order: Int

    public init(
        id: String = UUID().uuidString,
        name: String,
        icon: String = "folder",
        isCollapsed: Bool = false,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isCollapsed = isCollapsed
        self.order = order
    }
}
