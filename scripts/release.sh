#!/usr/bin/env bash
# Builds, signs, notarizes and publishes an ordino release for a version tag,
# and updates the Sparkle appcast so installed apps update themselves.
#
#   scripts/release.sh v0.2.0             # used by .github/workflows/release.yml
#   DRY_RUN=1 scripts/release.sh v0.2.0   # build everything, publish nothing
#
# Environment:
#   UPDATES_REPO      public repo that hosts the appcast (GitHub Pages) and the
#                     update archives, e.g. ordino-app/ordino-updates. Unset = no feed.
#   DEPLOY_KEY        SSH deploy key with write access to UPDATES_REPO
#                     (default ~/.config/ordino/updates_deploy_key)
#   SPARKLE_KEY_FILE  EdDSA private key (default ~/.config/ordino/sparkle_ed25519.key)
#   NOTARY_PROFILE    notarytool keychain profile (default ordino-notary)
#
# One-time signing setup on the release Mac (keys never leave its keychain):
#   1. "Developer ID Application" certificate in the login keychain.
#   2. xcrun notarytool store-credentials ordino-notary --key AuthKey_XXXX.p8 --key-id XXXX --issuer <uuid>
set -euo pipefail

TAG="${1:?usage: release.sh vX.Y.Z}"
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.([1-9]|[12][0-9]|3[0-2]))?$ ]]; then
  echo "Bad tag '$TAG' (expected vX.Y.Z or vX.Y.Z-alpha|beta|rc.N with N 1-32)" >&2
  exit 1
fi
VERSION="${TAG#v}"
DRY_RUN="${DRY_RUN:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ordino-notary}"
KEY="${SPARKLE_KEY_FILE:-$HOME/.config/ordino/sparkle_ed25519.key}"
UPDATES_REPO="${UPDATES_REPO:-}"
DEPLOY_KEY="${DEPLOY_KEY:-$HOME/.config/ordino/updates_deploy_key}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SB="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
DIST="$ROOT/dist/$VERSION"
APP="$DIST/ordino.app"
ZIP="$DIST/ordino-$VERSION.zip"
CHANNEL=""
[[ "$VERSION" == *-* ]] && CHANNEL="beta"
cd "$ROOT"
mkdir -p "$DIST"

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }

[ -f "$KEY" ] || { echo "Sparkle private key not found at $KEY" >&2; exit 1; }
if [ -n "$UPDATES_REPO" ]; then
  FEED_URL="https://${UPDATES_REPO%%/*}.github.io/${UPDATES_REPO#*/}/appcast.xml"
else
  FEED_URL="${FEED_URL:-https://ordino-app.github.io/ordino-updates/appcast.xml}"
fi

log "Building ordino $VERSION (universal, release) -> feed $FEED_URL"
CONFIG=release UNIVERSAL=1 VERSION="$VERSION" FEED_URL="$FEED_URL" APP="$APP" \
  scripts/bundle-app.sh 2>&1 | grep -v 'replacing existing signature'
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
lipo -info "$APP/Contents/MacOS/ordino"

SIGNED_BY="$(codesign -dvv "$APP" 2>&1 | awk -F= '/^Authority=/{print $2; exit}')"
if [[ "$SIGNED_BY" == Developer\ ID\ Application* ]] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  log "Notarizing ($SIGNED_BY)"
  ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
  xcrun notarytool submit "$DIST/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  spctl -a -vvv -t exec "$APP"
else
  log "Not notarized (signed by: ${SIGNED_BY:-ad hoc}). Fine for testing; Gatekeeper will warn users."
fi

log "Packaging"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" > SHA256SUMS)
cat "$DIST/SHA256SUMS"

