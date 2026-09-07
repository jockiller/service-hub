import Foundation
import AppKit

let projectDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
let svgPath = "\(projectDir)/Resources/AppIcon.svg"
let icnsPath = "\(projectDir)/Resources/AppIcon.icns"
let iconsetDir = "/tmp/ServiceHub_AppIcon.iconset"

print("==> 正在读取 SVG 矢量图标: \(svgPath)")
guard let svgData = try? Data(contentsOf: URL(fileURLWithPath: svgPath)),
      let image = NSImage(data: svgData) else {
    print("[-] 读取 SVG 失败")
    exit(1)
}

let fm = FileManager.default
try? fm.removeItem(atPath: iconsetDir)
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for item in sizes {
    let targetSize = NSSize(width: item.size, height: item.size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: item.size,
        pixelsHigh: item.size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = targetSize

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(origin: .zero, size: targetSize), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    if let pngData = rep.representation(using: .png, properties: [:]) {
        let dest = "\(iconsetDir)/\(item.name)"
        try? pngData.write(to: URL(fileURLWithPath: dest))
    }
}

print("==> 正在调用 iconutil 生成 macOS 原生 .icns 文件...")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
try? process.run()
process.waitUntilExit()

try? fm.removeItem(atPath: iconsetDir)

if fm.fileExists(atPath: icnsPath) {
    print("[✓] 原生应用图标生成成功: \(icnsPath)")
} else {
    print("[-] 生成 icns 失败")
    exit(1)
}
