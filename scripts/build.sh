#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/ModuleCache"

CONFIGURATION="${1:-release}"
BUILD_ARCH="${2:-universal}"
if [[ "$CONFIGURATION" != release && "$CONFIGURATION" != debug ]]; then
    echo 'Usage: bash scripts/build.sh [release|debug] [universal|arm64|x86_64]' >&2
    exit 1
fi
case "$BUILD_ARCH" in
    universal) ARCHITECTURES=(arm64 x86_64) ;;
    arm64|x86_64) ARCHITECTURES=("$BUILD_ARCH") ;;
    *) echo 'Unsupported architecture' >&2; exit 1 ;;
esac
BINARIES=()
for architecture in "${ARCHITECTURES[@]}"; do
    swift build --disable-sandbox --scratch-path .build --cache-path .swiftpm/cache -c "$CONFIGURATION" --arch "$architecture" --product LiuBai
    BINARIES+=("$PROJECT_DIR/.build/$architecture-apple-macosx/$CONFIGURATION/LiuBai")
done

if [[ "$CONFIGURATION" == release ]]; then
    DEFAULT_OUTPUT_DIR="$PROJECT_DIR/dist/release"
else
    DEFAULT_OUTPUT_DIR="$PROJECT_DIR/dist"
fi
OUTPUT_DIR="${LIUBAI_OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"
DESTINATION_APP="$OUTPUT_DIR/留白.app"
APP_PATH="$OUTPUT_DIR/.LiuBai-staging-$$.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
if [[ "$BUILD_ARCH" == universal ]]; then
    lipo -create "${BINARIES[@]}" -output "$APP_PATH/Contents/MacOS/LiuBai"
else
    cp "${BINARIES[0]}" "$APP_PATH/Contents/MacOS/LiuBai"
fi
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
cp Resources/StarterTracks.json "$APP_PATH/Contents/Resources/StarterTracks.json"
if [[ "$CONFIGURATION" == debug ]]; then
    if [[ -n "${LIUBAI_BUNDLE_ID:-}" ]]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $LIUBAI_BUNDLE_ID" "$APP_PATH/Contents/Info.plist"
    fi
    /usr/libexec/PlistBuddy -c 'Add :LSEnvironment dict' "$APP_PATH/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :LSEnvironment:LIUBAI_DATA_DIR string ${LIUBAI_DATA_DIR:-$PROJECT_DIR/.local-data}" "$APP_PATH/Contents/Info.plist"
fi
cp -R Notices "$APP_PATH/Contents/Resources/"
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" scripts/MakeIcon.swift "$PROJECT_DIR/.build/AppIcon.iconset"
iconutil -c icns .build/AppIcon.iconset -o "$APP_PATH/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
# Preserve the prior bundle, including any executable a running App has mapped.
if [[ -d "$DESTINATION_APP" ]]; then
    mkdir -p "$OUTPUT_DIR/previous"
    mv "$DESTINATION_APP" "$OUTPUT_DIR/previous/留白-$(date +%Y%m%d-%H%M%S)-$$.app"
fi
mv "$APP_PATH" "$DESTINATION_APP"
if [[ "$CONFIGURATION" == release && "$OUTPUT_DIR" == "$PROJECT_DIR/dist/release" ]]; then
    LEGACY_APP="$PROJECT_DIR/dist/留白.app"
    if [[ ! -L "$LEGACY_APP" ]] || [[ "$(readlink "$LEGACY_APP")" != 'release/留白.app' ]]; then
        if [[ -d "$LEGACY_APP" || -L "$LEGACY_APP" ]]; then
            mkdir -p "$PROJECT_DIR/dist/previous"
            mv "$LEGACY_APP" "$PROJECT_DIR/dist/previous/留白-$(date +%Y%m%d-%H%M%S)-$$.app"
        fi
        ln -s 'release/留白.app' "$LEGACY_APP"
    fi
fi
ditto -c -k --sequesterRsrc --keepParent "$DESTINATION_APP" "$OUTPUT_DIR/.LiuBai-mac-$BUILD_ARCH-$$.zip"
mv "$OUTPUT_DIR/.LiuBai-mac-$BUILD_ARCH-$$.zip" "$OUTPUT_DIR/LiuBai-mac-$BUILD_ARCH.zip"
echo "Built: $DESTINATION_APP"
