import SwiftUI
import AppKit

struct ServiceIconView: View {
    let service: Service
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let radius = max(7, size * 0.28)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        Group {
            if let path = service.appPath, FileManager.default.fileExists(atPath: path) {
                let nsImg = NSWorkspace.shared.icon(forFile: path)
                Image(nsImage: nsImg)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                ZStack {
                    shape.fill(ProTheme.innerContainerFill(colorScheme: colorScheme))
                    Image(systemName: service.icon)
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundColor(service.category.color)
                }
                .frame(width: size, height: size)
            }
        }
    }
}
