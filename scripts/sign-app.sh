#!/bin/bash
set -euo pipefail
APP="$1"
IDENTITY="$2"
SIGN_OPTIONS=(--force --sign "$IDENTITY")
if [ "$IDENTITY" = "-" ]; then
    SIGN_OPTIONS+=(--options 0)
else
    SIGN_OPTIONS+=(--options runtime --timestamp)
fi
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN_OPTIONS[@]}" "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
codesign "${SIGN_OPTIONS[@]}" --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
codesign "${SIGN_OPTIONS[@]}" "$FRAMEWORK/Versions/B/Autoupdate"
codesign "${SIGN_OPTIONS[@]}" "$FRAMEWORK/Versions/B/Updater.app"
codesign "${SIGN_OPTIONS[@]}" "$FRAMEWORK"
codesign "${SIGN_OPTIONS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
