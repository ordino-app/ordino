#!/usr/bin/env bash
# Applies ordino's repository settings: merge policy, Actions hardening,
# rulesets for main and release tags, the release environment and security
# features. Safe to re-run (updates rulesets in place).
#
#   scripts/setup-github.sh            # uses the repo of the current checkout
#   REPO=owner/ordino scripts/setup-github.sh
set -euo pipefail

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
VISIBILITY="$(gh repo view "$REPO" --json visibility -q .visibility | tr '[:upper:]' '[:lower:]')"
FAILED=()
SKIPPED=()

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }
try() {
  local desc="$1"; shift
  if "$@" >/dev/null; then echo "   ok   $desc"; else echo "   FAIL $desc"; FAILED+=("$desc"); fi
}
# Like try, but on a private repo a failure means "not available on this plan"
# (rulesets, environments and fork approval need a public repo or GitHub Pro).
try_plan() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "   ok   $desc"
  elif [ "$VISIBILITY" != "public" ]; then echo "   skip $desc (needs a public repo or a paid plan)"; SKIPPED+=("$desc")
  else echo "   FAIL $desc"; FAILED+=("$desc"); fi
}

# Creates or updates a ruleset by name. $1 = name, stdin = JSON body.
ruleset() {
  local name="$1" body id
  body="$(cat)"
  id="$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$name\") | .id" 2>/dev/null || true)"
  if [ -n "$id" ]; then
    gh api -X PUT "repos/$REPO/rulesets/$id" --input - <<<"$body"
  else
    gh api -X POST "repos/$REPO/rulesets" --input - <<<"$body"
  fi
}

log "Configuring $REPO ($VISIBILITY)"

try "squash merges only, PR title becomes the commit, auto-delete branches" \
  gh api -X PATCH "repos/$REPO" \
    -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
    -F delete_branch_on_merge=true -F allow_auto_merge=true \
    -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY

try "workflow token is read-only by default" \
  gh api -X PUT "repos/$REPO/actions/permissions/workflow" \
    -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false

try_plan "fork PRs need your approval before any workflow runs" \
  gh api -X PUT "repos/$REPO/actions/permissions/fork-pr-contributor-approval" \
    -f approval_policy=all_external_contributors

try_plan "ruleset 'main': PRs only, required checks, no force-push or deletion" ruleset main <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [{ "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "pull_request" }],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [ { "context": "Build & test" }, { "context": "Conventional Commits" } ] } }
  ]
}
JSON

try_plan "ruleset 'release tags': only admins create, move or delete v* tags" ruleset "release tags" <<'JSON'
{
  "name": "release tags",
  "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "bypass_actors": [{ "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" }],
  "rules": [ { "type": "creation" }, { "type": "update" }, { "type": "deletion" } ]
}
JSON

try_plan "environment 'release' limited to v* tags" \
  gh api -X PUT "repos/$REPO/environments/release" --input - <<'JSON'
{ "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true } }
JSON
if ! gh api "repos/$REPO/environments/release/deployment-branch-policies" --jq '.branch_policies[].name' 2>/dev/null | grep -qx 'v*'; then
  try_plan "environment 'release' tag policy v*" \
    gh api -X POST "repos/$REPO/environments/release/deployment-branch-policies" -f name='v*' -f type=tag
fi

try "Dependabot alerts" gh api -X PUT "repos/$REPO/vulnerability-alerts"
try "Dependabot security updates" gh api -X PUT "repos/$REPO/automated-security-fixes"
try_plan "private vulnerability reporting" gh api -X PUT "repos/$REPO/private-vulnerability-reporting"

if [ "${#FAILED[@]}" -gt 0 ]; then
  log "Finished with ${#FAILED[@]} failure(s):"
  printf '   - %s\n' "${FAILED[@]}"
  exit 1
fi
if [ "${#SKIPPED[@]}" -gt 0 ]; then
  log "Skipped ${#SKIPPED[@]} setting(s) this plan doesn't offer for private repos. Re-run after going public."
fi
log "Done."
