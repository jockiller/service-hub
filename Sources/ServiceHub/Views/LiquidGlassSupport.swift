import SwiftUI

/// 苹果官方 Liquid Glass 统一系统适配层
/// 在拥有 macOS 26+/macOS 27 最新 SDK 编译器环境下激活苹果官方原生 .glass 与 .glassEffect API；
/// 在低版本 SDK 编译器（如 CI 环境）或旧系统上平滑回退，确保任何环境均可完美构建。
extension View {
    /// 应用苹果官方原生液态玻璃按钮（macOS 26+ 激活系统 .glass，旧版本平滑回退）
    @ViewBuilder
    func liquidGlassButton(tint: Color? = nil, isProminent: Bool = false) -> some View {
        #if compiler(>=6.3)
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
            fallbackBorderedButton(tint: tint, isProminent: isProminent)
        }
        #else
        fallbackBorderedButton(tint: tint, isProminent: isProminent)
        #endif
    }

    @ViewBuilder
    private func fallbackBorderedButton(tint: Color?, isProminent: Bool) -> some View {
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

    /// 应用苹果官方原生液态玻璃卡片容器（macOS 26+ 激活系统 .glassEffect）
    @ViewBuilder
    func liquidGlassCard(cornerRadius: CGFloat = 12) -> some View {
        #if compiler(>=6.3)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
        #else
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        #endif
    }

    /// 应用苹果官方原生液态玻璃吸顶/条状材质
    @ViewBuilder
    func liquidGlassBar() -> some View {
        #if compiler(>=6.3)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular)
        } else {
            self.background(.ultraThinMaterial)
        }
        #else
        self.background(.ultraThinMaterial)
        #endif
    }
}
