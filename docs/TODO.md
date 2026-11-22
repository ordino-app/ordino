# ordino roadmap / TODO

Status: `[x]` done · `[~]` in progress · `[ ]` not started. Keep this file current when work starts or lands.

## Next (agreed 2026-11-22)

- [ ] **1. Saved workspaces.** Named sets like "Coding" = editor left, browser right, terminal bottom.
  One shortcut launches missing apps and puts each window in its slot.
  - Model: `Workspace { name, slots: [(bundleID, frame as fractions of the visible frame)] }`, stored in Settings (JSON in UserDefaults).
  - "Save current arrangement as workspace…" in the menu captures bundle IDs + frames of the display under the mouse.
  - Apply: `NSWorkspace.openApplication` for missing apps, wait for their first window (poll ≤5 s), then move with `WindowMover`.
  - Settings pane "Workspaces": list, rename, delete, a shortcut per workspace (dynamic `KeyboardShortcuts.Name`).
- [~] **2. Re-arrange when displays change.** After a monitor is connected or disconnected, put the windows back
  in the layout last used on each display. Status in "Progress log" below.
- [x] **3. Move window to another display** keeping its relative position: Next/Previous Display
  (⌃⌥⌘→ / ⌃⌥⌘←), `WindowActionEngine.frame(movingWindow:from:to:)`. Shipped in 0.2.
- [ ] **4. Per-app rules.** "Slack always bottom-right", "Terminal never arranged".
  - "Never arranged" already exists: Ignored apps (Settings › Apps). Turn that list into "Rules" and add
    `AppRule { bundleID, action: WindowAction }` (e.g. `.bottomRightQuarter`).
  - When arranging, ruled windows go to their action's frame and are left out of the layout; simplest first
    version arranges the remaining windows normally in the full area.
  - Later: apply the rule when the app opens a new window (AXObserver `kAXWindowCreatedNotification`).
- [ ] **5. Drag to the screen edge to snap** (like Windows / Rectangle).
  - `NSEvent.addGlobalMonitorForEvents([.leftMouseDragged, .leftMouseUp])`; while dragging, confirm the focused
    window is moving (AX position changes) and the cursor is within ~5 px of an edge or corner.
  - Show a translucent preview `NSPanel` (borderless, `ignoresMouseEvents`, level `.floating`) for the target:
    left/right half at the sides, maximize at the top, quarters at the corners. On mouse-up apply that `WindowAction`.
  - Settings toggle (off by default at first), respect Ignored apps, skip while ⌘ is held.

## Later

- [ ] 6. Gaps and margins: already in Settings › Layouts; add a live preview.
- [ ] 7. Custom layouts: user-drawn grids (e.g. 3 columns for ultrawide).
- [ ] 8. Arrange only selected windows (e.g. the two most recently used).
- [ ] 9. Automation: URL scheme `ordino://arrange?layout=…`, App Intents for Shortcuts.app, Raycast extension.
- [ ] 10. Stage Manager / Spaces awareness: per-Space layouts.
- [ ] 11. First-run walkthrough polish (Accessibility + the three basic shortcuts).

## Project / ops follow-ups

- [ ] Ask Sociálna poisťovňa and Finančná správa in writing about Buy Me a Coffee donations (question text in the
      owner's local NAVOD-open-source.md). Don't withdraw payouts before the answer.
- [ ] Back up `~/.config/ordino` (Sparkle key, signing keychain, both deploy keys) to an encrypted image.
- [ ] Homebrew: the first automatic cask bump runs on the next release; check ordino-app/homebrew-tap afterwards.
- [ ] Old bridges: xsugra/ordino-updates (static appcast), xsugra/ordino and xsugra/ordino-web (redirects).
      Keep 6–12 months, then archive. xsugra/ordino-private keeps the old private history.
- [ ] Optional: ask GitHub Support to purge cached commits with the old email in closed PRs of
      xsugra/ordino-private and xsugra/gitlab-code-reviews.

## Progress log

- 2026-11-22: roadmap written; item 3 confirmed already shipped. Item 2 started on branch `feat/multi-display-rules`.
