# ordino: produktový a technický plán

**macOS menu bar aplikácia, ktorá jedným klávesom usporiada všetky okná na monitore. Automatické aktualizácie cez GitHub Releases. Verejná promo stránka.**

Verzia plánu 1.0 · 21. 11. 2026 · pracovný názov **ordino**. Názov treba ešte overiť: ochrannú známku, doménu a Homebrew cask.

> Značka **[overiť]** označuje údaj, ktorý závisí od aktuálnej verzie nástroja alebo od politiky tretej strany. Pred implementáciou alebo publikovaním ho treba skontrolovať.

---

## 0. Zhrnutie na jednu stranu

| Oblasť | Rozhodnutie |
|---|---|
| **Problém** | Rectangle, Magnet a natívne tiling v macOS umiestňujú okná po jednom. Amethyst, yabai a AeroSpace dlaždicujú stále a pre bežného používateľa sú agresívne. Chýba jednorazové „uprac celú obrazovku teraz“, ktoré sa prispôsobí počtu okien a potom sa nepletie do cesty. |
| **Riešenie** | Jeden hotkey (⌃⌥⌘A) alebo jeden klik. Aplikácia nájde všetky okná na monitore a vyberie layout podľa ich počtu (1 → maximalizované, 2 → polovice, 3 → master + stack, 4 → 2×2, 6 → 3×2 …). Rešpektuje minimálne veľkosti okien, ponúka náhľad a **Undo**. Opakované stlačenie prepne na ďalší layout. |
| **Jazyk / UI** | **Swift 6 + SwiftUI**, s **AppKitom** tam, kde treba (status item, overlay panely). Natívne API, malá pamäťová stopa, Liquid Glass. |
| **Ovládanie okien** | Verejné **Accessibility API** (`AXUIElement`) a **žiadne vypínanie SIP**. Jediná súkromná funkcia je bežne používaný `_AXUIElementGetWindow`. |
| **Distribúcia** | Mimo Mac App Store. Podpis Developer ID, hardened runtime, **notarizácia**, DMG a Homebrew cask. |
| **Auto-update** | **Sparkle 2** s EdDSA podpisom. Binárky ležia na **GitHub Releases**, `appcast.xml` na vlastnej doméne. Celý proces spúšťa **GitHub Actions** po pushnutí tagu. |
| **Web** | **Astro + Tailwind CSS v4** na **Cloudflare**. Download tlačidlo vedie na najnovší release a changelog sa generuje z GitHub Releases. Analytika je Plausible, bez cookies. |
| **Podporované OS** | macOS 14 Sonoma a novšie. Primárne testovanie na macOS 26 Tahoe a na aktuálnom macOS 27 **[overiť]**. Universal binárka (Apple Silicon + Intel). |
| **Časový plán** | Verejná beta približne o **12 týždňov**, verzia 1.0 približne o **14 týždňov** (1–2 vývojári). |
| **Fixné náklady** | Približne **110–140 USD ročne** (Apple Developer 99 USD a doména). Hosting, CI pre verejný repozitár a analytika na free tieri sú zadarmo. |

---

## 1. Analýza trhu: z čoho sa inšpirujeme

| Produkt | Prístup | Auto-layout všetkých okien? | Čo prevezmeme | Licencia |
|---|---|---|---|---|
| **Rectangle** | AX | Čiastočne: akcie „Tile All“ / „Cascade All“ **[overiť]**, ale bez prispôsobenia počtu okien, bez master/stack, náhľadu a cyklovania | AX workaroundy (`AXEnhancedUserInterface`, presun medzi monitormi), Sparkle pipeline, Homebrew | MIT |
| **Rectangle Pro** | AX | Statické layouty aplikácií viazané na konkrétne aplikácie | Spúšťanie layoutu pri pripojení monitora | Platená |
| **Moom** | AX | Snapshot a obnovenie uložených pozícií | Uložené rozloženia a triggery pri zmene monitorov | Platená |
| **Amethyst** | AX | Áno, ale stále zapnuté dlaždicovanie (xmonad štýl) | Slovník layoutov (Tall, Wide, BSP, Columns), cyklovanie layoutov, „swap with main“ | MIT |
| **yabai** | AX a SkyLight, časť funkcií vyžaduje vypnutý SIP | Áno, BSP | Skriptovateľnosť. **Nepreberáme** nič, čo vyžaduje vypnutý SIP. | MIT |
| **AeroSpace** | AX a vlastné virtuálne workspaces | Áno, i3 strom | Deterministický model, konfiguračný súbor, CLI | MIT |
| **Loop** | AX, SwiftUI | Nie (radiálne menu pre jedno okno) | Moderný vizuál, náhľad pred aplikovaním | **GPL-3**: len inšpirácia, žiadny kód |
| **macOS 15+ natívne** | Systém | Len 2 alebo 4 okná (Arrange Left & Right, in Quarters) | Potvrdzuje dopyt. Netreba kolidovať s klávesmi Fn-⌃ + šípky. | Vstavané |
| **Raycast** | AX | Window Layouts pre vybrané aplikácie **[overiť rozsah]** | Paleta príkazov | Freemium |

**Naše odlíšenie (pozicionovanie):** *ľubovoľný počet okien, ľubovoľný monitor, náhľad, Undo, výnimky, jeden kláves a žiadne trvalé dlaždicovanie.* Porovnávaciu tabuľku na webe treba robiť férovo, bez tvrdení typu „nikto iný to nevie“.

---

## 2. Rozsah produktu (MVP → v1.x → v2)

