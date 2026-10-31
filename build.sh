#!/bin/zsh
# Builds AINewsBar.app and installs it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/AINewsBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/AINewsBar "$APP/Contents/MacOS/AINewsBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>AI News</string>
    <key>CFBundleIdentifier</key><string>com.local.AINewsBar</string>
    <key>CFBundleExecutable</key><string>AINewsBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

mkdir -p ~/Applications
rm -rf ~/Applications/AINewsBar.app
cp -R "$APP" ~/Applications/
echo "Installed: ~/Applications/AINewsBar.app"
