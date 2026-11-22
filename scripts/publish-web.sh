#!/usr/bin/env bash
# Publishes web/ (the promo site) to the public repo that GitHub Pages serves.
#
#   scripts/publish-web.sh               # push to xsugra/ordino-web
#   DRY_RUN=1 scripts/publish-web.sh     # show what would change, push nothing
#
# Credentials: a deploy key at ~/.config/ordino/web_deploy_key if present
# (works from the CI runner), otherwise gh's own login.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB_REPO="${WEB_REPO:-xsugra/ordino-web}"
DEPLOY_KEY="${WEB_DEPLOY_KEY:-$HOME/.config/ordino/web_deploy_key}"
WORK="$(mktemp -d)"

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }

[ -f "$ROOT/web/index.html" ] || { echo "web/index.html not found" >&2; exit 1; }

if [ -f "$DEPLOY_KEY" ]; then
  export GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
  REMOTE="git@github.com:$WEB_REPO.git"
  PUSH=(git -C "$WORK/site" push -q)
else
  REMOTE="https://github.com/$WEB_REPO.git"
  PUSH=(git -C "$WORK/site" -c credential.helper= -c 'credential.helper=!gh auth git-credential' push -q)
fi

log "Cloning $WEB_REPO"
git -c credential.helper= -c 'credential.helper=!gh auth git-credential' clone -q --depth 1 "$REMOTE" "$WORK/site"

log "Copying web/"
# Mirror web/ into the repo root, keeping the repo's own .git and README.
rsync -a --delete \
  --exclude '.git' --exclude 'README.md' \
  --exclude '.taste-skill' --exclude 'shots' --exclude '*.md' --exclude 'names.json' \
  --exclude '.DS_Store' --exclude 'media/*.png' \
  "$ROOT/web/" "$WORK/site/"
touch "$WORK/site/.nojekyll"

git -C "$WORK/site" add -A
if git -C "$WORK/site" diff --cached --quiet; then
  log "Site already up to date"
  exit 0
fi
git -C "$WORK/site" diff --cached --stat | tail -1
if [ "${DRY_RUN:-0}" = "1" ]; then
  log "Dry run: nothing pushed"
  exit 0
fi
git -C "$WORK/site" -c user.name="ordino web" -c user.email="web@users.noreply.github.com" \
  commit -q -m "site: $(git -C "$ROOT" rev-parse --short HEAD)"
"${PUSH[@]}"
log "Published: https://${WEB_REPO%%/*}.github.io/${WEB_REPO#*/}/"
