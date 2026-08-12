#!/usr/bin/env bash
# Zip the already-built, notarized, stapled .app for GitHub release upload.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Typen"
VERSION="$(grep '^version' pubspec.yaml | sed -E 's/version: ([0-9.]+).*/\1/')"
APP_PATH="build/macos/Build/Products/Release/$APP_NAME.app"
OUT_DIR="build/dist"
OUT_ZIP="$OUT_DIR/$APP_NAME-v$VERSION.zip"

mkdir -p "$OUT_DIR"
rm -f "$OUT_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$OUT_ZIP"

echo "$OUT_ZIP"
