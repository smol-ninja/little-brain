#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${LITTLE_BRAIN_BUILD_DIR:-$(mktemp -d -t little-brain-build)}"
if [ -z "${LITTLE_BRAIN_BUILD_DIR:-}" ]; then trap 'rm -rf "$BUILD_DIR"' EXIT; fi
APP="${LITTLE_BRAIN_APP_PATH:-$ROOT/../little-brain.app}"
swift build --package-path "$ROOT" --scratch-path "$BUILD_DIR" -c release
BIN="$(swift build --package-path "$ROOT" --scratch-path "$BUILD_DIR" -c release --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
SPARKLE="$BUILD_DIR/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$ROOT/THIRD_PARTY_NOTICES" "$APP/Contents/Resources/THIRD_PARTY_NOTICES"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
cp "$BIN/LittleBrain" "$APP/Contents/MacOS/LittleBrain"
cp "$ROOT/Assets/little-brain.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Assets/little-brain.png" "$APP/Contents/Resources/Logo.png"
cp "$ROOT/Assets/Wordmark.pdf" "$APP/Contents/Resources/Wordmark.pdf"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LittleBrain</string>
<key>CFBundleIdentifier</key><string>com.local.littlebrain</string>
<key>CFBundleName</key><string>littlebrain</string>
<key>CFBundleDisplayName</key><string>littlebrain</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.4.8</string>
<key>CFBundleVersion</key><string>15</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>SUFeedURL</key><string>https://smol-ninja.github.io/little-brain/appcast.xml</string>
<key>SUPublicEDKey</key><string>yGdwWhf6flJq6Idqx8gX3JQbJ5yiffplrlHZEuKAOJU=</string>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUAutomaticallyUpdate</key><false/>
<key>SUEnableSystemProfiling</key><false/>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SURequireSignedFeed</key><true/>
</dict></plist>
PLIST
if [ -n "${LITTLE_BRAIN_FIXTURE_BUILD:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set CFBundleVersion $LITTLE_BRAIN_FIXTURE_BUILD" "$APP/Contents/Info.plist"
fi
if [ -n "${LITTLE_BRAIN_FIXTURE_FEED:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set SUFeedURL $LITTLE_BRAIN_FIXTURE_FEED" "$APP/Contents/Info.plist"
fi
bash "$ROOT/scripts/sign-app.sh" "$APP" "${LITTLE_BRAIN_SIGN_IDENTITY:--}"
printf 'Built %s\n' "$APP"
