#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/.dist"
APP_DIR="$DIST_DIR/AppVolumeGlass.app"
CONTENTS_DIR="$APP_DIR/Contents"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUNDLE_DIR="$RESOURCES_DIR/AppVolumeGlass_AppVolumeGlass.bundle"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$RESOURCES_DIR"

cp ".build/release/AppVolumeGlass" "$CONTENTS_DIR/MacOS/AppVolumeGlass"
cp -R ".build/arm64-apple-macosx/release/AppVolumeGlass_AppVolumeGlass.bundle" "$BUNDLE_DIR"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>AppVolumeGlass</string>
  <key>CFBundleIdentifier</key>
  <string>dev.codex.AppVolumeGlass</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>AppVolumeGlass</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.2</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAudioCaptureUsageDescription</key>
  <string>AppVolumeGlass needs system audio capture permission to lower the volume of individual apps and replay them at the selected level.</string>
</dict>
</plist>
PLIST

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

rm -f "$DIST_DIR/AppVolumeGlass.zip"
ditto -c -k --keepParent "$APP_DIR" "$DIST_DIR/AppVolumeGlass.zip"

echo "$APP_DIR"
echo "$DIST_DIR/AppVolumeGlass.zip"