### MVP / 1.0
- Menu bar aplikácia (`LSUIElement`), onboarding pre Accessibility a spúšťanie po prihlásení
- **Arrange All**: hotkey a klik, monitor pod kurzorom
- Smart layouty pre 1–9 okien so zohľadnením pomeru strán (ultrawide uprednostní stĺpce, portrait riadky)
- **Zaostrené okno ide do master slotu**, ostatné sa rozdelia s minimálnym presunom
- **Cyklovanie layoutov** opakovaným stlačením a **Rotate** (posun priradení okien)
- **Undo** posledného usporiadania
- Medzery (gaps) a okraje
- Výnimky pre aplikácie (Ignore)
- Constraint solver: okno s minimálnou šírkou dostane väčší slot a ostatné sa zmenšia
- HUD toast „Usporiadané 4 okná · 2×2 · ⌃⌥⌘Z späť“
- Sparkle auto-update (stable a beta kanál) a tlačidlo „Kopírovať diagnostiku“

### v1.x
- **Živý náhľad (overlay)** pred aplikovaním, pri hoveri v popoveri. Gesto „podrž a pusti“ príde až po prototype (pozri riziká).
- Viac monitorov: „Usporiadať všetky monitory“ a layouty pre každý monitor zvlášť
- Pravidlá pre aplikácie: Float, preferovaný master (napr. IDE je vždy master)
- Ďalšie layouty: BSP, centered master pre ultrawide, 60/40
- Shortcuts / App Intents a URL schéma `ordino://arrange?layout=grid`
- Uložené obľúbené layouty a ponuka pri pripojení monitora
- Lokalizácia (SK, EN, DE …)

### v2
- Voliteľný režim **„Keep Arranged“**, ktorý automaticky preusporiada okná pri otvorení alebo zatvorení okna (pre každý monitor zvlášť)
- Vizuálny editor vlastných zón (v štýle FancyZones)
- „Projekty“: jedným príkazom spustiť aplikácie a usporiadať ich
- CLI (`ordino arrange --layout grid --display 2`)

### Mimo rozsahu (treba to povedať aj vo FAQ na webe)
- Ovládanie iných Spaces a fullscreen Spaces (neexistuje na to verejné API)
- Čokoľvek, čo vyžaduje vypnutý SIP
- Mac App Store (rozhodnutie z dôvodu politiky App Review, nie technický zákaz)

---

## 3. Voľba technológií a zdôvodnenie

| Možnosť | Verdikt | Dôvod |
|---|---|---|
| **Swift 6 + SwiftUI/AppKit** | ✅ **Zvolené** | AX, CoreGraphics, ServiceManagement aj NSScreen sú C/ObjC API, ktoré Swift volá priamo. Pamäť ~15–30 MB, Liquid Glass je zadarmo. Rovnakú voľbu urobili Rectangle, Amethyst, AeroSpace aj Loop. |
| Rust core + Swift UI | ❌ | Dva toolchainy a FFI vrstva bez prínosu. Úzkym hrdlom je IPC latencia AX, nie CPU. |
| Tauri 2 | ❌ | WebView (40–80 MB), nenatívny vzhľad, žiadny Liquid Glass. Produkt je zo svojej podstaty len pre macOS. |
| Electron | ❌ | 150 MB+ pre aplikáciu, ktorá beží celý deň. Natívny addon by bolo treba aj tak. |

**Knižnice (pripnúť presné verzie):**

| Balík | Účel |
|---|---|
| `sparkle-project/Sparkle` 2.x **[overiť poslednú verziu]** | Auto-update |
| `sindresorhus/KeyboardShortcuts` | Globálne hotkeys cez Carbon `RegisterEventHotKey`, nepotrebuje Input Monitoring, má recorder UI |
| `sindresorhus/Defaults` | Typované UserDefaults |
| `pointfreeco/swift-snapshot-testing` | Snapshot testy layoutov (len v testoch) |
| Vlastné, ~30 riadkov | Wrapper nad `SMAppService.mainApp` pre spúšťanie po prihlásení |

**Toolchain:** Xcode 26.x (Swift 6.2), alebo novší, ak je GA **[overiť]**. Verziu treba pripnúť v CI. Swift 6 language mode so striktnou konkurenciou.

**Web:** Astro (statický výstup, nulový JS okrem dvoch islands), Tailwind v4, hosting na Cloudflare (zadarmo aj pri komerčnom použití, edge redirecty, hlavičky, proxy pre Plausible). Vercel Hobby zakazuje komerčné použitie a GitHub Pages nevie nastaviť vlastné hlavičky ani redirecty.

---

## 4. Architektúra aplikácie

```
┌──────────────────────── ordino.app (@MainActor) ────────────────────────┐
│ StatusItem + Popover   Settings (SwiftUI)   Onboarding   Overlay / HUD   │
│        │                     │                  │              ▲         │
│  HotkeyModule ──▶  ArrangeCoordinator (actor, jedna sériová pipeline)    │
│                     snapshot → plan → assign → apply → verify → undo     │
│          ┌──────────────┬───────────────┬──────────────┐                 │
│     DisplayKit     LayoutEngine      WindowKit     PermissionsKit        │
│     NSScreen,UUID  ČISTÝ (Foundation) AX + CGWindow  AX trust, TCC       │
│  SettingsStore (Defaults + JSON)   UpdateKit (Sparkle)   LoginItemKit    │
└──────────────────────────────────────────────────────────────────────────┘
```

### 4.1 Štruktúra repozitára

