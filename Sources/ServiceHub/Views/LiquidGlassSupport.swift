import SwiftUI

/// 苹果官方 Liquid Glass 统一系统适配层
/// 在 macOS 26+ / macOS 27 真实系统上无缝激活苹果官方原生 .glass 与 .glassEffect API；
/// 同时保持向后平滑兼容。
extension View {
    /// 应用苹果官方原生液态玻璃按钮（macOS 26+ 激活系统 .glass，旧版本平滑回退）
    @ViewBuilder
    func liquidGlassButton(tint: Color? = nil, isProminent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if isProminent {
                if let tint {
                    self.buttonStyle(.glassProminent).tint(tint)
                } else {
                    self.buttonStyle(.glassProminent)
                }
            } else {
                if let tint {
                    self.buttonStyle(.glass).tint(tint)
                } else {
                    self.buttonStyle(.glass)
                }
            }
        } else {
            if isProminent {
                if let tint {
                    self.buttonStyle(.borderedProminent).tint(tint)
                } else {
                    self.buttonStyle(.borderedProminent)
                }
            } else {
                if let tint {
                    self.buttonStyle(.bordered).tint(tint)
                } else {
                    self.buttonStyle(.bordered)
                }
            }
        }
    }

    /// 应用苹果官方原生液态玻璃卡片容器（macOS 26+ 激活系统 .glassEffect）
    @ViewBuilder
    func liquidGlassCard(cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// 应用苹果官方原生液态玻璃吸顶/条状材质
    @ViewBuilder
    func liquidGlassBar() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular)
        } else {
            self.background(.ultraThinMaterial)
        }
    }
}
