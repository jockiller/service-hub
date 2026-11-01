import SwiftUI

// MARK: - Material 3 Flat Tonal Dashboard Design System (FlClash / M3 Surface Containers)

public enum ProTheme {
    public static let cornerRadiusSmall: CGFloat = 10
    public static let cornerRadiusCard: CGFloat = 18
    public static let cornerRadiusLarge: CGFloat = 22

    /// 主画布背景 (M3 Surface)
    public static func surfaceBase(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.075, blue: 0.086)   // #131316 深邃哑光炭黑
            : Color(red: 0.953, green: 0.961, blue: 0.976)   // #F3F5F9 柔和浅灰白
    }

    /// 卡片容器背景 (M3 Surface Container)
    public static func cardBaseFill(colorScheme: ColorScheme, isHovered: Bool, isSelected: Bool) -> Color {
        if colorScheme == .dark {
            if isSelected {
                return Color(red: 0.145, green: 0.148, blue: 0.172)
            }
            return isHovered
                ? Color(red: 0.135, green: 0.137, blue: 0.156) // #222328
                : Color(red: 0.118, green: 0.118, blue: 0.133) // #1E1E22
        } else {
            return Color.white
        }
    }

    /// 卡片内嵌子容器背景 (M3 Surface Container High)
    public static func innerContainerFill(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.160, green: 0.162, blue: 0.184)     // #29292F 哑光内嵌槽
            : Color(red: 0.945, green: 0.957, blue: 0.976)     // #F1F4F9 柔和浅灰槽
    }

    /// 极简无高光边框
    public static func cardBorder(colorScheme: ColorScheme, isHovered: Bool, isSelected: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.75 : 0.65)
        }
        if colorScheme == .dark {
            return Color.white.opacity(isHovered ? 0.09 : 0.04)
        } else {
            return Color.black.opacity(isHovered ? 0.08 : 0.04)
        }
    }

    public static func subtleBackground(colorScheme: ColorScheme, isHovered: Bool = false) -> Color {
        if colorScheme == .dark {
            return isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.045)
        } else {
            return isHovered ? Color.black.opacity(0.06) : Color.black.opacity(0.035)
        }
    }
}

// MARK: - M3 Matte Canvas Background
public struct M3AmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ProTheme.surfaceBase(colorScheme: colorScheme)
            .ignoresSafeArea()
    }
}

// MARK: - M3 Flat Tonal Card Modifier (零塑料白边、零霓虹发光、纯净哑光大圆角卡片)
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
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(
                shape.fill(ProTheme.cardBaseFill(colorScheme: colorScheme, isHovered: isHovered, isSelected: isSelected))
            )
            .overlay(
                shape.strokeBorder(
                    ProTheme.cardBorder(colorScheme: colorScheme, isHovered: isHovered, isSelected: isSelected),
                    lineWidth: isSelected ? 1.5 : 1.0
                )
            )
            .shadow(
                color: colorScheme == .dark
                    ? Color.black.opacity(isHovered ? 0.28 : 0.14)
                    : Color.black.opacity(isHovered ? 0.07 : 0.035),
                radius: isHovered ? 12 : 6,
                x: 0,
                y: isHovered ? 4 : 2
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - Material 3 Pill / Tonal / Filled Button Style
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
        let horizontalPadding: CGFloat = size == .mini ? 8 : (size == .small ? 11 : 15)
        let verticalPadding: CGFloat = size == .mini ? 4 : (size == .small ? 5.5 : 7.5)
        let effectiveTint = isEnabled ? tint : Color.secondary.opacity(0.4)
        let shape = Capsule(style: .continuous)

        configuration.label
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .font(.system(size: size == .mini ? 10.5 : (size == .small ? 11.5 : 12.5), weight: .semibold))
            .foregroundColor(
                isProminent
                    ? (colorScheme == .dark && effectiveTint == .orange ? Color.black.opacity(0.88) : Color.white)
                    : (isEnabled ? effectiveTint : Color.secondary)
            )
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                shape.fill(
                    isProminent
                        ? effectiveTint.opacity(configuration.isPressed ? 0.82 : (isHovered ? 0.92 : 1.0))
                        : effectiveTint.opacity(!isEnabled ? 0.05 : (configuration.isPressed ? 0.24 : (isHovered ? 0.18 : 0.12)))
                )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - 状态圆点
public struct StatusDotView: View {
    public let color: Color
    public var size: CGFloat = 6.5
    public var showGlow: Bool = false

    public init(color: Color, size: CGFloat = 6.5, showGlow: Bool = false) {
        self.color = color
        self.size = size
        self.showGlow = showGlow
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

// MARK: - M3 Flat Tonal Chip (无白边、扁平哑光胶囊标签)
public struct ProBadgeView: View {
    public let text: String
    public var icon: String? = nil
    public var tint: Color = .secondary
    public var isMonospaced: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    public init(_ text: String, icon: String? = nil, tint: Color = .secondary, isMonospaced: Bool = false) {
        self.text = text
        self.icon = icon
        self.tint = tint
        self.isMonospaced = isMonospaced
    }

    public var body: some View {
        let isNeutral = (tint == .secondary || tint == .primary)
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(isNeutral ? .secondary : tint)
            }
            Text(text)
                .font(.system(size: 10.5, weight: .semibold, design: isMonospaced ? .monospaced : .default))
                .foregroundColor(isNeutral ? .primary.opacity(0.88) : tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            isNeutral
                ? ProTheme.innerContainerFill(colorScheme: colorScheme)
                : tint.opacity(colorScheme == .dark ? 0.16 : 0.12),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }
}

// MARK: - M3 Bar Modifier
@MainActor
public struct M3GlassBarModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        content
            .background(ProTheme.surfaceBase(colorScheme: colorScheme))
    }
}

public extension View {
    /// 应用 Material 3 + Liquid Glass 卡片样式
    @MainActor
    func proCard(statusColor: Color? = nil, isSelected: Bool = false, cornerRadius: CGFloat = ProTheme.cornerRadiusCard) -> some View {
        self.modifier(ProCardModifier(statusColor: statusColor, isSelected: isSelected, cornerRadius: cornerRadius))
    }

    /// 应用 Material 3 胶囊按钮样式
    @MainActor
    func proButton(tint: Color = .accentColor, isProminent: Bool = false, size: ControlSize = .small) -> some View {
        self.buttonStyle(ProButtonStyle(tint: tint, isProminent: isProminent, size: size))
    }

    /// 统一顶部/底部液态玻璃控制栏背景
    @MainActor
    func proBar() -> some View {
        self.modifier(M3GlassBarModifier())
    }

    @MainActor
    func liquidGlassCard(statusColor: Color = .clear, isSelected: Bool = false, cornerRadius: CGFloat = ProTheme.cornerRadiusCard) -> some View {
        self.proCard(statusColor: statusColor, isSelected: isSelected, cornerRadius: cornerRadius)
    }

    @MainActor
    func liquidGlassButton(tint: Color = .accentColor, isProminent: Bool = false) -> some View {
        self.proButton(tint: tint, isProminent: isProminent)
    }

    @MainActor
    func liquidGlassBar() -> some View {
        self.proBar()
    }
}