```
ordino/
├── App/                        # tenký Xcode target: @main, Info.plist, entitlements, assets
├── Packages/ordinoKit/        # lokálny SPM balík (swift-tools 6.0, macOS 14)
│   ├── Sources/
│   │   ├── Geometry/           # Rect, Insets: len Foundation
│   │   ├── LayoutEngine/       # stratégie, chooser, priradenie, constraint repair: ČISTÉ
│   │   ├── DisplayKit/         # NSScreen, CGDirectDisplayID, prevod súradníc
│   │   ├── WindowKit/          # AXUIElement, CGWindowList, observery, actor pre každú aplikáciu
│   │   ├── ArrangeCore/        # koordinátor, undo, politiky
│   │   ├── PermissionsKit/     # AX trust, polling, deep linky, detekcia „zapnuté, ale nedôveryhodné“
│   │   ├── SettingsStore/  HotkeyModule/  UpdateKit/  LoginItemKit/
│   │   ├── OverlayUI/          # NSPanel overlay a HUD
│   │   └── ordinoUI/          # SwiftUI views, GlassBackground modifier
│   └── Tests/                  # Swift Testing a snapshot testy
├── Tools/WindowHarness/        # testovacia aplikácia, ktorá otvorí N okien s danými min. veľkosťami (E2E)
├── scripts/release.sh          # lokálny záložný release (rovnaké kroky ako CI)
└── .github/workflows/          # ci.yml, release.yml
web/  (samostatný repozitár)    # Astro stránka a public/appcast.xml
```

**Pravidlá závislostí:** `Geometry` a `LayoutEngine` importujú iba Foundation, takže sú deterministické a testovateľné kdekoľvek. Okná, monitory a layouty spája len `ArrangeCore`.

### 4.2 Pipeline „Arrange“

1. **Zachytenie kontextu ešte pred otvorením UI.** Zaznamenať frontmost aplikáciu a jej zaostrené okno. Bez toho by sa po otvorení popoveru stala „zaostrenou“ naša aplikácia. Na popover použiť `NSStatusItem` + `NSPanel(.nonactivatingPanel)`.
2. **Snapshot.** Cieľový monitor je ten pod kurzorom. Okná na ňom sa zistia z `CGWindowListCopyWindowInfo` (z-order, on-screen, aktuálny Space) a spoja s AX elementmi cez `_AXUIElementGetWindow`. Filter: subrole `AXStandardWindow`, bez minimalizovaných, fullscreen, PiP a vlastných okien, bez okien menších ako prah (jedna konštanta v `LayoutEngine` testoch).
3. **Plán.** Čistá funkcia `LayoutEngine.plan(context) -> LayoutPlan`.
4. **Priradenie.** Zaostrené okno ide do master slotu. Ostatné sa rozdelia s minimálnou cenou (vzdialenosť stredov, pomer strán, nedostatok miesta pre min. veľkosť). Do 8 okien bitmask DP, nad 8 Hungarian. Shody sa rozhodujú deterministicky podľa WindowID, takže opakované stlačenie s rovnakými oknami nič nezmení.
5. **Aplikovanie.** Pre každé okno size → position → size. Paralelne medzi aplikáciami, sériovo v rámci jednej aplikácie. Pred zápisom dočasne vypnúť `AXEnhancedUserInterface` (Chromium/Electron), ak nebeží VoiceOver.
6. **Overenie a oprava.** Počkať 30–80 ms (asynchrónne aplikácie ako JetBrains alebo Electron), prečítať rámy späť a pri odmietnutí prepočítať s pevnou veľkosťou okna. Maximálne 2 iterácie.
7. **Undo.** Pôvodné rámy sa zapíšu do zásobníka až po začatí aplikovania.

**Súbeh:** koordinátor je sériový. Stlačenie počas prebiehajúceho usporiadania sa zahodí, prípadne sa uloží ako „ďalší layout“. Medzi fázami sa kontroluje `Task.isCancelled`. **Cieľová latencia:** < 150 ms pri 6 oknách, < 300 ms pri 12 oknách (M-series).

### 4.3 Layout engine: predvolená tabuľka

Jediný zdroj pravdy je tabuľka v testoch `LayoutEngine`. Dokumentácia a UI sa na ňu odkazujú.

| n | Landscape (1,3–2,0) | Ultrawide (> 2,0) | Portrait (< 1,0) |
|---|---|---|---|
| 1 | Maximalizovať | Na stred, 65 % šírky | Maximalizovať |
| 2 | 2 stĺpce 50/50 | 2 stĺpce | 2 riadky |
| 3 | Master 55 % + 2 v stacku | 3 stĺpce | 3 riadky |
| 4 | Mriežka 2×2 | 4 stĺpce, ak má bunka aspoň 800 pt, inak 2×2 | 2×2 |
| 5 | Master + 4, alebo mriežka 3+2 (podľa ceny) | Mriežka 3+2 | 2×3 |
| 6 | 3×2 | 3×2 | 2×3 |
| 7–9 | Mriežka podľa cenovej funkcie (pomer strán buniek, prázdne bunky, min. šírka) | Mriežka | Mriežka |
| > 9 | Prvých 9 podľa z-order, ostatné nechať na mieste a ukázať upozornenie | | |

**Stratégie:** Grid, Columns/Rows, Master+Stack (aj centered master), BSP (pri n > 6 prejde na grid), Single.
**Personalizácia:** cyklovanie si zapamätá voľbu pre dvojicu (UUID monitora, n). Netreba na to ML, stačí tabuľka.

### 4.4 Kľúčové ukážky kódu

