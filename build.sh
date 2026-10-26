#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${LITTLE_BRAIN_BUILD_DIR:-$(mktemp -d -t little-brain-build)}"
if [ -z "${LITTLE_BRAIN_BUILD_DIR:-}" ]; then trap 'rm -rf "$BUILD_DIR"' EXIT; fi
APP="${LITTLE_BRAIN_APP_PATH:-$ROOT/../little-brain.app}"
swift build --package-path "$ROOT" --scratch-path "$BUILD_DIR" -c release
BIN="$(swift build --package-path "$ROOT" --scratch-path "$BUILD_DIR" -c release --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/LittleBrain" "$APP/Contents/MacOS/LittleBrain"
cp "$ROOT/Assets/little-brain.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Assets/little-brain.png" "$APP/Contents/Resources/Logo.png"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LittleBrain</string>
<key>CFBundleIdentifier</key><string>com.local.littlebrain</string>
<key>CFBundleName</key><string>little-brain</string>
<key>CFBundleDisplayName</key><string>little-brain</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
