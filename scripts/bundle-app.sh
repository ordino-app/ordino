#!/usr/bin/env bash
# Builds ordino.app from the SwiftPM executable.
#
#   scripts/bundle-app.sh                 # debug, native arch -> build/ordino.app
#   CONFIG=release UNIVERSAL=1 scripts/bundle-app.sh
#
# Signing: "Developer ID Application" if present, else the free "ordino
# Self-Signed" identity from scripts/setup-signing.sh, else ad hoc. macOS ties
# the Accessibility permission to the signing identity, so releases must always
# use the same one.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIG="${CONFIG:-debug}"
BUNDLE_ID="${BUNDLE_ID:-io.github.xsugra.ordino}"
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.1.0}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || VERSION="0.1.0"   # e.g. a non-release tag in git describe
# Sparkle compares CFBundleVersion, so it must grow with every release:
#   MAJOR*1000000 + MINOR*10000 + PATCH*100 + suffix
#   suffix: alpha.N = N (1-32), beta.N = 32+N (33-64), rc.N = 64+N (65-96), final = 99
# so alpha < beta < rc < final within a version. 1.2.3-beta.4 -> 1020336, 1.2.3 -> 1020399.
build_number() {
  local v="$1" core suffix=99 label n major minor patch
  core="${v%%-*}"
  if [[ "$v" == *-* ]]; then
    if [[ ! "${v#*-}" =~ ^(alpha|beta|rc)\.([0-9]+)$ ]]; then
      echo "Unsupported prerelease '${v#*-}' (use alpha.N, beta.N or rc.N)" >&2
      return 1
    fi
    label="${BASH_REMATCH[1]}"
    n=$((10#${BASH_REMATCH[2]}))
    if ((n < 1 || n > 32)); then
      echo "Prerelease number must be 1-32, got $n" >&2
      return 1
    fi
    case "$label" in alpha) suffix=$n ;; beta) suffix=$((32 + n)) ;; rc) suffix=$((64 + n)) ;; esac
  fi
  IFS=. read -r major minor patch <<<"$core"
  echo $((${major:-0} * 1000000 + ${minor:-0} * 10000 + ${patch:-0} * 100 + suffix))
}
BUILD_NUMBER="${BUILD_NUMBER:-$(build_number "$VERSION")}"
# Where the app looks for updates. Must be a public HTTPS URL (see docs/AUTOMATION.md).
FEED_URL="${FEED_URL:-https://xsugra.github.io/ordino-updates/appcast.xml}"
PUBLIC_ED_KEY="${PUBLIC_ED_KEY:-$(cat "$ROOT/Config/SparklePublicKey.txt")}"
APP="${APP:-$ROOT/build/ordino.app}"

ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

echo "==> swift build ($CONFIG${UNIVERSAL:+, universal})"
swift build -c "$CONFIG" --product ordino ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"})"
BIN="$BIN_DIR/ordino"

echo "==> Assembling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/ordino"
FW="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$BIN_DIR/Sparkle.framework" "$FW"
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
  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$PUBLIC_ED_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
  <key>SUEnableSystemProfiling</key><false/>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Signing identity, in order of preference. Every release must use the same
# one: macOS ties the Accessibility permission to it.
#   1. Developer ID Application (paid; also lets the app be notarized)
#   2. "ordino Self-Signed" from scripts/setup-signing.sh (free, stable)
#   3. ad hoc (changes every build; dev only)
SIGNING_DIR="${ORDINO_SIGNING_DIR:-$HOME/.config/ordino}"
SIGNING_KEYCHAIN="$SIGNING_DIR/signing.keychain-db"
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
if [ -n "$IDENTITY" ]; then
  echo "==> Signing with $IDENTITY (hardened runtime)"
  SIGN=(--force --options runtime --timestamp --sign "$IDENTITY")
elif [ -f "$SIGNING_KEYCHAIN" ] && [ -f "$SIGNING_DIR/signing.keychain-password" ]; then
  security unlock-keychain -p "$(cat "$SIGNING_DIR/signing.keychain-password")" "$SIGNING_KEYCHAIN"
  # Self-signed certificates aren't "valid" to the trust system, so look the
  # identity up by name without -v and sign by its SHA-1.
  IDENTITY="$(security find-identity -p codesigning "$SIGNING_KEYCHAIN" | awk '/"ordino Self-Signed"/ {print $2; exit}')"
  [ -n "$IDENTITY" ] || { echo "No 'ordino Self-Signed' identity in $SIGNING_KEYCHAIN (run scripts/setup-signing.sh)" >&2; exit 1; }
  echo "==> Signing with ordino Self-Signed (stable identity)"
  # No hardened runtime: it only matters for notarization, and its library
  # validation needs a Team ID, which a self-signed certificate doesn't have.
  SIGN=(--force --sign "$IDENTITY" --keychain "$SIGNING_KEYCHAIN")
else
  echo "==> Signing ad hoc: Accessibility must be re-granted after each rebuild (run scripts/setup-signing.sh)"
  SIGN=(--force --sign -)
fi
# Inside-out, as Sparkle documents for non-sandboxed apps. Never --deep.
codesign "${SIGN[@]}" "$FW/Versions/B/XPCServices/Installer.xpc"
codesign "${SIGN[@]}" --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
codesign "${SIGN[@]}" "$FW/Versions/B/Autoupdate"
codesign "${SIGN[@]}" "$FW/Versions/B/Updater.app"
codesign "${SIGN[@]}" "$FW"
codesign "${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "==> Built $APP ($VERSION, build $BUILD_NUMBER)"
