#!/usr/bin/env bash
# Builds, signs (when a Developer ID is available), notarizes (when a notary
# profile exists) and publishes a GitHub release for a version tag.
#
#   scripts/release.sh v0.1.0             # used by .github/workflows/release.yml
#   DRY_RUN=1 scripts/release.sh v0.1.0   # build artifacts only, publish nothing
#
# One-time signing setup on the release Mac. The keys never leave its keychain:
#   1. Install your "Developer ID Application" certificate in the login keychain.
#   2. xcrun notarytool store-credentials ordino-notary \
#        --key AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-uuid>
#
# Today this ships the ordino-probe CLI. When the menu bar app lands, this
# script grows the xcodebuild archive -> DMG -> Sparkle appcast steps (docs/PLAN.md, section 6).
set -euo pipefail

TAG="${1:?usage: release.sh vX.Y.Z}"
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  echo "Bad tag '$TAG' (expected vMAJOR.MINOR.PATCH[-pre])" >&2
  exit 1
fi
VERSION="${TAG#v}"
DRY_RUN="${DRY_RUN:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ordino-notary}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist/$VERSION"
cd "$ROOT"
mkdir -p "$DIST"

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }

log "Building ordino $VERSION (universal arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64 --product ordino-probe
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
cp "$BIN_DIR/ordino-probe" "$DIST/ordino-probe"
lipo -info "$DIST/ordino-probe"

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
if [ -n "$IDENTITY" ]; then
  log "Signing with: $IDENTITY"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$DIST/ordino-probe"
  codesign --verify --strict --verbose=2 "$DIST/ordino-probe"
else
  log "No Developer ID certificate found: shipping unsigned (fine for the prototype)"
fi

ZIP="$DIST/ordino-probe-$VERSION-macos-universal.zip"
ditto -c -k --keepParent "$DIST/ordino-probe" "$ZIP"

if [ -n "$IDENTITY" ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  log "Notarizing (profile $NOTARY_PROFILE)"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  # Plain command-line binaries can't be stapled; Gatekeeper checks online.
else
  log "Skipping notarization (no identity, or no '$NOTARY_PROFILE' keychain profile)"
fi

(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" > SHA256SUMS)
cat "$DIST/SHA256SUMS"

if [ "$DRY_RUN" = "1" ]; then
  log "Dry run: artifacts in dist/$VERSION, nothing published"
  exit 0
fi

PRERELEASE=()
if [[ "$VERSION" == *-* ]]; then PRERELEASE=(--prerelease); fi
log "Publishing GitHub release $TAG"
gh release create "$TAG" "$ZIP" "$DIST/SHA256SUMS" \
  --verify-tag --title "ordino $VERSION" --generate-notes ${PRERELEASE[@]+"${PRERELEASE[@]}"}