publish_feed() {
  local work prefix git_ssh
  work="$(mktemp -d)"
  log "Updating appcast in $UPDATES_REPO"
  [ -f "$DEPLOY_KEY" ] || { echo "Deploy key not found at $DEPLOY_KEY (docs/AUTOMATION.md)" >&2; exit 1; }
  # A deploy key scoped to the updates repo: works from the launchd runner,
  # which can't use gh's keychain login.
  git_ssh="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
  GIT_SSH_COMMAND="$git_ssh" git clone -q --depth 1 "git@github.com:$UPDATES_REPO.git" "$work/repo"
  if ! git -C "$work/repo" rev-parse -q --verify HEAD >/dev/null; then
    echo "$UPDATES_REPO has no commits yet. Create it with --add-readme (docs/AUTOMATION.md)." >&2
    exit 1
  fi

  # Archives live in the repo and are served by GitHub Pages next to the appcast.
  prefix="${FEED_URL%/appcast.xml}/archives/"
  mkdir -p "$work/archives" "$work/repo/archives"
  cp "$ZIP" "$work/archives/"
  [ -f "$work/repo/appcast.xml" ] && cp "$work/repo/appcast.xml" "$work/archives/appcast.xml"
  # generate_appcast keeps existing items and adds the archive in the folder.
  "$SB/generate_appcast" --ed-key-file "$KEY" --download-url-prefix "$prefix" \
    --maximum-deltas 0 ${CHANNEL:+--channel "$CHANNEL"} \
    --link "https://github.com/$UPDATES_REPO" "$work/archives"
  grep -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>" "$work/archives/appcast.xml" \
    || { echo "appcast is missing build $BUILD_NUMBER" >&2; exit 1; }

  if [ "$DRY_RUN" = "1" ]; then
    cp "$work/archives/appcast.xml" "$DIST/appcast.xml"
    log "Dry run: appcast written to dist/$VERSION/appcast.xml, not published"
    return
  fi
  # Archive and appcast land in one commit, so Pages never serves an item
  # whose archive is missing. Safe to re-run for the same tag.
  cp "$ZIP" "$work/repo/archives/"
  cp "$work/archives/appcast.xml" "$work/repo/appcast.xml"
  git -C "$work/repo" add appcast.xml "archives/$(basename "$ZIP")"
  if git -C "$work/repo" diff --cached --quiet; then
    log "Appcast already up to date"
    return
  fi
  git -C "$work/repo" -c user.name="ordino release" -c user.email="release@users.noreply.github.com" \
    commit -q -m "release: $TAG"
  GIT_SSH_COMMAND="$git_ssh" git -C "$work/repo" push -q
  log "Appcast published: $FEED_URL (GitHub Pages updates within a minute or two)"
}

if [ -n "$UPDATES_REPO" ]; then
  (publish_feed)
else
  log "UPDATES_REPO not set: skipping the appcast (no auto-update for this release)"
fi

if [ "$DRY_RUN" = "1" ]; then
  log "Dry run: artifacts in dist/$VERSION, nothing published"
  exit 0
fi

log "Publishing GitHub release $TAG"
PRERELEASE=()
[ -n "$CHANNEL" ] && PRERELEASE=(--prerelease)
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$ZIP" "$DIST/SHA256SUMS" --clobber
else
  gh release create "$TAG" "$ZIP" "$DIST/SHA256SUMS" \
    --verify-tag --title "ordino $VERSION" --generate-notes ${PRERELEASE[@]+"${PRERELEASE[@]}"}
fi

# Homebrew tap: bump the cask's version and sha256 (TAP_REPO, e.g. ordino-app/homebrew-tap,
# pushed with its own deploy key, because GitHub allows one repo per deploy key).
TAP_REPO="${TAP_REPO:-}"
TAP_KEY="${TAP_DEPLOY_KEY:-$HOME/.config/ordino/tap_deploy_key}"
if [ -n "$TAP_REPO" ] && [ -n "$UPDATES_REPO" ]; then
  log "Updating Homebrew cask in $TAP_REPO"
  [ -f "$TAP_KEY" ] || { echo "Tap deploy key not found at $TAP_KEY" >&2; exit 1; }
  tap_work="$(mktemp -d)"
  tap_ssh="ssh -i $TAP_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
  GIT_SSH_COMMAND="$tap_ssh" git clone -q --depth 1 "git@github.com:$TAP_REPO.git" "$tap_work"
  sha="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
  sed -i '' -E -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$tap_work/Casks/ordino.rb"
  if git -C "$tap_work" diff --quiet; then
    log "Cask already at $VERSION"
  else
    git -C "$tap_work" -c user.name="ordino release" -c user.email="212017430+xsugra@users.noreply.github.com" \
      commit -qam "ordino $VERSION"
    GIT_SSH_COMMAND="$tap_ssh" git -C "$tap_work" push -q
    log "Cask updated: brew upgrade --cask ordino-app/tap/ordino"
  fi
  rm -rf "$tap_work"
fi