```swift
public protocol LayoutStrategy: Sendable {
    static var id: LayoutID { get }
    func supports(count: Int, area: Rect) -> Bool
    /// Čistá funkcia: vráti presne `count` neprekrývajúcich sa slotov v `area`, oddelených `gap`.
    func slots(count: Int, in area: Rect, gap: Double, prefs: LayoutPreferences) -> [Slot]
}

public protocol WindowBackend: Sendable {          // reálny = AX/CG, fake = testy
    func snapshot(display: DisplaySnapshot) async throws -> [WindowInfo]
    func apply(_ plan: [WindowID: Rect]) async -> [WindowID: Result<Rect, AXFailure>]
}
```

```swift
// Kontrola AX oprávnenia, kompatibilná so Swift 6 (bez globálnej premennej kAXTrustedCheckOptionPrompt)
let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
let trusted = AXIsProcessTrustedWithOptions(opts)
```

`_AXUIElementGetWindow` deklarovať v C hlavičke alebo module mape, nie cez `@_silgen_name`.

### 4.5 Súradnice a monitory
- AX používa globálny priestor s počiatkom vľavo hore na primárnom monitore, `NSScreen` vľavo dole. Prevod je v **jednej** funkcii v `DisplayKit` a je pokrytý testami so syntetickými konfiguráciami (vertikálne usporiadané monitory, záporné súradnice).
- Plocha na layout je `NSScreen.visibleFrame` (menu bar, notch, Dock) mínus okraje.
- Identita monitora je `CGDisplayCreateUUIDFromDisplayID`. Pri rovnakých monitoroch bez sériového čísla sa ako záloha použije UUID + pozícia.

### 4.6 Známe problémové prípady (quirks tabuľka)
| Prípad | Riešenie |
|---|---|
| Electron/Chromium: pomalé alebo animované resize | Dočasne vypnúť `AXEnhancedUserInterface`, prípadne `AXManualAccessibility` |
| JetBrains/Java, Catalyst: asynchrónne rámy | Počkať a prečítať znova. Min. veľkosť potvrdiť až pri opakovanom odmietnutí. |
| Min. veľkosti (Xcode, System Settings) | Cache naučených min. veľkostí s kľúčom **bundle ID + subrole**, s expiráciou a možnosťou resetu |
| Okná s pevnou veľkosťou | Umiestniť na stred slotu |
| Natívne taby (Finder, Terminal, Safari) | Mapovanie len cez `_AXUIElementGetWindow` a len on-screen okno |
| Stage Manager | Zistiť, či je zapnutý, a usporiadať len aktívny stage, prípadne ukázať info. **Otestovať pred tým, ako to sľúbime na webe.** |
| Fullscreen okno na inom monitore | Nahlásiť v UI, nevynechať potichu |
| Okná dlaždicované natívne systémom (Sequoia+) | Overiť, či ich systém po našom presune znova neprichytí **[overiť]** |

---

## 5. UX dizajn (senior UI/UX)

### 5.1 Princípy
1. **Jedna akcia, nulová konfigurácia.** Nastavenia sú voliteľné.
2. **Najprv ukáž, potom pohni.** Náhľad pri hoveri a Undo, ktoré funguje vždy.
3. **Predvídateľnosť.** Zaostrené okno je master a ostatné sa takmer nepohnú. Pravidlo je vysvetlené v tooltipe aj v Settings.
4. **Slušný hosť.** Aplikácia nekradne focus a hlási, prečo sa niečo nedalo urobiť.
5. **Natívne.** SF Symbols, systémové fonty, HIG, Liquid Glass na macOS 26 a materiály na 14/15.

### 5.2 Popover (~340 pt)
```
┌──────────────────────────────────────┐
│  [Built-in Retina ▾]      4 okná     │
│ ┌──────────────────────────────────┐ │
│ │  ┌──────┬──────┐                 │ │
│ │  │Safari│ Xcode│   Mriežka 2×2   │ │  ← navrhnutý layout s ikonami aplikácií
│ │  ├──────┼──────┤   ⌃⌥⌘A          │ │
│ │  │Slack │ Notes│                 │ │
│ │  └──────┴──────┘                 │ │
│ └──────────────────────────────────┘ │
│   [        Usporiadať okná        ]  │  ← .glassProminent na macOS 26
│  Ďalšie layouty:  [▥] [▤] [⊞] [◧]    │  ← hover = náhľad na monitore
│  Medzery ●───── 8 pt     ↶ Späť      │
│ ─────────────────────────────────────│
│  Nastavenia…      Pozastaviť   Koniec│
└──────────────────────────────────────┘
```
- Náhľady sú vektorové obdĺžniky s ikonou aplikácie a názvom okna. Názvy sa čítajú cez AX, ktoré už máme. **Screen Recording nepotrebujeme nikdy.**
- Klávesnica: šípky, Return použije layout, ⌘Z vráti, 1–9 vyberie layout, Esc zavrie.

### 5.3 Hotkeys (predvolené, dajú sa zmeniť)
| Akcia | Kláves |
|---|---|
| Usporiadať monitor pod kurzorom; opakované stlačenie do 2 s = ďalší layout | ⌃⌥⌘A |
| Predchádzajúci / ďalší layout | ⌃⌥⌘← / → |
| Rotovať priradenie okien | ⌃⌥⌘R |
| Späť | ⌃⌥⌘Z |
| Usporiadať všetky monitory (v1.x) | ⌃⌥⌘⇧A |

Gesto „podrž pre náhľad“ je až vo v1.x. Počas držania modifikátorov by šípky a Tab prepadávali do aktívnej aplikácie, takže by bolo treba dočasné hotkeys alebo event tap. **Esc ako zrušenie nepoužívať:** s držanými modifikátormi je kombinácia ⌃⌥⌘Esc len jeden kláves od Force Quit (⌥⌘Esc).

