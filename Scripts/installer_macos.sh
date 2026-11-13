#!/usr/bin/env bash
# Builds dist/DueBar.pkg, a standard installer that puts DueBar.app in /Applications.
# Run Scripts/build_app.sh first (package_release.sh does both).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
APP="dist/DueBar.app"
[ -d "$APP" ] || { echo "Run Scripts/build_app.sh first" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
ID=dev.ahmadarif.duebar
OUT="dist/DueBar.pkg"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root" "$WORK/scripts"
ditto "$APP" "$WORK/root/DueBar.app"

# The app belongs to the person who installed it, so it can be replaced later without a password.
cat > "$WORK/scripts/postinstall" <<'SCRIPT'
#!/bin/sh
OWNER=$(stat -f%Su /dev/console)
if [ -n "$OWNER" ] && [ "$OWNER" != root ]; then
    chown -R "$OWNER":admin "$2/DueBar.app" 2>/dev/null || true
fi
exit 0
SCRIPT
chmod +x "$WORK/scripts/postinstall"

# Replace an installed copy in place instead of relocating to wherever one is found.
pkgbuild --analyze --root "$WORK/root" "$WORK/components.plist" >/dev/null
PLIST=/usr/libexec/PlistBuddy
"$PLIST" -c "Set :0:BundleIsRelocatable false" "$WORK/components.plist" 2>/dev/null \
    || "$PLIST" -c "Add :0:BundleIsRelocatable bool false" "$WORK/components.plist"
"$PLIST" -c "Set :0:BundleIsVersionChecked false" "$WORK/components.plist" 2>/dev/null \
    || "$PLIST" -c "Add :0:BundleIsVersionChecked bool false" "$WORK/components.plist"
pkgbuild --root "$WORK/root" --component-plist "$WORK/components.plist" --scripts "$WORK/scripts" \
    --identifier "$ID" --version "$VERSION" --install-location /Applications \
    "$WORK/DueBar-app.pkg" >/dev/null 2>&1

cat > "$WORK/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>DueBar</title>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <allowed-os-versions><os-version min="14.0"/></allowed-os-versions>
    <domains enable_localSystem="true"/>
    <choices-outline><line choice="default"><line choice="$ID"/></line></choices-outline>
    <choice id="default"/>
    <choice id="$ID" visible="false"><pkg-ref id="$ID"/></choice>
    <pkg-ref id="$ID" version="$VERSION" onConclusion="none">DueBar-app.pkg</pkg-ref>
</installer-gui-script>
XML
productbuild --distribution "$WORK/distribution.xml" --package-path "$WORK" "$OUT" >/dev/null
printf 'Built %s\nsha256: %s\n' "$OUT" "$(shasum -a 256 "$OUT" | awk '{print $1}')"
