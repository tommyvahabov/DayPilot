#!/bin/bash
set -e

APP_NAME="DayPilot"
BUNDLE_DIR="$HOME/Applications/${APP_NAME}.app"
CONTENTS="$BUNDLE_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Clean previous bundle
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp ".build/arm64-apple-macosx/release/$APP_NAME" "$MACOS/$APP_NAME"

# Copy app icon and runtime images directly into Contents/Resources/
# Loaded via Bundle.main.url at runtime — no SPM resource bundle dependency.
cp "Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp "Resources/MenubarIcon.png" "$RESOURCES/MenubarIcon.png"
cp "Resources/MenubarIcon@2x.png" "$RESOURCES/MenubarIcon@2x.png"
cp "Resources/SidebarIcon.png" "$RESOURCES/SidebarIcon.png"

# Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DayPilot</string>
    <key>CFBundleDisplayName</key>
    <string>DayPilot</string>
    <key>CFBundleIdentifier</key>
    <string>com.pilotai.daypilot</string>
    <key>CFBundleVersion</key>
    <string>1.9.3</string>
    <key>CFBundleShortVersionString</key>
    <string>1.9.3</string>
    <key>CFBundleExecutable</key>
    <string>DayPilot</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

echo "✓ Bundle created at $BUNDLE_DIR"