### 5.4 Onboarding (4 kroky, ~560×460)
1. **Vitaj.** Animácia neporiadku, ktorý sa usporiada, a jedna veta.
2. **Prečo Accessibility.** Ľudsky napísané vysvetlenie: aplikácia čítá a presúva len okná, nenahráva obrazovku a nič neposiela preč z Macu.
3. **Udeliť prístup.** Tlačidlo otvorí System Settings (deep link `x-apple.systempreferences:…Privacy_Accessibility` **[overiť na 26/27]**). Aplikácia každú sekundu kontroluje `AXIsProcessTrusted()` a sama prejde ďalej. Súčasťou je **sprievodca opravou stavu „prepínač je zapnutý, ale nefunguje to“**: odstrániť a znova pridať aplikáciu, prípadne `tccutil reset Accessibility <bundle-id>`.
4. **Prispôsob si.** Hotkey, spúšťanie po prihlásení, automatické aktualizácie a tlačidlo **„Vyskúšaj teraz“**, ktoré usporiada skutočné okná. To je ten aha moment.

Navyše: ak aplikácia beží z DMG alebo z Downloads (App Translocation), ponúknuť **„Presunúť do Applications“**. Inak nebude fungovať Sparkle a TCC sa naviaže na zlú cestu.

### 5.5 Nastavenia (sidebar)
General · Layouty · Monitory · Vzhľad · Skratky · Výnimky · Aktualizácie (stable/beta) · O aplikácii (verzia, licencie, „Kopírovať diagnostiku“, nahlásiť chybu).
**Opätovné spustenie aplikácie vždy otvorí Nastavenia.** Ikona v menu bare môže byť skrytá za notchom alebo Bartenderom, preto je dizajn hotkey-first.

### 5.6 Prázdne a chybové stavy
| Situácia | UI |
|---|---|
| Chýba oprávnenie | Karta v popoveri a HUD pri hotkey, s tlačidlami [Otvoriť nastavenia] [Prečo?] |
| 0 okien | „Na tomto monitore nie sú okná. Okná vo fullscreen a na iných Spaces nie sú zahrnuté.“ |
| Všetky okná sú vylúčené | „4 okná ignorujú tvoje výnimky.“ [Skontrolovať] |
| Okno odmietlo resize | Toast „System Settings má pevnú veľkosť, umiestnené v slote.“ |
| Aplikácia neodpovedá | Po 250 ms ju preskočiť a pokračovať s ostatnými |
| Priveľa okien | Upozornenie a voľba „Usporiadať 9 posledných“ |

### 5.7 Prístupnosť a Liquid Glass
- VoiceOver popisy náhľadov („Mriežka 2 krát 2. Safari vľavo hore…“) a ohlásenie výsledku cez `announcementRequested`.
- Rešpektovať Reduce Motion (len crossfade), Reduce Transparency (plné pozadie) a Increase Contrast.
- Glass len na ovládacej vrstve (chrome popoveru, tlačidlá, HUD), nie na obsahu. Celé vetvenie podľa verzie OS je v jednom modifieri `GlassBackground`: `if #available(macOS 26, *) { .glassEffect(...) } else { .ultraThinMaterial }` **[overiť API v aktuálnom SDK]**.
- Ikona aplikácie z Icon Composeru (vrstvy pre režimy Default, Dark, Clear a Tinted) a klasický `.icns` pre 14/15.
- Lokalizácia cez String Catalogs. Layouty musia zniesť o 30 % dlhší text.

### 5.8 Brand
**ordino** (kamienok mozaiky): prémiový a pokojný. Teplá off-white a grafitová s jedným akcentom (terakota `#D9653B`). Ikona sú tri nerovnaké dlaždice (master + stack). Tón: presný a tichý, napr. *„Every window, in its place.“* Alternatívy: *Settle*, *Huddle*.

---

## 6. Distribúcia a automatické aktualizácie z GitHubu

### 6.1 Princíp
```
git tag v1.3.0 && git push --tags
        │
        ▼
GitHub Actions (macOS runner)
  build (Universal) → podpis Developer ID + hardened runtime
  → notarizácia .app → staple → DMG → podpis + notarizácia + staple
  → ZIP pre Sparkle → generate_appcast (EdDSA + delty)
  → GitHub Release (DMG, ZIP, delty, release notes)
  → commit appcast.xml do web repozitára → Cloudflare deploy
  → bump Homebrew tapu (len stable)
        │
        ▼
Aplikácie používateľov (Sparkle raz denne): stiahne → overí EdDSA + Apple podpis → nainštaluje
```

### 6.2 Kľúčové rozhodnutia
| Téma | Rozhodnutie |
|---|---|
| **Feed URL** | `https://ordino.app/appcast.xml` **na vlastnej doméne**, na rovnakom hostingu ako web (Cloudflare). Nie `releases/latest/download/…`, lebo `latest` ignoruje prereleases, čím by sa pokazil beta kanál, a URL by ostala navždy viazaná na GitHub. |
| **Binárky** | GitHub Releases: `ordino-1.3.0.dmg`, `ordino-1.3.0.zip` a `.delta` súbory. Stabilný alias pre web je `/download` (edge redirect na verziovaný DMG). |
| **Číslo buildu** | `CFBundleVersion` musí striktne rásť. Použiť `github.run_number` alebo kódovanie `MMmmpp` + beta počítadlo. **Nie** `git rev-list --count`: beta a stable na rovnakom commite by dostali rovnaké číslo. CI musí overiť, že nové číslo je vyššie než maximum v appcaste. |
| **Beta kanál** | Tag `v1.3.0-beta.1` vytvorí prerelease s `--channel beta`. Nastavenie „Dostávať betaverzie“ v aplikácii zapne `allowedChannels`. |
| **Podpisová identita** | Bundle ID a Team ID sú **navždy**. Ich zmena (napr. prechod z fyzickej osoby na firmu) zruší TCC oprávnenie všetkým používateľom a naruší Sparkle kontrolu kontinuity podpisu. **Právnu formu treba rozhodnúť pred 1.0.** |
| **Notarizácia** | `notarytool` s App Store Connect API kľúčom a `stapler`. Používateľ uvidí len štandardný dialóg „stiahnuté z internetu, otvoriť?“, nie blokovanie. |
| **Sandbox / MAS** | Bez sandboxu, entitlements prázdne. AX je TCC oprávnenie, nie entitlement. |
| **Menu bar aplikácia** | Sparkle „gentle reminders“, teda bodka na ikone namiesto vyskakovacieho okna. |
| **Rollback** | Revert commitu `appcast.xml` a oprava s vyšším build číslom. Pri vážnych chybách `sparkle:criticalUpdate`. Pri rizikových releasoch `phasedRolloutInterval`. |
| **Kill switch** | Remote config JSON na webe (feature flags), ktorý vie vypnúť problémovú funkciu bez nového buildu |

