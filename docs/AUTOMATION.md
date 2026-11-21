# Automation

How code gets from your editor to users, and what runs where.

## The flow

```
commit ──► pre-commit hook (swift-format)  +  commit-msg hook (Conventional Commits)
   │
push branch ──► open PR (title: feat(engine): ...)
   │              ├─ CI "Build & test"     lint, universal release build, tests
   │              └─ "Conventional Commits" PR title check
   │
squash-merge into main ──► CI runs again on main
   │
git tag v0.2.0 && git push --tags
   │
   └─► Release workflow (your Mac only): tests ─► build ─► sign ─► notarize ─► GitHub Release
```

Dependabot opens weekly PRs for GitHub Actions and Swift package updates.

## What runs where

| Workflow | Trigger | Runner |
|---|---|---|
| `ci.yml` | push to main, PRs from this repo's branches | **your Mac** when `CI_RUNNER=self-hosted`, otherwise GitHub-hosted |
| `ci.yml` | PRs from forks | GitHub-hosted by default |
| `pr-title.yml` | every PR | your Mac when `CI_RUNNER=self-hosted`, otherwise `ubuntu-latest` |
| `release.yml` | `v*.*.*` tag push, manual | **your Mac only** |

**While the repo is private** (now): GitHub-hosted minutes are billed against the free monthly allowance, and macOS minutes count 10x. With `CI_RUNNER=self-hosted` every job runs on your Mac and uses no minutes. Only collaborators you invite can push or fork, so the runner only ever sees code from people you trust.

**When the repo goes public:** GitHub-hosted standard runners become free (macOS included). A pull request from a fork can contain any code, **including edits to the workflow files themselves**, so the `runs-on` routing above is a convenience, not a security boundary. The boundary is the setting "require approval for all outside contributors" (applied by `make github-setup` on a public repo): nothing from a fork runs until you approve it. Before going public, also:

1. Re-run `make github-setup` (rulesets for `main` and `v*` tags, the `release` environment and fork approval become available).
2. Add `environment: release` back to `release.yml`.
3. Consider `gh variable delete CI_RUNNER` so day-to-day CI uses the free hosted runners, and keep the Mac for releases only.

**Signing keys stay on your Mac.** The release job runs on your machine, so the Developer ID certificate and the notarization key never have to be uploaded to GitHub.

## One-time setup

```bash
make bootstrap        # git hooks
make runner           # register this Mac as runner "ordino" (launchd service)
git push -u origin main
make github-setup     # repo settings, rulesets, release environment, security features
                      # (after the first push: the main ruleset would reject it)
```

Stop sending jobs to the Mac (CI falls back to GitHub-hosted runners):

```bash
gh variable delete CI_RUNNER
```

Remove the runner completely:

```bash
make runner-remove
```

## Releasing

```bash
git tag v0.2.0 && git push origin v0.2.0      # stable
git tag v0.3.0-beta.1 && git push origin v0.3.0-beta.1   # marked as prerelease
make release-dry RELEASE_TAG=v0.2.0                  # build the artifacts locally, publish nothing
```

Signing is picked up automatically once these exist on the release Mac:

1. A "Developer ID Application" certificate in the login keychain.
2. A notary profile: `xcrun notarytool store-credentials ordino-notary --key AuthKey_XXXX.p8 --key-id XXXX --issuer <uuid>`

Without them, releases are published unsigned, which is fine for the prototype stage.

## Auto-update (Sparkle)

ordino updates itself with [Sparkle 2](https://sparkle-project.org) (pinned to 2.10.1):

1. `release.yml` (on your Mac) builds a universal `ordino.app`, zips it and signs the zip with the **EdDSA key** (`~/.config/ordino/sparkle_ed25519.key`, also in your login keychain as account `ordino`).
2. `generate_appcast` adds the new version to `appcast.xml`. Tags like `v0.3.0-beta.1` go to the `beta` channel; only users who tick "Beta" in the menu get them.
3. The zip is uploaded to a release in the **updates repo** first, then `appcast.xml` is pushed there. GitHub Pages serves it at `https://<owner>.github.io/<repo>/appcast.xml`, the `SUFeedURL` baked into the app.
4. Installed apps check once a day. A menu bar app never pops an alert over your work: the icon fills in and the menu shows "Update available…".

**Why a separate public updates repo:** Sparkle downloads without logging in, and files in a private repo need a login. The updates repo holds only `appcast.xml` and the zipped app, never source code.

**Build numbers** (`CFBundleVersion`, what Sparkle compares) come from the version: `MAJOR*1000000 + MINOR*10000 + PATCH*100 + suffix`, where alpha.N = N, beta.N = 32+N, rc.N = 64+N and a final release = 99. So `0.2.0-alpha.1` (20001) < `0.2.0-beta.1` (20033) < `0.2.0-rc.1` (20065) < `0.2.0` (20099). Prerelease numbers go up to 32; the release script rejects anything else.

**Back up the private key** (password manager). If it is lost, installed apps can't verify new updates and users would have to download ordino again manually. The public half is in `Config/SparklePublicKey.txt`.

Setup once:

```bash
gh repo create <owner>/ordino-updates --public --add-readme   # needs a first commit
gh variable set UPDATES_REPO --body <owner>/ordino-updates
# then enable Pages: Settings > Pages > Deploy from branch "main", folder "/"
```

Test the whole update path locally (no network, separate bundle ID):

```bash
make test-update
```

## Daily commands

```bash
make help        # all targets
make test
make format      # fix formatting
make probe       # dry run on your displays
make arrange     # arrange the display under the mouse
```
