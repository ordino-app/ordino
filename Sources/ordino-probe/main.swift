// ordino-probe: week-1 prototype.
//
//   swift run ordino-probe                 # dry run: list windows + print plan
//   swift run ordino-probe --apply         # actually move the windows
//   swift run ordino-probe --layout grid --rotate 1 --apply
//   swift run ordino-probe --prompt        # show the Accessibility prompt
//
// The process that runs this (Terminal, iTerm, ...) needs Accessibility access.

import Foundation
import Geometry
import LayoutEngine
import WindowKit

@MainActor
func run() async -> Int32 {
    var args = Array(CommandLine.arguments.dropFirst())
    func flag(_ name: String) -> Bool {
        guard let i = args.firstIndex(of: name) else { return false }
        args.remove(at: i)
        return true
    }
    func option(_ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        args.removeSubrange(i...(i + 1))
        return v
    }

    let apply = flag("--apply")
    let prompt = flag("--prompt")
    let layout = option("--layout").flatMap(LayoutID.init(rawValue:))
    let rotation = option("--rotate").flatMap(Int.init) ?? 0

    // Capture focus first, before anything else can change it.
    let focused = WindowDiscovery.focusedWindowID()

    print("ordino-probe")
    print("Accessibility trusted: \(AccessibilityPermission.isTrusted)")
    if !AccessibilityPermission.isTrusted {
        if prompt { AccessibilityPermission.requestWithPrompt() }
        print(
            """
            -> Grant Accessibility to the app running this command:
               System Settings > Privacy & Security > Accessibility
               (\(AccessibilityPermission.settingsURL.absoluteString))
               Without it, windows can be listed by CoreGraphics but not matched or moved.
            """)
    }

    for d in Displays.all() { print("Display: \(d)") }
    guard let display = Displays.underMouse() else {
        print("No display.")
        return 1
    }
    print("Target (under mouse): \(display.name)\n")

    let found = WindowDiscovery().windows(on: display, focusedID: focused)
    print("Eligible windows (front to back):")
    for w in found.windows {
        let mark = w.info.isFocused ? "*" : " "
        let fixed = w.info.isResizable ? "" : " [fixed size]"
        print(" \(mark) #\(w.info.id) \(w.appName) - \(w.title.prefix(40)) \(w.info.frame)\(fixed)")
    }
    if !found.skipped.isEmpty {
        print("Skipped:")
        for s in found.skipped { print("   \(s)") }
    }

    let ctx = LayoutContext(area: display.visibleFrame, windows: found.windows.map(\.info))
    guard let plan = LayoutEngine().plan(ctx, layout: layout, rotation: rotation) else {
        print("\nNothing to arrange.")
        return 0
    }
    print("\nPlan: \(plan.layout)  (cycle: \(plan.candidates.map(\.rawValue).joined(separator: " -> ")))")
    if !plan.isFeasible { print("  note: minimum sizes don't all fit") }
    for w in found.windows {
        if let f = plan.frames[w.info.id] { print("   #\(w.info.id) \(w.appName): \(w.info.frame) -> \(f)") }
    }
    if !plan.unplaced.isEmpty { print("   left alone: \(plan.unplaced)") }

    guard apply else {
        print("\nDry run. Add --apply to move the windows.")
        return 0
    }
    guard AccessibilityPermission.isTrusted else {
        print("\nCannot apply without Accessibility.")
        return 2
    }

    let start = ContinuousClock.now
    let outcomes = await WindowMover().apply(plan.frames, to: found.windows)
    let elapsed = ContinuousClock.now - start
    print("\nApplied in \(elapsed.formatted(.units(allowed: [.milliseconds]))) (incl. settle delay):")
    for o in outcomes { print("   \(o)") }
    return 0
}

exit(await run())
