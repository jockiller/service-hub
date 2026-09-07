import SwiftUI
import AppKit

struct ServiceIconView: View {
    let service: Service
    let size: CGFloat

    var body: some View {
        Group {
            if let path = service.appPath, FileManager.default.fileExists(atPath: path) {
                let nsImg = NSWorkspace.shared.icon(forFile: path)
                Image(nsImage: nsImg)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: service.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.accentColor)
                    .frame(width: size * 0.72, height: size * 0.72)
                    .frame(width: size, height: size)
            }
        }
    }
}
