# ordino

**Every window, in its place.** ordino is a free, open-source macOS menu bar app that arranges *all* windows on a display with one keystroke. With 4 windows you get a 2x2 grid, with 3 a master + stack, and so on. It adapts to the window count and the display shape (laptop, ultrawide, portrait), respects minimum window sizes, and can be undone.

> Status: **early prototype** (week 1). The layout engine is done and tested; the menu bar app is next.

## Why

Rectangle, Magnet and macOS' own tiling place windows one at a time. Amethyst, yabai and AeroSpace tile all the time. ordino is the missing middle: **tidy the whole screen right now, then get out of the way.**

## Repository layout

| Path | What |
|---|---|
| `Sources/Geometry` | Pure value types (`Rect`, `Size`, `Insets`), Quartz/AppKit coordinate flip |
| `Sources/LayoutEngine` | Pure, deterministic layout planner: layout trees, smart defaults, slot assignment, min-size repair |
| `Sources/AXPrivate` | C shim for `_AXUIElementGetWindow` |
| `Sources/WindowKit` | Accessibility + CoreGraphics: displays, window discovery, moving windows |
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

## Privacy

ordino uses only the Accessibility permission. It never records the screen, and nothing leaves your Mac.

## License

MIT, see [LICENSE](LICENSE).
