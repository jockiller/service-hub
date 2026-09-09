#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"

VERSION="${1:-1.7.1}"
APP_NAME="ServiceHub"
BUILD_DIR="$DIR/build"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}-macOS.dmg"
ZIP_NAME="${APP_NAME}-${VERSION}-macOS.zip"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"

echo "==> 1. 编译并构建 Release App Bundle..."
"$DIR/scripts/build_app.sh" "$VERSION"

echo "==> 2. 执行 macOS Ad-Hoc 深度代码签名..."
# 对 Mach-O 二进制文件及 App Bundle 执行深度代码签名（确保在 Apple Silicon / ARM64 上具备完整哈希签名）
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> 3. 验证签名完整性..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "==> 4. 准备 DMG 制作环境..."
DMG_TEMP="$BUILD_DIR/dmg_root"
rm -rf "$DMG_TEMP" "$DMG_PATH" "$ZIP_PATH"
mkdir -p "$DMG_TEMP"

# 拷贝已签名的 App
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# 创建 Applications 应用程序目录快捷替身
ln -s /Applications "$DMG_TEMP/Applications"

# 生成安装说明提示文件
cat << 'EOF' > "$DMG_TEMP/安装说明 (首次打开必看).txt"
==============================================================================
ServiceHub macOS 安装与使用说明
==============================================================================

【安装方法】
将左侧的 ServiceHub 图标直接拖拽至右侧的 Applications (应用程序) 文件夹中即可。

【首次打开提示“无法验证开发者”或“已损坏”解决方法】
因为本项目为免费开源项目，未购买苹果每年 $99 的商业开发者证书：
如果双击打开时系统拦截提示，请打开 macOS 的「终端 (Terminal)」执行以下一键信任命令：

  xattr -cr /Applications/ServiceHub.app

执行完毕后即可像官方应用一样正常秒开！
或者：在访达中找到 ServiceHub，按住 Control 键并右键点击 -> 选择“打开” -> 在弹出窗口中点击“打开”。

==============================================================================
开源主页: https://github.com/jockiller/service-hub
==============================================================================
EOF

echo "==> 5. 使用 hdiutil 生成压缩 DMG 镜像..."
hdiutil create \
  -volname "ServiceHub" \
  -srcfolder "$DMG_TEMP" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$DMG_TEMP"

echo "==> 6. 制作便携 ZIP 压缩包..."
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> 7. 计算 SHA256 校验和..."
shasum -a 256 "$DMG_PATH" | tee "$BUILD_DIR/${DMG_NAME}.sha256"
shasum -a 256 "$ZIP_PATH" | tee "$BUILD_DIR/${ZIP_NAME}.sha256"

echo ""
echo "=============================================================================="
echo "[✓] 打包与签名全套完成！"
echo "    DMG 镜像: $DMG_PATH"
echo "    ZIP 压缩包: $ZIP_PATH"
echo "=============================================================================="
