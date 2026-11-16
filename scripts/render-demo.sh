#!/bin/bash
# Requires macOS 26+, Xcode command-line tools, and ffmpeg.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_TEMP="$(mktemp -d -t littlebrain-demo)"
DEMO_DIR="$DEMO_TEMP/demo.noindex"
mkdir -p "$DEMO_DIR"
trap 'rm -rf "$DEMO_TEMP"' EXIT
APP="$DEMO_DIR/Render.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Assets/little-brain.png" "$APP/Contents/Resources/Logo.png"
cp "$ROOT/Assets/Wordmark.pdf" "$APP/Contents/Resources/Wordmark.pdf"
VERSION="$(sed -n 's/.*CFBundleShortVersionString.*<string>\([^<]*\)<\/string>.*/\1/p' "$ROOT/build.sh")"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.local.littlebrain.demo</string>
<key>CFBundleExecutable</key><string>Render</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
cat "$ROOT/Sources/LittleBrain/Presentation.swift" "$ROOT/scripts/render-demo.swift" > "$DEMO_DIR/Scene.swift"
swiftc -parse-as-library -swift-version 5 \
  "$ROOT/Sources/LittleBrain/PulseState.swift" "$ROOT/Sources/LittleBrain/MenuBarController.swift" \
  "$DEMO_DIR/Scene.swift" -o "$APP/Contents/MacOS/Render"
"$APP/Contents/MacOS/Render" "$DEMO_DIR/frames"
ffmpeg -hide_banner -loglevel error -y -framerate 12 -i "$DEMO_DIR/frames/%04d.png" \
  -filter_complex '[0:v]split[a][b];[a]palettegen=stats_mode=diff:reserve_transparent=0[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle' \
  -loop 0 "$ROOT/docs/demo.gif"
ffmpeg -hide_banner -loglevel error -y -i "$DEMO_DIR/frames/0060.png" -frames:v 1 -update 1 "$ROOT/docs/demo-poster.png"
