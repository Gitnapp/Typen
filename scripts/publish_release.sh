#!/usr/bin/env bash
# Create the GitHub release for the current pubspec version and upload the
# packaged, notarized zip built by package_release.sh.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$(grep '^version' pubspec.yaml | sed -E 's/version: ([0-9.]+).*/\1/')"
TAG="v$VERSION"
ZIP="build/dist/Typen-v$VERSION.zip"
TITLE="$1"
NOTES_FILE="$2"

gh release create "$TAG" "$ZIP" \
  --repo Gitnapp/Typen \
  --title "$TITLE" \
  --notes-file "$NOTES_FILE"
