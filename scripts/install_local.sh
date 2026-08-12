#!/usr/bin/env bash
# Install the already-built, notarized Release app into /Applications.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Typen"
SRC="build/macos/Build/Products/Release/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

if [ ! -d "$SRC" ]; then
  echo "no build at $SRC — run scripts/notarize.sh first" >&2
  exit 1
fi

if [ -d "$DEST" ]; then
  rm -rf "$DEST"
fi

ditto "$SRC" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "installed: $DEST"
codesign --verify --verbose=2 "$DEST"
spctl -a -vvv --type execute "$DEST"
