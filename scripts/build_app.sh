#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"

echo "==> 正在编译 ServiceHub (Release 优化模式)..."
swift build -c release

APP_NAME="ServiceHub"
BUNDLE_DIR="$DIR/build/${APP_NAME}.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "==> 拷贝应用图标..."
if [ ! -f "$DIR/Resources/AppIcon.icns" ]; then
  swift "$DIR/scripts/generate_icns.swift" "$DIR"
fi
cp -f "$DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

echo "==> 组装 macOS App Bundle..."
cp -f "$DIR/.build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ServiceHub</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.jockiller.servicehub</string>
    <key>CFBundleName</key>
    <string>ServiceHub</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "[✓] 编译打包完成！"
echo "    App 路径: $BUNDLE_DIR"
echo "    可直接双击运行，或执行: open \"$BUNDLE_DIR\""
