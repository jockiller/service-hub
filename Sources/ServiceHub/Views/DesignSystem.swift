import SwiftUI

// MARK: - Pro Developer-Tool Design Tokens (Raycast / Linear 风格设计系统)

public enum ProTheme {
    // MARK: - Radius
    public static let cornerRadiusSmall: CGFloat = 6
    public static let cornerRadiusCard: CGFloat = 10
    public static let cornerRadiusLarge: CGFloat = 12

    // MARK: - Surfaces & Colors
    public static func cardBackground(colorScheme: ColorScheme, isHovered: Bool, isSelected: Bool) -> Color {
        if isSelected {
            return colorScheme == .dark
                ? Color(red: 0.14, green: 0.17, blue: 0.22)
                : Color(red: 0.94, green: 0.96, blue: 1.0)
        }
        if colorScheme == .dark {
            return isHovered
                ? Color(red: 0.16, green: 0.16, blue: 0.18)
                : Color(red: 0.12, green: 0.12, blue: 0.14)
        } else {
            return isHovered
                ? Color(red: 0.98, green: 0.98, blue: 0.99)
                : Color.white
        }
    }

    public static func cardBorder(colorScheme: ColorScheme, isHovered: Bool, isSelected: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.85)
        }
        if colorScheme == .dark {
            return isHovered
                ? Color.white.opacity(0.18)
                : Color.white.opacity(0.08)
        } else {
            return isHovered
                ? Color.black.opacity(0.16)
                : Color.black.opacity(0.08)
        }
    }

    public static func subtleBackground(colorScheme: ColorScheme, isHovered: Bool = false) -> Color {
        if colorScheme == .dark {
            return isHovered ? Color.white.opacity(0.09) : Color.white.opacity(0.05)
        } else {
            return isHovered ? Color.black.opacity(0.06) : Color.black.opacity(0.03)
        }
    }
}

// MARK: - Pro Card Modifier
public struct ProCardModifier: ViewModifier {
    var statusColor: Color?
    var isSelected: Bool
    var cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false

    public init(statusColor: Color? = nil, isSelected: Bool = false, cornerRadius: CGFloat = ProTheme.cornerRadiusCard) {
        self.statusColor = statusColor
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(ProTheme.cardBackground(colorScheme: colorScheme, isHovered: isHovered, isSelected: isSelected))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        ProTheme.cardBorder(colorScheme: colorScheme, isHovered: isHovered, isSelected: isSelected),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .shadow(
                color: isSelected
                    ? Color.accentColor.opacity(colorScheme == .dark ? 0.3 : 0.15)
                    : (colorScheme == .dark ? Color.black.opacity(isHovered ? 0.35 : 0.2) : Color.black.opacity(isHovered ? 0.08 : 0.03)),
                radius: isHovered ? 5 : 2,
                x: 0,
                y: isHovered ? 2.5 : 1
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - Pro Button Style (Raycast / Linear 扁平微交互按钮)
public enum ProButtonVariant {
    case subtle(tint: Color)
    case solid(tint: Color)
    case danger
    case success
}

public struct ProButtonStyle: ButtonStyle {
    public var tint: Color
    public var isProminent: Bool
    public var size: ControlSize

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false

    public init(tint: Color = .accentColor, isProminent: Bool = false, size: ControlSize = .small) {
        self.tint = tint
        self.isProminent = isProminent
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        let horizontalPadding: CGFloat = size == .mini ? 6 : (size == .small ? 8 : 12)
        let verticalPadding: CGFloat = size == .mini ? 2.5 : (size == .small ? 4 : 6)
        let cornerRadius: CGFloat = size == .mini ? 4 : 6
        let effectiveTint = isEnabled ? tint : Color.secondary.opacity(0.4)

        configuration.label
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .font(.system(size: size == .mini ? 10 : (size == .small ? 11 : 12), weight: .medium))
            .foregroundColor(
                isProminent
                    ? Color.white
                    : (isEnabled ? (isHovered ? effectiveTint : effectiveTint.opacity(0.9)) : Color.secondary)
            )
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                ZStack {
                    if isProminent {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(effectiveTint.opacity(configuration.isPressed ? 0.8 : (isHovered ? 0.9 : 1.0)))
                    } else {
                        // 细致的半透明微底色
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                effectiveTint.opacity(
                                    !isEnabled ? 0.02 : (configuration.isPressed ? 0.22 : (isHovered ? 0.15 : 0.08))
                                )
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isProminent
                            ? Color.white.opacity(0.15)
                            : effectiveTint.opacity(isHovered ? 0.35 : 0.18),
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - 现代精密微光晕状态点 (Raycast 风格状态指示灯)
public struct StatusDotView: View {
    public let color: Color
    public var size: CGFloat = 7
    public var showGlow: Bool = true

    public init(color: Color, size: CGFloat = 7, showGlow: Bool = true) {
        self.color = color
        self.size = size
        self.showGlow = showGlow
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: showGlow ? color.opacity(0.6) : .clear, radius: 2.5, x: 0, y: 0)
    }
}

// MARK: - 统一徽章 / 标签 (Linear 风格等宽参数 Badge)
public struct ProBadgeView: View {
    public let text: String
    public var icon: String? = nil
    public var tint: Color = .secondary
    public var isMonospaced: Bool = false

    public init(_ text: String, icon: String? = nil, tint: Color = .secondary, isMonospaced: Bool = false) {
        self.text = text
        self.icon = icon
        self.tint = tint
        self.isMonospaced = isMonospaced
    }

    public var body: some View {
        HStack(spacing: 3.5) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 9))
            }
            Text(text)
                .font(.system(size: 10, weight: .medium, design: isMonospaced ? .monospaced : .default))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 5.5)
        .padding(.vertical, 2)
        .background(tint.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(tint.opacity(0.2), lineWidth: 0.5)
        )
        .cornerRadius(4)
    }
}

// MARK: - 扩展方法与平滑过渡支持
public extension View {
    /// 应用 Raycast / Linear 风格精密专业卡片样式
    func proCard(statusColor: Color? = nil, isSelected: Bool = false, cornerRadius: CGFloat = ProTheme.cornerRadiusCard) -> some View {
        self.modifier(ProCardModifier(statusColor: statusColor, isSelected: isSelected, cornerRadius: cornerRadius))
    }

    /// 应用 Raycast / Linear 风格精致按钮样式
    func proButton(tint: Color = .accentColor, isProminent: Bool = false, size: ControlSize = .small) -> some View {
        self.buttonStyle(ProButtonStyle(tint: tint, isProminent: isProminent, size: size))
    }

    /// 统一顶部/底部控制栏背景
    func proBar() -> some View {
        self.background(Color(NSColor.windowBackgroundColor).opacity(0.85))
    }

    // --- 兼容旧命名，全面重定向至现代 Pro 体系 ---
    func liquidGlassCard(statusColor: Color = .clear, isSelected: Bool = false, cornerRadius: CGFloat = ProTheme.cornerRadiusCard) -> some View {
        self.proCard(statusColor: statusColor, isSelected: isSelected, cornerRadius: cornerRadius)
    }

    func liquidGlassButton(tint: Color = .accentColor, isProminent: Bool = false) -> some View {
        self.proButton(tint: tint, isProminent: isProminent)
    }

    func liquidGlassBar() -> some View {
        self.proBar()
    }
}
