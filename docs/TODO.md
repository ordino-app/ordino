# ordino roadmap / TODO

Status: `[x]` done · `[~]` in progress · `[ ]` not started. Keep this file current when work starts or lands.

## Next (agreed 2026-11-22)

- [x] **1. Saved workspaces.** `Workspaces.swift`: menu › Workspaces › "Save Current Layout as Workspace…" captures the
  windows of the display under the mouse (bundle ID + frame as fractions of the visible frame). Applying opens apps
  that aren't running (in the background), waits up to ~6 s for their windows, and puts window i of each app into its
  i-th slot on the display under the mouse. Settings › Layouts › Workspaces: rename, per-workspace shortcut, apply,
  delete. Stored as JSON in UserDefaults (`workspaces`).
  - Ideas: remember a preferred display, include apps' window titles to match the right window, launch arguments.
- [x] **2. Re-arrange when displays change.** After a monitor is connected or disconnected (2 s debounce), every
  display ordino arranged before gets its last layout again (`AppDelegate.displaysChanged`). Toggle in Settings ›
  General › Displays (on by default). The layout memory is in-memory only: after relaunching ordino a display is
  re-arranged only once it has been arranged again. Not yet tested with a real external monitor.
- [x] **3. Move window to another display** keeping its relative position: Next/Previous Display
  (⌃⌥⌘→ / ⌃⌥⌘←), `WindowActionEngine.frame(movingWindow:from:to:)`. Shipped in 0.2.
- [x] **4. Per-app rules** (first version, see below). "Slack always bottom-right", "Terminal never arranged".
  - "Never arranged" already exists: Ignored apps (Settings › Apps). Turn that list into "Rules" and add
    `AppRule { bundleID, action: WindowAction }` (e.g. `.bottomRightQuarter`).
  - Done: `Settings.appRules` (bundle ID -> WindowAction), menu "Always Place <app>", Settings › Apps › Rules.
    Ruled apps are excluded from layouts and placed after each arrange (`AppDelegate.applyAppRules`).
  - Done: layouts use the largest free part of the display next to ruled windows (`FreeArea`, tested), unless
    less than 400x300 pt would be left.
  - Done: windows of a ruled app are placed when the app launches or comes to the front, once per window
    (`placeNewWindows`); afterwards the user may move them. A window opened without activating its app waits
    for the next arrange (an AXObserver for kAXWindowCreatedNotification would catch it immediately).
- [x] **5. Drag to the screen edge to snap** (like Windows / Rectangle). `DragSnap.swift` + `SnapZone` (tested):
  left/right edge = half, top = maximize, corners = quarters, bottom edge = nothing (Dock). Translucent preview
  panel while dragging, ⌘ disables it, ignored apps skipped, off while another window manager runs.
  Settings › General › Displays and dragging (on by default). 
  - Also: a Windows 11-style snap bar near the top (halves, thirds, 2/3+1/3, 1/3+2/3, quarters, full), each cell a
    target area; portrait displays get top/bottom halves and row thirds (thirds are rows on portrait everywhere).
    Only outer screen edges snap (edges shared between displays don't), unsnap restores size, defers to macOS tiling.
    Tested by hand by the owner on 3 monitors incl. portrait.

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

- 2026-11-22: roadmap written; item 3 confirmed already shipped. Items 2 and 4 (first version) landed on
  `feat/multi-display-rules`. Items 1 and 5 not started: 5 followed the same day (PR #7). Workspaces (1) and the rest of 4 followed on `feat/workspaces-rules`.
