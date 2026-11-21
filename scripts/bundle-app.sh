#!/usr/bin/env bash
# Builds ordino.app from the SwiftPM executable.
#
#   scripts/bundle-app.sh                 # debug, native arch -> build/ordino.app
#   CONFIG=release UNIVERSAL=1 scripts/bundle-app.sh
#
# Signing: uses "Developer ID Application", else "Apple Development", else ad hoc.
# macOS ties the Accessibility permission to the signature. With ad-hoc signing
# every rebuild looks like a new app and the permission has to be granted again.
# A free "Apple Development" certificate (Xcode > Settings > Accounts > Manage
# Certificates > +) gives a stable identity for local development.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIG="${CONFIG:-debug}"
BUNDLE_ID="${BUNDLE_ID:-io.github.xsugra.ordino}"
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="$ROOT/build/ordino.app"

ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

echo "==> swift build ($CONFIG${UNIVERSAL:+, universal})"
swift build -c "$CONFIG" --product ordino ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c "$CONFIG" --show-bin-path ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"})/ordino"

echo "==> Assembling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ordino"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>ordino</string>
  <key>CFBundleDisplayName</key><string>ordino</string>
  <key>CFBundleExecutable</key><string>ordino</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License. The ordino authors.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')"
fi
if [ -n "$IDENTITY" ]; then
  echo "==> Signing with $IDENTITY (hardened runtime)"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  echo "==> Signing ad hoc (Accessibility must be re-granted after each rebuild)"
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "==> Built $APP ($VERSION, build $BUILD_NUMBER)"
