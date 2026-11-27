# Launch kit

Ready-to-post texts for getting ordino in front of people, for free. Expands the "Launch" line in [PLAN.md](PLAN.md).
Media: `docs/media/demo.gif` (README, awesome lists) and `docs/media/demo.mp4` (Reddit, X, LinkedIn; uploaded
videos play better there than GIFs). Regenerate both with `python3 scripts/demo-gif.py`.

Order: GitHub topics → r/macapps → Show HN (another weekday) → r/MacOS and r/opensource a few days later →
awesome lists and AlternativeTo any time. After every post, stay 2–3 hours to answer comments.

Links used below:
- Site: https://ordino-app.github.io/ordino/
- Repo: https://github.com/ordino-app/ordino
- Install: `brew install --cask ordino-app/tap/ordino`

---

## 1. GitHub topics (one command, do it first)

```bash
gh repo edit ordino-app/ordino --add-topic macos,window-manager,menubar-app,tiling,swift,productivity,open-source,macos-app
```

---

## 2. Reddit r/macapps

Post type: video (upload `demo.mp4`) with the text below, or an image post with the GIF.

**Title**

> I made ordino, a free and open-source menu bar app that arranges every window on your Mac with one shortcut

**Text**

> Hi r/macapps! I kept ending up with a pile of overlapping windows, and every tool I tried either moves one window at a time (Rectangle, Magnet) or tiles all the time (Amethyst, yabai, AeroSpace). I wanted something in between: tidy the whole screen *right now*, then get out of the way.
>
> So I built **ordino**. Press ⌥⌘A and it arranges every window on the display:
>
> - picks the layout from the window count and the screen shape: 2 windows side by side, 3 as master + stack, 4 as a grid; laptop, ultrawide and portrait displays each get their own
> - press ⌥⌘A again within 2 s for the next layout, ⌥⌘R rotates the windows through the slots, ⌥⌘Z undoes
> - the window you were working in gets the big slot (or pick an app that always does)
> - also has the usual single-window actions (halves, thirds, corners, maximize…) with Rectangle- or Spectacle-style shortcuts
> - respects minimum window sizes, gaps and margins are adjustable, updates itself
>
> It's **free, MIT-licensed, no account, no analytics**. macOS 14 Sonoma or later.
>
> Install: `brew install --cask ordino-app/tap/ordino`, or download the ZIP from the site.
>
> One honest note: it isn't notarized (that costs $99/year and this is a free hobby project), so on first launch macOS will block it once. System Settings › Privacy & Security › Open Anyway fixes that, then it needs Accessibility access to move windows. Steps: https://github.com/ordino-app/ordino/blob/main/docs/INSTALL.md
>
> Site: https://ordino-app.github.io/ordino/
> Source: https://github.com/ordino-app/ordino
>
> It's still in beta, so I'd love feedback: which layouts you'd want, what broke, what's annoying.

Check the subreddit's rules and flairs before posting (developers usually have to say they made the app; the text above does).

---

## 3. Hacker News — Show HN

Submit at https://news.ycombinator.com/submit. URL field: the **repo** link (HN prefers source over a landing page). Leave the text field empty and post the comment below right after submitting. Best time: Tuesday–Thursday, 15:00–17:00 CET.

**Title** (max 80 characters)

> Show HN: Ordino – arrange every window on your Mac with one keystroke

**First comment**

> Hi HN, I'm the author. ordino is a small macOS menu bar app (Swift, MIT) that arranges all windows on the current display when you press ⌥⌘A, and then does nothing until you press it again.
>
> The idea is the gap between two kinds of tools. Rectangle and Magnet place one window at a time; Amethyst, yabai and AeroSpace tile continuously and want you to live in their model. I wanted a one-shot "tidy everything" that I could use a few times an hour without changing how I work.
>
> Some details that took the most work:
>
> - The layout planner is a pure, deterministic Swift module (layout trees, slot assignment) with no AppKit in it, so it's unit-tested without touching real windows.
> - Layouts depend on window count and display aspect ratio, so an ultrawide gets columns where a laptop gets master + stack.
> - Many apps have minimum window sizes. The planner repairs layouts so a window that can't shrink doesn't overlap its neighbours.
> - Undo restores the previous frames; quick repeated presses collapse into one undo step.
> - Window discovery uses the Accessibility API plus CoreGraphics, with a tiny C shim for `_AXUIElementGetWindow` to match AX elements to window IDs.
>
> It isn't notarized (no paid Apple developer account; I'm keeping the project at zero cost), so first launch needs "Open Anyway". Install: `brew install --cask ordino-app/tap/ordino`.
>
> Happy to answer questions, and I'd like to hear which layouts you'd want.

---

## 4. Reddit r/MacOS (a few days after r/macapps)

**Title**

> Free, open-source utility: one shortcut to tidy every window on the screen (ordino)

**Text**

> I built a small menu bar app because I was tired of dragging windows around after every meeting. Press ⌥⌘A and ordino arranges all windows on the display: side by side for 2, master + stack for 3, a grid for 4, adjusted for laptop, ultrawide or portrait screens. Press again for the next layout, ⌥⌘Z to undo.
>
> Free, MIT, no account or tracking, macOS 14+. `brew install --cask ordino-app/tap/ordino` or https://ordino-app.github.io/ordino/
>
> Not notarized, so the first launch needs Privacy & Security › Open Anyway. Feedback welcome!

