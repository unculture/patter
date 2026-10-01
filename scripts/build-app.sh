#!/bin/bash
# Builds build/Patter.app. With --install, also copies it to /Applications and opens it.
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

APP=build/Patter.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Patter "$APP/Contents/MacOS/Patter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature. The designated requirement names only the bundle identifier, so that
# macOS keeps the microphone and Accessibility permissions when you rebuild the app.
codesign --force --sign - \
    --identifier com.unculture.Patter \
    --requirements '=designated => identifier "com.unculture.Patter"' \
    "$APP"
echo "Built $APP"

# Quits an app: the bundle identifier, then the process name.
quit_app() {
    if pgrep -xq "$2"; then
        osascript -e "tell application id \"$1\" to quit" || true
        sleep 1
        pkill -x "$2" || true
    fi
}

if [[ "${1:-}" == "--install" ]]; then
    quit_app com.unculture.Patter Patter
    # Patter was called Wisp. Remove the old app, so that the two apps do not compete for the
    # shortcut. Patter copies the settings, the transcripts, and the API key of Wisp.
    if [[ -d /Applications/Wisp.app ]]; then
        quit_app com.unculture.Wisp Wisp
        /Applications/Wisp.app/Contents/MacOS/Wisp --unregister-login-item || true
        rm -rf /Applications/Wisp.app
        echo "Removed /Applications/Wisp.app"
    fi
    rm -rf /Applications/Patter.app
    cp -R "$APP" /Applications/Patter.app
    open /Applications/Patter.app
    echo "Installed /Applications/Patter.app"
fi
