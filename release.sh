#!/bin/bash
set -euo pipefail

# Usage: ./release.sh <version> [release notes...]
# e.g.   ./release.sh 1.5.0 "Bug fixes and polish"

VERSION="${1:-}"
NOTES="${2:-DayPilot v$VERSION}"

if [[ -z "$VERSION" ]]; then
    echo "Usage: ./release.sh <version> [notes]"
    echo "Example: ./release.sh 1.5.0 \"What's new\""
    exit 1
fi

SIGN_IDENTITY="Developer ID Application: Rahmonberdi Vahabov (K5J4DDU5H4)"
TEAM_ID="K5J4DDU5H4"
NOTARY_PROFILE="daypilot-notary"

APP_NAME="DayPilot"
APP_PATH="$HOME/Applications/${APP_NAME}.app"
ZIP_PATH="$HOME/Applications/${APP_NAME}.zip"
ENTITLEMENTS="Resources/${APP_NAME}.entitlements"

echo "▶ Releasing v$VERSION"

# 1. Bump version in bundle.sh
echo "▶ Bumping bundle.sh to $VERSION"
sed -i.bak -E "s/<string>[0-9]+\.[0-9]+\.[0-9]+<\/string>/<string>$VERSION<\/string>/g" bundle.sh
rm -f bundle.sh.bak

# 2. Build release binary
echo "▶ Building release binary"
swift build -c release

# 3. Bundle the .app
echo "▶ Bundling app"
./bundle.sh

# 4. Sign with hardened runtime
echo "▶ Signing with $SIGN_IDENTITY"
codesign --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# 5. Zip for notarization
echo "▶ Zipping for notarization"
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

# 6. Submit to notarization service
echo "▶ Submitting to Apple notary (this can take 1-5 min)"
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# 7. Staple the ticket
echo "▶ Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

# 8. Re-zip with stapled app
echo "▶ Re-zipping stapled app"
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

# 9. Commit version bump and tag
echo "▶ Committing version bump"
git add bundle.sh
git commit -m "chore: bump version to $VERSION" || echo "  (nothing to commit)"
git push

echo "▶ Tagging v$VERSION"
git tag "v$VERSION"
git push origin "v$VERSION"

# 10. Create GitHub release
echo "▶ Creating GitHub release"
gh release create "v$VERSION" "$ZIP_PATH" \
    --title "DayPilot v$VERSION" \
    --notes "$NOTES"

echo "✓ Released v$VERSION"
echo "  https://github.com/tommyvahabov/DayPilot/releases/tag/v$VERSION"
