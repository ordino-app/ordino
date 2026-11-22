<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/logo-horizontal-dark.svg">
    <img src="brand/logo-horizontal.svg" alt="ordino" width="320">
  </picture>
</p>

# ordino

**Every window, in its place.** ordino is a free, open-source macOS menu bar app that arranges *all* windows on a display with one keystroke. With 4 windows you get a 2x2 grid, with 3 a master + stack, and so on. It adapts to the window count and the display shape (laptop, ultrawide, portrait), respects minimum window sizes, and can be undone.

> Status: **early prototype**. Layout engine, window layer and a first menu bar app work; signing, auto-update and settings come next.

## Install

```bash
brew install --cask ordino-app/tap/ordino
```

Or download the ZIP from the [website](https://ordino-app.github.io/ordino/). ordino is not notarized: on first launch click Done, then System Settings › Privacy & Security › Open Anyway, and allow it under Accessibility. It updates itself.

## Use the app

```bash
make run-app     # builds build/ordino.app and launches it
```

| Default shortcut | Action |
|---|---|
| ⌃⌥⌘A | Arrange the display. Press again within 2 s for the next layout |
| ⌃⌥⌘] / ⌃⌥⌘[ | Next / previous layout |
| ⌃⌥⌘R | Rotate windows through the slots |
| ⌃⌥⌘Z | Undo (a run of quick presses is one step) |

**Window actions** for the active window, like Rectangle: halves, corners, thirds, fourths, sixths, maximize, almost maximize, maximize height, larger, smaller, center, move to edge, restore, next/previous display. Pressing a half again cycles ½ → ⅔ → ⅓. They're in the menu, and get shortcuts from a preset (Rectangle-style ⌃⌥ arrows by default, Spectacle-style ⌥⌘ arrows, or none). Every shortcut can be changed in **Settings › Shortcuts**. If another window manager is running, ordino leaves window shortcuts unassigned so they don't collide.

**Settings** (⌘, from the menu): launch at login, menu bar icon, which display to arrange, confirmations, gaps and margins with a live preview, primary-window width, window limit, shortcuts, always-primary and ignored apps, updates, diagnostics.

**Primary window.** With Master + Stack (the default for 3 windows) the primary window gets the large slot. By default that's the window you were working in. In the menu you can pick another one (or click its slot in the preview), and tick "Always make <app> primary" to make an app win whenever it's on screen.

**Updates.** ordino checks for updates once a day through Sparkle; "Check for updates…" is in the menu, and "Beta" opts into prereleases.

Run `make signing` once: it creates a free self-signed certificate ("ordino Self-Signed") so the Accessibility permission survives rebuilds and updates. Without it, builds are signed ad hoc and macOS asks again every time.

Installing a release (first launch of an unnotarized app): [docs/INSTALL.md](docs/INSTALL.md).

## Why

Rectangle, Magnet and macOS' own tiling place windows one at a time. Amethyst, yabai and AeroSpace tile all the time. ordino is the missing middle: **tidy the whole screen right now, then get out of the way.**

## Repository layout

| Path | What |
|---|---|
| `Sources/Geometry` | Pure value types (`Rect`, `Size`, `Insets`), Quartz/AppKit coordinate flip |
| `Sources/LayoutEngine` | Pure, deterministic layout planner: layout trees, smart defaults, slot assignment, min-size repair |
| `Sources/AXPrivate` | C shim for `_AXUIElementGetWindow` |
| `Sources/WindowKit` | Accessibility + CoreGraphics: displays, window discovery, moving windows |
| `Sources/ArrangeCore` | Arrange / cycle / rotate / undo logic behind a backend protocol (tested with a fake) |
| `Sources/OrdinoApp` | The menu bar app: status item, panel, HUD, onboarding, global hotkeys |
| `Sources/ordino-probe` | Prototype CLI that runs the whole pipeline |
| `Tests/` | Swift Testing suites for Geometry and LayoutEngine |

## Development

```bash
make bootstrap   # install git hooks (formatting + Conventional Commits)
make test
make help        # everything else
```

CI, releases and the self-hosted runner are described in [docs/AUTOMATION.md](docs/AUTOMATION.md). The product plan is in [docs/PLAN.md](docs/PLAN.md).

## Build and test

Requires Xcode 26 or newer (Swift 6) and macOS 14+.

```bash
swift build
swift test
```

## Try the prototype

The app that runs the command (Terminal, iTerm, ...) needs **Accessibility** access:
System Settings > Privacy & Security > Accessibility.

```bash
swift run ordino-probe                      # dry run: list windows, print the plan
swift run ordino-probe --apply              # arrange the display under the mouse
swift run ordino-probe --layout columns --apply
swift run ordino-probe --rotate 1 --apply   # shift windows one slot
```

Layouts: `maximize`, `centered`, `columns`, `rows`, `masterStack`, `grid`, `bsp`.

## Defaults

| Windows | Laptop / desktop | Ultrawide | Portrait |
|---|---|---|---|
| 1 | Maximize | Centered (65 %) | Maximize |
| 2 | Columns | Columns | Rows |
| 3 | Master + stack | Columns | Rows |
| 4 | 2x2 grid | Columns (if >= 800 pt each) | Grid |
| 5-9 | Grid (cost-based) | Grid / columns | Grid |

The focused window becomes the master. Everyone else moves as little as possible, so arranging twice does nothing.

## Automation

ordino answers `ordino://` links, so Shortcuts.app ("Open URLs"), Raycast Quicklinks, Alfred or a script can drive it:

| Link | Does |
| --- | --- |
| `ordino://arrange` | Arrange the display |
| `ordino://arrange?recent=2` | Arrange only the 2 most recently used windows |
| `ordino://layout/columns` | Use a layout: `columns`, `rows`, `grid`, `masterStack`, `bsp`, `maximize`, `centered` |
| `ordino://next-layout`, `previous-layout`, `rotate`, `undo` | Same as the shortcuts |
| `ordino://window/leftHalf` | A window action on the focused window (`rightHalf`, `topLeft`, `firstThird`, `maximize`, …) |
| `ordino://workspace/Coding` | Apply a saved workspace by name |
| `ordino://custom/3%20Columns` | Apply a custom layout by name |

```bash
open "ordino://arrange?recent=2"
```

Raycast: *Create Quicklink*, paste a link, give it a hotkey or alias.

## Privacy

ordino uses only the Accessibility permission. It never records the screen, and nothing leaves your Mac.

## License

MIT, see [LICENSE](LICENSE).

Website: https://ordino-app.github.io/ordino/ (source in [web/](web/)). Brand assets and logo guidelines: [brand/](brand/README.md).
