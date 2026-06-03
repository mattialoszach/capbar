#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="CapBar"
APP_VERSION="0.2.0"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/docs/images/capbar-logo.png"
ICONSET_DIR="$DIST_DIR/$APP_NAME.iconset"
ZIP_PATH="$DIST_DIR/$APP_NAME-macOS.zip"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR" "$ICONSET_DIR" "$ZIP_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp ".build/release/CapBar" "$MACOS_DIR/CapBar"

RESOURCE_BUNDLE="$(find .build -path '*/release/CapBar_CapBar.bundle' -type d -print -quit)"
if [[ -n "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
fi

if [[ -f "$ICON_SOURCE" ]]; then
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/CapBar.icns"
  rm -rf "$ICONSET_DIR"
else
  echo "warning: $ICON_SOURCE not found; app bundle will not have a custom icon" >&2
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CapBar</string>
    <key>CFBundleDisplayName</key>
    <string>CapBar</string>
    <key>CFBundleIdentifier</key>
    <string>dev.capbar.CapBar</string>
    <key>CFBundleIconFile</key>
    <string>CapBar</string>
    <key>CFBundleName</key>
    <string>CapBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
fi

ditto -c -k --norsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "$APP_DIR"
echo "$ZIP_PATH"