## 5. Reddit r/opensource

**Title**

> ordino: an MIT-licensed macOS app that arranges all your windows with one keystroke (Swift)

**Text**

> Sharing a project I've been building in the open: a macOS menu bar app that lays out every window on the display at once, then gets out of the way. The layout engine is a pure Swift package with unit tests, the window layer uses the Accessibility API, and releases are built by GitHub Actions and delivered through Sparkle and a Homebrew tap. Contributions, issues and layout ideas welcome.
>
> https://github.com/ordino-app/ordino

---

## 6. Awesome lists (pull requests)

Read each list's CONTRIBUTING file first: most want alphabetical order and an exact line format, and the
section names below may have changed. Suggested entries:

**jaywcjlove/awesome-mac**, window management section:

```markdown
* [ordino](https://github.com/ordino-app/ordino) - Arrange every window on the display with one keystroke; layouts adapt to window count and screen shape. [![Open-Source Software][OSS Icon]](https://github.com/ordino-app/ordino) ![Freeware][Freeware Icon]
```

**serhii-londar/open-source-mac-os-apps**, window management category. The README there is generated from
`applications.json`; add the entry to that file, matching the fields of its neighbours:

```json
{
  "short_description": "Arrange every window on the display with one keystroke.",
  "categories": ["window-management"],
  "repo_url": "https://github.com/ordino-app/ordino",
  "title": "ordino",
  "icon_url": "",
  "screenshots": ["https://raw.githubusercontent.com/ordino-app/ordino/main/docs/media/demo.gif"],
  "official_site": "https://ordino-app.github.io/ordino/",
  "languages": ["swift"]
}
```

**iCHAIT/awesome-macOS**, utilities / window management section:

```markdown
- [ordino](https://github.com/ordino-app/ordino) - Arrange every window on the display with one keystroke. [![Open-Source Software][OSS Icon]](https://github.com/ordino-app/ordino) ![Freeware][Freeware Icon]
```

PR title for all three: `Add ordino`. PR body:

> ordino is a free, MIT-licensed macOS menu bar app that arranges every window on the display with one keystroke (layouts adapt to window count and screen shape, with undo). Actively maintained, macOS 14+.

---

## 7. AlternativeTo

Add at https://alternativeto.net/software/add/ (free account).

- Name: ordino
- Short description: Free, open-source macOS menu bar app that arranges every window on the display with one keystroke.
- Platforms: Mac. License: Free, Open Source.
- Tags: window-manager, tiling-window-manager, menu-bar, productivity
- Alternative to: Rectangle, Magnet, Moom, Amethyst, Spectacle, BetterSnapTool, Divvy
- Image: `web/og-image.png` or a frame of the demo

---

## 8. LinkedIn / X (short)

> I released ordino, a free and open-source macOS app: press ⌥⌘A and every window on the screen is arranged into a layout that fits the number of windows and the display. Press again for the next layout, ⌥⌘Z to undo. Built in Swift, MIT licensed.
> https://ordino-app.github.io/ordino/

## 9. Slovensky / česky (Jablíčkář.cz, skupiny na Facebooku)

> Spravil som ordino, bezplatnú open-source appku do lišty pre Mac: stlačíš ⌥⌘A a všetky okná na obrazovke sa poukladajú. Pri dvoch oknách vedľa seba, pri troch jedno veľké a dve pod sebou, pri štyroch mriežka; prispôsobí sa aj ultrawide či vertikálnemu monitoru. Ďalší stisk prepne layout, ⌥⌘Z vráti späť. Bez účtu, bez sledovania, macOS 14+.
> Inštalácia: `brew install --cask ordino-app/tap/ordino` alebo https://ordino-app.github.io/ordino/
> Appka nie je notarizovaná, takže pri prvom spustení treba v Nastaveniach › Súkromie a bezpečnosť kliknúť „Aj tak otvoriť“. Budem rád za spätnú väzbu.

---

## Answers to questions you'll get

- **"How is this different from Rectangle?"** Rectangle moves the active window. ordino arranges all windows at once (and has Rectangle-style single-window actions too).
- **"Why not Amethyst/yabai/AeroSpace?"** Those tile continuously. ordino is one-shot: it arranges when you ask and leaves your windows alone otherwise.
- **"Why isn't it notarized?"** Notarization needs a $99/year Apple developer account; ordino is free and costs nothing to run. The source and the release builds are public on GitHub.
- **"Does it collect data?"** No analytics, no account. Update checks go to GitHub (Sparkle appcast).
- **Feature questions (multiple displays, Spaces, Stage Manager):** answer from what the released app does; don't promise what isn't shipped.

## Measuring

GitHub › Insights › Traffic shows referrers for 14 days: note them after each post. Stars and release downloads:

```bash
gh api repos/ordino-app/ordino/releases --jq '.[] | {tag: .tag_name, downloads: ([.assets[].download_count] | add)}'
```
