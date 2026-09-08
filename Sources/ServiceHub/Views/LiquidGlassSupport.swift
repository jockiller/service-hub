import SwiftUI

/// 统一的液态玻璃按钮样式（Liquid Glass Button Style）
/// 为关闭 (红)、重启 (蓝)、启动 (绿)、公网 (紫) 等赋予鲜明的色彩辨识度与玻璃折射光泽
struct LiquidGlassButtonStyle: ButtonStyle {
    var tint: Color
    var size: ControlSize = .small
    var isProminent: Bool = false

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let horizontalPadding: CGFloat = size == .small ? 8.5 : (size == .mini ? 6 : 12)
        let verticalPadding: CGFloat = size == .small ? 4 : (size == .mini ? 2.5 : 6)
        let cornerRadius: CGFloat = size == .mini ? 5 : 7
        let effectiveColor = isEnabled ? tint : Color.secondary.opacity(0.5)

        configuration.label
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(isProminent ? .white : effectiveColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                ZStack {
                    if isProminent {
                        // 高亮实体流体胶囊
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(effectiveColor)
                    } else {
                        // 柔和半透明彩色底色（饱满鲜活，绝非死灰色！）
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(effectiveColor.opacity(
                                !isEnabled ? 0.04 : (configuration.isPressed ? 0.30 : (isHovered ? 0.22 : 0.14))
                            ))
                    }

                    // 顶部弧面液态折射高光（Liquid Glossy Highlight）
                    if isEnabled {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isProminent ? 0.30 : (colorScheme == .dark ? 0.22 : 0.38)),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.35 : 0.55),
                                isProminent ? Color.white.opacity(0.15) : effectiveColor.opacity(isHovered ? 0.50 : 0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isEnabled && (isHovered || isProminent)
                    ? effectiveColor.opacity(isHovered ? 0.25 : 0.15)
                    : Color.clear,
                radius: 4,
                x: 0,
                y: 2
            )
            .scaleEffect(configuration.isPressed ? 0.96 : (isHovered ? 1.02 : 1.0))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { isHovered = $0 }
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
            .animation(.spring(response: 0.12, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

/// 统一的液态玻璃卡片容器修饰符
struct LiquidGlassCardModifier: ViewModifier {
    var statusColor: Color
    var isSelected: Bool
    var cornerRadius: CGFloat = 12

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // 1. 底层状态色彩微漫射光晕 (Ambient Diffuse Glow)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(statusColor.opacity(colorScheme == .dark ? 0.08 : 0.05))

                    // 2. 超薄物理磨砂玻璃材质
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)

                    // 3. 悬停时的液态内部透光增强
                    if isHovered {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(statusColor.opacity(0.04))
                    }
                }
            )
            // 4. 物理玻璃边缘高光描边（上亮下收的折射光线）
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                isSelected
                                    ? Color.accentColor
                                    : Color.white.opacity(colorScheme == .dark ? 0.28 : 0.50),
                                isSelected
                                    ? Color.accentColor.opacity(0.7)
                                    : statusColor.opacity(isHovered ? 0.40 : 0.22),
                                Color.white.opacity(colorScheme == .dark ? 0.06 : 0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            // 5. 景深与悬浮微投影
            .shadow(
                color: isSelected
                    ? Color.accentColor.opacity(0.25)
                    : (isHovered
                        ? statusColor.opacity(0.18)
                        : Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06)),
                radius: isHovered ? 8 : 4,
                x: 0,
                y: isHovered ? 4 : 2
            )
            .scaleEffect(isHovered ? 1.006 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
            .animation(.easeInOut(duration: 0.18), value: isSelected)
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// 应用兼具鲜活色彩与液态玻璃折射光泽的按钮样式
    func liquidGlassButton(tint: Color = .accentColor, isProminent: Bool = false) -> some View {
        self.buttonStyle(LiquidGlassButtonStyle(tint: tint, isProminent: isProminent))
    }

    /// 应用动态透光液态玻璃卡片容器
    func liquidGlassCard(statusColor: Color, isSelected: Bool = false, cornerRadius: CGFloat = 12) -> some View {
        self.modifier(LiquidGlassCardModifier(statusColor: statusColor, isSelected: isSelected, cornerRadius: cornerRadius))
    }

    /// 应用动态吸顶磨砂材质
    func liquidGlassBar() -> some View {
        self.background(.ultraThinMaterial)
    }
}
