#!/usr/bin/env bash
# Build, sign, notarize, and staple the macOS release build.
#
# Requires:
#   - "Developer ID Application" identity in the login keychain
#   - an App Store Connect API key at $API_KEY_PATH below (see setup below)
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Typen"
IDENTITY="Developer ID Application: Yu Eric (R9Q763J4DV)"
# App Store Connect API key — doesn't expire/rotate the way an app-specific
# password can, unlike the keychain-profile (Apple ID + app-specific
# password) method this used before. Generate at
# https://appstoreconnect.apple.com/access/api → Keys, download the .p8 once
# (Apple only lets you download it at creation time), and place it here.
API_KEY_ID="M5ZDHNY66P"
API_KEY_ISSUER="cee87d4d-1341-488c-9e84-0862067891b9"
API_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_$API_KEY_ID.p8"
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
xcrun notarytool submit "$ZIP_PATH" \
  --key "$API_KEY_PATH" --key-id "$API_KEY_ID" --issuer "$API_KEY_ISSUER" \
  --wait

echo "==> staple ticket"
xcrun stapler staple "$APP_PATH"

echo "==> final verification"
spctl -a -vvv --type execute "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "==> done: $APP_PATH"
