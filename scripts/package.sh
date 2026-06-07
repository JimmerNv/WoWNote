#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$DIST_DIR/WowNote"
ZIP_FILE="$DIST_DIR/WowNote.zip"

rm -rf "$BUILD_DIR" "$ZIP_FILE"
mkdir -p "$BUILD_DIR"

cp "$ROOT_DIR/WowNote.toc" "$BUILD_DIR/WowNote.toc"

# Copy all addon Lua modules.
cp "$ROOT_DIR"/*.lua "$BUILD_DIR/"

# Optional project files inside the ZIP.
[ -f "$ROOT_DIR/README.md" ] && cp "$ROOT_DIR/README.md" "$BUILD_DIR/README.md"
[ -f "$ROOT_DIR/CHANGELOG.md" ] && cp "$ROOT_DIR/CHANGELOG.md" "$BUILD_DIR/CHANGELOG.md"
[ -f "$ROOT_DIR/LICENSE.md" ] && cp "$ROOT_DIR/LICENSE.md" "$BUILD_DIR/LICENSE.md"

(
  cd "$DIST_DIR"
  zip -qr "WowNote.zip" "WowNote"
)

echo "Created $ZIP_FILE"
echo "ZIP contents:"
unzip -l "$ZIP_FILE"
