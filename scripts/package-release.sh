#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$PROJECT_DIR/dist/release"
APP_PATH="$OUTPUT_DIR/留白.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
BASE_NAME="LiuBai-$VERSION-mac-universal"

codesign --verify --deep --strict "$APP_PATH"
lipo "$APP_PATH/Contents/MacOS/LiuBai" -verify_arch arm64 x86_64
LIUBAI_PACKAGE_STAGE=$(mktemp -d "$OUTPUT_DIR/.package-stage.XXXXXX")
trap 'rm -rf "$LIUBAI_PACKAGE_STAGE"' EXIT

mkdir -p "$LIUBAI_PACKAGE_STAGE/volume"
ditto "$APP_PATH" "$LIUBAI_PACKAGE_STAGE/volume/留白.app"
ln -s /Applications "$LIUBAI_PACKAGE_STAGE/volume/Applications"
cat > "$LIUBAI_PACKAGE_STAGE/volume/安装说明.txt" <<'TEXT'
留白 · LiuBai

支持 macOS 14 或更新版本，同时支持 Apple Silicon 和 Intel。

将「留白.app」拖入「Applications（应用程序）」即可安装。
更新前请先正常退出旧版留白，再替换应用。

本应用使用本地签名，尚未经过 Apple 公证。
登录仅用于读取 B 站收藏夹；天气背景可按需授权系统定位。
音乐不会下载到本地，统计和手记保存在这台 Mac。

佛系开发，全 vibe coding。有 token 就做，没 token 就鸽。
第三方许可和署名保存在应用包的 Contents/Resources/Notices 中。
TEXT

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$LIUBAI_PACKAGE_STAGE/$BASE_NAME.zip"
unzip -tq "$LIUBAI_PACKAGE_STAGE/$BASE_NAME.zip"
hdiutil create -volname "留白 $VERSION" -srcfolder "$LIUBAI_PACKAGE_STAGE/volume" -format UDZO -ov "$LIUBAI_PACKAGE_STAGE/$BASE_NAME.dmg"
hdiutil verify "$LIUBAI_PACKAGE_STAGE/$BASE_NAME.dmg"
mv "$LIUBAI_PACKAGE_STAGE/$BASE_NAME.zip" "$OUTPUT_DIR/$BASE_NAME.zip"
mv "$LIUBAI_PACKAGE_STAGE/$BASE_NAME.dmg" "$OUTPUT_DIR/$BASE_NAME.dmg"
cd "$OUTPUT_DIR"
shasum -a 256 "$BASE_NAME.dmg" "$BASE_NAME.zip" > "$BASE_NAME.sha256"
echo "Packaged: $OUTPUT_DIR/$BASE_NAME.dmg"
echo "Packaged: $OUTPUT_DIR/$BASE_NAME.zip"