### 6.3 GitHub Actions (skrátená kostra `release.yml`)
```yaml
name: Release
on: { push: { tags: ['v*.*.*'] } }
permissions: { contents: write }
concurrency: { group: release, cancel-in-progress: false }
jobs:
  release:
    runs-on: macos-26            # [overiť] GA label, inak macos-15 + Xcode 26
    environment: release         # secrets + required reviewers
    steps:
      - uses: actions/checkout@<SHA>   # akcie pripnuté na commit SHA
        with: { fetch-depth: 0 }
      - run: sudo xcode-select -s /Applications/Xcode_26.app
      - name: Verzie
        id: v
        run: |
          echo "marketing=${GITHUB_REF_NAME#v}" >> $GITHUB_OUTPUT
          echo "build=$((1000 + GITHUB_RUN_NUMBER))" >> $GITHUB_OUTPUT
          [[ "$GITHUB_REF_NAME" == *-* ]] && echo "channel=beta" >> $GITHUB_OUTPUT || true
      - name: Import Developer ID do dočasnej keychain      # DEVID_P12_BASE64, heslá
      - name: xcodebuild archive + export (developer-id, ARCHS="arm64 x86_64", hardened runtime)
      - name: Notarizácia + staple .app                     # notarytool submit --wait
      - name: DMG (create-dmg) → codesign → notarytool → stapler
      - name: Release notes (git-cliff → HTML)
      - name: Načítať appcast (MUSÍ uspieť, žiadne "|| true") + 3 predošlé ZIP pre delty
      - name: generate_appcast --ed-key-file - --channel … --maximum-deltas 3
      - name: Kontrola monotónnosti build čísla voči appcastu
      - name: gh release create (DMG, ZIP, delty)           # NAJPRV assety…
      - name: Commit appcast.xml do web repo                # …POTOM appcast
      - name: Homebrew tap bump (len stable)
      - name: Zmazať keychain   # if: always()
```

**Secrets** (GitHub Environment `release`): `DEVID_P12_BASE64`, `DEVID_P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `ASC_KEY_P8_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `SPARKLE_ED_PRIVATE_KEY`, `APPLE_TEAM_ID`, `WEB_DEPLOY_TOKEN`, `TAP_TOKEN`. Kľúče musia byť zálohované offline. **Strata Sparkle kľúča znamená bolestivú migráciu.**

**Verifikačné brány** (CI zlyhá, ak neprejdú): `codesign --verify --strict`, `spctl -a -t exec` (výsledok „Notarized Developer ID“), `stapler validate` pre .app aj .dmg.

**Záloha:** `scripts/release.sh` urobí to isté lokálne na Macu, ak CI zlyhá.

### 6.4 CI pre každý PR (`ci.yml`)
`swift test` pre čisté moduly, SwiftLint/SwiftFormat, build Universal Release bez podpisu, snapshot testy layoutov. Nočný E2E beh s `WindowHarness` na self-hosted Macu alebo v Tart VM s predudeleným TCC **[overiť ceny a politiku runnerov v 2026]**.

### 6.5 Testovacia matica pred každým releasom
Čisté VM s macOS 14, 15, 26 a 27 (Intel aj Apple Silicon, kde sa dá):
- DMG stiahnutý cez prehliadač (karanténa)
- Prvé spustenie a Accessibility prompt
- **Update N-1 → N cez Sparkle a overenie, že AX oprávnenie ostane platné**
- Delta update
- Beta → stable

---

## 7. Promo web

### 7.1 Stack
- **Astro** (statický výstup) + **Tailwind v4** + vanilla TS islands
- **Cloudflare** (Workers Static Assets alebo Pages, podľa aktuálneho odporúčania **[overiť]**). Používa `_redirects` (`/download`) a `_headers` (CSP, cache).
- **Plausible** cez first-party proxy (bez cookies a bez cookie lišty, nech posúdi právnik)
- Rebuild: GitHub Action `on: release: published` → deploy hook, web je aktualizovaný do ~1 minúty

### 7.2 Napojenie na GitHub
- **Download tlačidlo:** `/download` → 302 na verziovaný DMG najnovšieho stable releasu. Text tlačidla (verzia, veľkosť) sa vygeneruje pri builde z GitHub API s tokenom, takže nevzniká layout shift ani rate limity.
- **Changelog:** vlastný Astro content loader `githubReleases()` → `/changelog`, `/changelog/v1-3-0` a RSS. Release notes v Sparkle odkazujú na tú istú stránku. Zdrojom pravdy je telo GitHub Release.
- Sekundárne CTA: `brew install --cask ordino` (najprv vlastný tap, oficiálny cask až po splnení notability).

