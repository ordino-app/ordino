#!/usr/bin/env bash
# Registers this Mac as a self-hosted GitHub Actions runner for ordino and runs
# it as a launchd service (starts at login, survives reboots).
#
#   scripts/setup-runner.sh            # download, verify, register, start
#   scripts/setup-runner.sh --remove   # stop, unregister, uninstall the service
#
# Security model (see docs/AUTOMATION.md):
# - ci.yml only sends trusted runs here (pushes and PRs from this repo's own
#   branches); fork PRs always go to GitHub-hosted runners.
# - release.yml runs here only for version tags, which only admins may push.
# - Optional hardening: run the runner under a separate standard macOS user.
#
# Needs: gh (logged in as a repo admin), an Apple Silicon Mac, Xcode.
set -euo pipefail

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
RUNNER_DIR="${RUNNER_DIR:-$HOME/actions-runner/ordino}"
RUNNER_NAME="${RUNNER_NAME:-$(scutil --get LocalHostName)-ordino}"
LABELS="ordino"

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }

if [ "${1:-}" = "--remove" ]; then
  cd "$RUNNER_DIR"
  ./svc.sh stop || true
  ./svc.sh uninstall || true
  TOKEN="$(gh api -X POST "repos/$REPO/actions/runners/remove-token" --jq .token)"
  ./config.sh remove --token "$TOKEN"
  gh variable delete CI_RUNNER --repo "$REPO" 2>/dev/null || true
  log "Runner removed. CI falls back to GitHub-hosted runners. You may delete $RUNNER_DIR."
  exit 0
fi

[ "$(uname -m)" = "arm64" ] || { echo "Expected an Apple Silicon Mac." >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "Install Xcode first." >&2; exit 1; }

if [ -f "$RUNNER_DIR/.runner" ]; then
  log "Runner already configured in $RUNNER_DIR"
  (cd "$RUNNER_DIR" && ./svc.sh status) || true
  exit 0
fi

log "Looking up the latest actions/runner release"
TAG="$(gh api repos/actions/runner/releases/latest --jq .tag_name)"
VERSION="${TAG#v}"
# The release notes publish one SHA-256 per package between these markers.
SHA="$(gh api repos/actions/runner/releases/latest --jq .body \
  | sed -n 's/.*<!-- BEGIN SHA osx-arm64 -->\([0-9a-f]\{64\}\)<!-- END SHA osx-arm64 -->.*/\1/p' | head -n1)"
[ -n "$SHA" ] || { echo "Could not read the osx-arm64 checksum from the release notes; aborting." >&2; exit 1; }

PKG="actions-runner-osx-arm64-$VERSION.tar.gz"
TMP="$(mktemp -d)"
log "Downloading $PKG"
curl -fsSL -o "$TMP/$PKG" "https://github.com/actions/runner/releases/download/$TAG/$PKG"
echo "$SHA  $TMP/$PKG" | shasum -a 256 -c -

mkdir -p "$RUNNER_DIR"
tar -xzf "$TMP/$PKG" -C "$RUNNER_DIR"

log "Registering '$RUNNER_NAME' for $REPO (labels: self-hosted, macOS, ARM64, $LABELS)"
TOKEN="$(gh api -X POST "repos/$REPO/actions/runners/registration-token" --jq .token)"
(cd "$RUNNER_DIR" && ./config.sh --unattended --url "https://github.com/$REPO" --token "$TOKEN" \
  --name "$RUNNER_NAME" --labels "$LABELS" --work _work --replace)

log "Installing launchd service"
(cd "$RUNNER_DIR" && ./svc.sh install && ./svc.sh start)

log "Routing trusted CI runs to this Mac (repo variable CI_RUNNER=self-hosted)"
gh variable set CI_RUNNER --repo "$REPO" --body self-hosted

gh api "repos/$REPO/actions/runners" --jq '.runners[] | "   \(.name): \(.status) [\(.labels | map(.name) | join(", "))]"'
log "Done. Stop routing jobs here any time: gh variable delete CI_RUNNER"
