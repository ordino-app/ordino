#!/usr/bin/env bash
# End-to-end check of the Sparkle update path, fully local:
#   builds ordino 0.1.0 (installed) and 0.1.1 (offered), signs 0.1.1 with the
#   EdDSA key, serves an appcast on localhost, launches 0.1.0 with "check now",
#   lets Sparkle download and install 0.1.1 on quit, then checks the version.
#
# Uses a separate bundle ID, so the real app's settings are not touched.
#   scripts/test-update.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
KEY="${SPARKLE_KEY_FILE:-$HOME/.config/ordino/sparkle_ed25519.key}"
SB="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
PORT="${PORT:-8765}"
TEST_ID="io.github.xsugra.ordino.updatetest"
WORK="$(mktemp -d)"
FEED="$WORK/feed"
mkdir -p "$FEED" "$WORK/installed" "$WORK/new"

cleanup() {
  [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null || true
  osascript -e "tell application id \"$TEST_ID\" to quit" >/dev/null 2>&1 || true
  defaults delete "$TEST_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

[ -f "$KEY" ] || { echo "Missing Sparkle private key at $KEY" >&2; exit 1; }

echo "==> Building 0.1.0 (installed) and 0.1.1 (update)"
for v in 0.1.0 0.1.1; do
  dest="$WORK/installed"; [ "$v" = 0.1.1 ] && dest="$WORK/new"
  VERSION="$v" BUNDLE_ID="$TEST_ID" FEED_URL="http://127.0.0.1:$PORT/appcast.xml" \
    APP="$dest/ordino.app" scripts/bundle-app.sh >/dev/null 2>&1
done

echo "==> Signing the update and writing the appcast"
ditto -c -k --sequesterRsrc --keepParent "$WORK/new/ordino.app" "$FEED/ordino-0.1.1.zip"
"$SB/generate_appcast" --ed-key-file "$KEY" --download-url-prefix "http://127.0.0.1:$PORT/" "$FEED" >/dev/null
grep -q 'sparkle:edSignature' "$FEED/appcast.xml" || { echo "appcast has no EdDSA signature" >&2; exit 1; }

echo "==> Serving $FEED on :$PORT"
python3 -I -m http.server "$PORT" --bind 127.0.0.1 --directory "$FEED" >"$WORK/server.log" 2>&1 &
SERVER_PID=$!
sleep 1

defaults write "$TEST_ID" SUAutomaticallyUpdate -bool YES
defaults write "$TEST_ID" SUHasLaunchedBefore -bool YES

echo "==> Launching 0.1.0 and checking for updates"
open -n "$WORK/installed/ordino.app" --args -ordinoCheckForUpdatesNow YES
for _ in $(seq 1 60); do
  grep -q 'GET /ordino-0.1.1.zip' "$WORK/server.log" && break
  sleep 1
done
grep -q 'GET /appcast.xml' "$WORK/server.log" || { echo "FAIL: appcast never requested"; cat "$WORK/server.log"; exit 1; }
grep -q 'GET /ordino-0.1.1.zip' "$WORK/server.log" || { echo "FAIL: update never downloaded"; cat "$WORK/server.log"; exit 1; }
echo "    appcast fetched, update downloaded"

sleep 3   # let Sparkle verify and stage the update
echo "==> Quitting 0.1.0 (Sparkle installs the update on quit)"
osascript -e "tell application id \"$TEST_ID\" to quit" >/dev/null 2>&1 || true
INSTALLED=""
for _ in $(seq 1 30); do
  INSTALLED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$WORK/installed/ordino.app/Contents/Info.plist" 2>/dev/null || true)"
  [ "$INSTALLED" = "0.1.1" ] && break
  sleep 1
done

if [ "$INSTALLED" = "0.1.1" ]; then
  codesign --verify --deep --strict "$WORK/installed/ordino.app"
  echo "PASS: 0.1.0 updated itself to 0.1.1 (signature valid)"
else
  echo "FAIL: installed version is still '${INSTALLED:-unknown}'"
  log show --last 3m --style compact --predicate 'process CONTAINS "ordino" OR process CONTAINS "Autoupdate" OR process == "Updater"' 2>/dev/null | grep -iE "sparkle|update|error" | tail -20
  exit 1
fi