### 7.3 Štruktúra stránky
1. **Nav** (sklo/blur): logo · Funkcie · Layouty · Changelog · GitHub · [Stiahnuť]
2. **Hero:** *„Every window, in its place.“* Podnadpis o jednom klávese a nulovom nastavovaní. CTA „Stiahnuť pre Mac · v1.3.0 · macOS 14+ · Apple Silicon & Intel“. Vedľa **animované demo** v HTML/CSS (okná sa rozhodené prichytia do 2×2, potom na master + stack). Približne 5 KB JS, Web Animations API, pri `prefers-reduced-motion` statický stav a tlačidlo Play.
3. **Problém v jednej vete:** iné nástroje umiestňujú okná po jednom, ordino celú obrazovku naraz.
4. **Ako to funguje:** stlač → pozri → hotovo
5. **Galéria layoutov** (interaktívna): prepínač 2 / 3 / 4 / 5 / 6 okien
6. **Funkcie** (6 dlaždíc): náhľad a Undo, viac monitorov, výnimky, klávesnica, rešpektuje notch a Dock, postavené pre macOS Tahoe
7. **Férové porovnanie** s Rectangle, natívnym tilingom a Amethyst/AeroSpace
8. **Súkromie:** *„Tvoje okná nikdy neopustia tvoj Mac.“* Názvy okien sa čítajú len lokálne, bez Screen Recording.
9. **FAQ** (`<details>` a FAQPage JSON-LD): oprávnenia, Spaces a fullscreen (mimo rozsahu), Intel, aktualizácie, rozdiel oproti Rectangle, odinštalovanie (vrátane `tccutil reset` a login itemu)
10. **Záverečné CTA** a **pätička:** Changelog · Privacy · Press kit · Kompatibilita (zoznam problémových aplikácií) · „Not affiliated with Apple“

### 7.4 SEO a launch
- Title „ordino: Arrange All Your Mac Windows With One Keystroke“, JSON-LD `SoftwareApplication`
- Long-tail stránky: `/vs/rectangle`, `/vs/macos-tiling`, `/guides/ultrawide`
- OG obrázky generované pri builde
- Launch: Show HN, r/macapps, Product Hunt, awesome-mac zoznamy

### 7.5 Výkonnostný rozpočet (vynútený cez Lighthouse CI)
LCP ≤ 1,8 s (mobil) · CLS ≤ 0,02 · JS ≤ 25 KB gzip · CSS ≤ 15 KB · 0 KB fontov (systémový stack) · Lighthouse ≥ 98/100/100/100.

---

## 8. Biznis model, súkromie a právo

**Rozhodnuté (21. 11. 2026):** ordino je **zadarmo** a **open source pod licenciou MIT**. Vlastníkom je **fyzická osoba**. Odpadajú platby, licenčné kľúče, licenčný server aj EULA. Na webe bude JSON-LD `price 0`.

- **Apple Developer Program: konto „Individual“** (99 USD ročne). Nepotrebuje D-U-N-S ani firmu a v podpise sa zobrazí tvoje meno („Developer ID Application: Meno Priezvisko“). Apple vie neskôr individuálne konto previesť na organizáciu a Team ID by mal ostať rovnaký **[overiť pri Apple Support pred prípadnou zmenou]**, takže voľba nie je nezvratná.
- **Živnosť ani s.r.o. netreba,** kým z projektu nemáš príjem. Ak neskôr pribudnú dary (GitHub Sponsors), ide o príjem fyzickej osoby. Vtedy to treba prebrať s účtovníkom **[overiť]**.
- **Bundle ID** zvoliť v týždni 0 a už nemeniť, napr. `app.ordino.mac` (ak bude doména `ordino.app`) alebo `io.github.<tvoj-login>.ordino`.
- **Copyright v LICENSE:** doplniť tvoje meno alebo „The ordino authors“.
- **Telemetria:** predvolene **vypnutá**, opt-in. Ak ju používateľ zapne: TelemetryDeck (len počty, napr. `layout.applied {n:4, layout:grid}`) a crash reporty cez Sentry (`sendDefaultPii=false`) alebo MetricKit. **Nikdy nezbierať** názvy okien, aplikácií ani obsah. Texty na webe musia sedieť so skutočnosťou.
- **Právo:** Privacy Policy, EULA (pri platenej verzii), atribúcie MIT kódu (Rectangle, Amethyst), z Loopu (GPL) žiadny kód. Overenie ochrannej známky názvu.

---

## 9. Časový plán (1–2 vývojári)

| Týždeň | Fáza | Výstup |
|---|---|---|
| **0** | Príprava | Rozhodnúť biznis model, právnu formu a názov. Apple Developer Program (D-U-N-S pri firme trvá dlhšie). Doména. Repozitáre. |
| **1** | **Rizikové prototypy** | Zachytenie z-order a focusu pred otvorením UI, non-activating panel, overlay, správanie Electron/JetBrains/Xcode pri resize, Stage Manager. **Go/no-go rozhodnutie.** |
| 2–3 | Jadro | `Geometry`, `LayoutEngine` (stratégie, chooser, priradenie) so 100 % testami, `DisplayKit` a prevody súradníc |
| 4–5 | WindowKit | AX vrstva, enumerácia, apply/verify/repair, quirks, learned min. veľkosti |
| 6 | ArrangeCore | Koordinátor, undo, cyklovanie, rotate, hotkeys, HUD |
| 7 | UI | Popover, onboarding (vrátane TCC sprievodcu a „Presunúť do Applications“), Nastavenia, výnimky |
| 8 | Release pipeline | Sparkle, podpis, notarizácia, `release.yml`, appcast na doméne, testy s dry-run beta tagmi, delta updaty |
| 9 | Web v1 | Astro stránka, demo animácia, `/download`, changelog loader, privacy, Plausible |
| 10 | Kvalita | Testovacia matica (14/15/26/27, Intel/ARM), výkon, prístupnosť, lokalizácia EN/SK |
| 11 | Uzavretá beta | 20–50 testerov cez beta kanál, diagnostika, opravy |
| **12** | **Verejná beta** | Show HN / r/macapps, stránka kompatibility |
| 13 | Stabilizácia | Opravy, Homebrew tap, Pro licencie (pri modeli A/B) |
| **14** | **1.0** | Product Hunt launch |
| 15+ | v1.x | Hold-to-preview, multi-monitor, pravidlá, App Intents, uložené layouty |

