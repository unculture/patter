#!/bin/bash
# Builds build/Wisp.app. With --install, also copies it to /Applications and opens it.
set -euo pipefail
cd "$(dirname "$0")/.."

# Swift Package Manager needs the full Xcode toolchain, not only the Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if [[ ! -f Resources/AppIcon.icns ]]; then
    swift scripts/make-icon.swift Resources/AppIcon.icns
fi

swift build -c release --arch arm64

APP=build/Wisp.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Wisp "$APP/Contents/MacOS/Wisp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature. The designated requirement names only the bundle identifier, so that
# macOS can keep the microphone permission when you rebuild the app.
codesign --force --sign - \
    --identifier com.unculture.Wisp \
    --requirements '=designated => identifier "com.unculture.Wisp"' \
    "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    if pgrep -xq Wisp; then
        osascript -e 'tell application id "com.unculture.Wisp" to quit' || true
        sleep 1
        pkill -x Wisp || true
    fi
    rm -rf /Applications/Wisp.app
    cp -R "$APP" /Applications/Wisp.app
    open /Applications/Wisp.app
    echo "Installed /Applications/Wisp.app"
fi
