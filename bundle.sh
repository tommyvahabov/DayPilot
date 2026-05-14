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

# Copy app icon
cp "Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"

# Copy SPM module resource bundle (contains MenubarIcon.png, SidebarIcon.png, etc.)
# Without this, Bundle.module crashes at runtime on machines other than the build host.
BUILD_DIR=".build/arm64-apple-macosx/release"
MODULE_BUNDLE="${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$BUILD_DIR/$MODULE_BUNDLE" ]; then
    cp -R "$BUILD_DIR/$MODULE_BUNDLE" "$RESOURCES/$MODULE_BUNDLE"
else
    echo "⚠ Module bundle not found at $BUILD_DIR/$MODULE_BUNDLE — runtime crash likely"
fi

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
    <string>1.9.1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.9.1</string>
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