---

## 10. Registre rizík

| # | Riziko | Dopad | Pravdepodobnosť | Opatrenie |
|---|---|---|---|---|
| 1 | **TCC „zapnuté, ale nedôveryhodné“** po Sparkle update alebo update macOS | Vysoký (aplikácia prestane fungovať) | Stredná | Detekcia (`.apiDisabled` napriek zapnutému prepínaču) a sprievodca opravou. Test N-1 → N pri každom releasi. Stabilná podpisová identita. |
| 2 | Zmeny AX alebo WindowServer v novom macOS | Vysoký | Stredná | Len verejné API, sledovať betaverzie macOS od WWDC, kill switch |
| 3 | Electron/Java aplikácie sa správajú nepredvídateľne | Stredný | Vysoká | Quirks tabuľka, settle + re-read, stránka kompatibility |
| 4 | Natívne tiling v macOS sa rozšíri | Vysoký (strategický) | Stredná | Odlíšenie: ľubovoľný počet okien, pravidlá, náhľad, Undo, automatizácia |
| 5 | Zachytenie focusu pred otvorením popoveru zlyhá | Stredný | Stredná | Prototyp v týždni 1, `NSPanel(.nonactivatingPanel)` |
| 6 | Strata Sparkle alebo Developer ID kľúča | Vysoký | Nízka | Offline zálohy na 2 miestach, dokumentovaný postup rotácie |
| 7 | Stage Manager a Spaces | Stredný | Stredná | Obmedzenie jasne komunikovať vo FAQ, nesľubovať neoverené |
| 8 | Ikona v menu bare je skrytá (notch, Bartender, nastavenia macOS) | Nízky | Vysoká | Hotkey-first, opätovné spustenie otvorí Nastavenia |
| 9 | Kolízia názvu alebo ochrannej známky | Stredný | Stredná | Overiť v týždni 0 |
| 10 | Zmeny cien GitHub runnerov | Nízky | Stredná | Verejný repozitár, lokálny `release.sh` |

---

## 11. Rozpočet

| Položka | Ročne |
|---|---|
| Apple Developer Program | 99 USD |
| Doména | 10–20 USD |
| GitHub (verejný repozitár: Releases, Actions) | 0 USD |
| Cloudflare hosting, Plausible (alebo self-host) | 0 USD, Plausible Cloud ~ 9 USD/mes. **[overiť]** |
| TelemetryDeck, Sentry (free tier) | 0 USD |
| Platobná brána | ~4–5 % + ~0,50 USD za predaj |
| **Spolu fixne** | **~110–140 USD ročne** (s Plausible Cloud ~ +110 USD) |

---

## 12. Definition of Done pre 1.0

- [ ] Usporiadanie 1–9 okien za < 150 ms (6 okien) na M-series, bez blikania v top 20 aplikáciách (Safari, Chrome, Arc, VS Code, Xcode, Slack, Teams, Zoom, Figma, Notion, JetBrains, Terminal, iTerm, Finder, Mail, Spotify, Discord, Obsidian, Excel, Word)
- [ ] Undo vráti presný pôvodný stav
- [ ] Onboarding zvládne nový používateľ bez návodu do 60 s (usability test s 5 ľuďmi)
- [ ] Update N-1 → N zachová oprávnenie na všetkých OS v matici
- [ ] Notarizácia, staple a overenie prejdú automaticky v CI
- [ ] Web: Lighthouse ≥ 98/100/100/100, privacy policy a FAQ sedia so skutočným správaním
- [ ] VoiceOver, Reduce Motion a Reduce Transparency otestované
- [ ] Nečinná aplikácia: < 30 MB RSS, ~0 % CPU

---

## 13. Rozhodnutia

1. **Biznis model:** zadarmo ✅
2. **Právna forma:** fyzická osoba, Apple Developer konto Individual ✅
3. **Názov:** **ordino** (s malým „o“, lat. „usporadúvam“) ✅. Ešte overiť ochrannú známku a doménu (`ordino.app`?). „Tessera“ je obsadená iným macOS window managerom.
4. **Zdrojový kód:** verejný, MIT ✅. Verejný repozitár má GitHub Actions minúty zadarmo.

**Ešte otvorené:** doména a bundle ID (týždeň 0).

## 14. Na overenie pred štartom
Aktuálna verzia Sparkle a flagy `generate_appcast` · label `macos-26` runnera a cesta k Xcode · presné Liquid Glass API v SDK · deep link na Accessibility v macOS 26/27 · rozsah „Tile All“ v Rectangle a Window Layouts v Raycaste (kvôli porovnávacej tabuľke) · Cloudflare Pages vs Workers · poplatky Paddle a Polar · správanie AX so Stage Managerom a so Sequoia tilingom.
