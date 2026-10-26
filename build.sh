#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${PULSE_BUILD_DIR:-$(mktemp -d -t codex-pulse-build)}"
if [ -z "${PULSE_BUILD_DIR:-}" ]; then trap 'rm -rf "$BUILD_DIR"' EXIT; fi
APP="${PULSE_APP_PATH:-$ROOT/../Codex Pulse.app}"
swift build --package-path "$ROOT" --scratch-path "$BUILD_DIR" -c release
BIN="$(swift build --package-path "$ROOT" --scratch-path "$BUILD_DIR" -c release --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_DIR/AppIcon.iconset"
cp "$BIN/CodexPulse" "$APP/Contents/MacOS/CodexPulse"
swift "$ROOT/Tools/MakeIcon.swift" "$BUILD_DIR/icon.png"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$BUILD_DIR/icon.png" --out "$BUILD_DIR/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$BUILD_DIR/icon.png" --out "$BUILD_DIR/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexPulse</string>
<key>CFBundleIdentifier</key><string>com.local.codexpulse</string>
<key>CFBundleName</key><string>Codex Pulse</string>
<key>CFBundleDisplayName</key><string>Codex Pulse</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
