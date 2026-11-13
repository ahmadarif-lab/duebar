#!/usr/bin/env bash
# Builds a universal release binary and wraps it into DueBar.app (LSUIElement,
# no Dock icon). Set DUEBAR_GOOGLE_CLIENT_ID (and _SECRET) to bake Google
# sign-in into the bundle.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "Building universal release binary…"
swift build -c release --arch arm64 --arch x86_64

APP_DIR="$ROOT_DIR/dist/DueBar.app"
CONTENTS="$APP_DIR/Contents"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
cp "$BIN_DIR/DueBar" "$CONTENTS/MacOS/DueBar"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS/Info.plist"

PLIST="$CONTENTS/Info.plist"
if [ -n "${DUEBAR_GOOGLE_CLIENT_ID:-}" ]; then
    /usr/libexec/PlistBuddy -c "Add :GoogleClientID string $DUEBAR_GOOGLE_CLIENT_ID" "$PLIST"
    [ -n "${DUEBAR_GOOGLE_CLIENT_SECRET:-}" ] && /usr/libexec/PlistBuddy -c "Add :GoogleClientSecret string $DUEBAR_GOOGLE_CLIENT_SECRET" "$PLIST"
    echo "Google sign-in baked in."
else
    echo "No DUEBAR_GOOGLE_CLIENT_ID: the build runs fully local (sign-in disabled)."
fi

# The mark shown in the dropdown header and Settings.
cp "$ROOT_DIR/Resources/BrandMark.png" "$CONTENTS/Resources/BrandMark.png"

ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.png"
if [ -f "$ICON_SOURCE" ]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
fi

echo "Ad-hoc signing…"
codesign --force --deep --sign - "$APP_DIR"
echo "Built: $APP_DIR"
