#!/usr/bin/env bash
# Build, sign, notarize, and staple the macOS release build.
#
# Requires:
#   - "Developer ID Application" identity in the login keychain
#   - notarytool credentials stored under the keychain profile below
#     (see `xcrun notarytool store-credentials`)
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Typen"
IDENTITY="Developer ID Application: Yu Eric (R9Q763J4DV)"
KEYCHAIN_PROFILE="typen-notary"
ENTITLEMENTS="macos/Runner/Release.entitlements"
BUILD_DIR="build/macos/Build/Products/Release"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"

echo "==> flutter build macos --release"
flutter build macos --release

echo "==> codesign (Developer ID, hardened runtime)"
codesign --deep --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$APP_PATH"

echo "==> verify signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> zip for submission"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> submit for notarization"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait

echo "==> staple ticket"
xcrun stapler staple "$APP_PATH"

echo "==> final verification"
spctl -a -vvv --type execute "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "==> done: $APP_PATH"
