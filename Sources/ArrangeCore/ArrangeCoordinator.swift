import Geometry
import LayoutEngine

/// Runs arrange / cycle / rotate / undo against a ``WindowBackend``.
///
/// Rules:
/// - Pressing Arrange again within ``cycleInterval`` on the same display with the
///   same windows switches to the next layout and remembers it for that window count.
/// - A run of quick presses is one undo step: Undo returns to the state before the first.
/// - Only one operation runs at a time; presses during a running one return `.busy`.
/// - When a window refuses its slot (minimum size), the size is learned and the
///   plan is solved again from the windows' actual positions, so neighbours shrink
///   instead of overlapping and the assignment (including a rotation) stays put.
@MainActor
public final class ArrangeCoordinator {
    public enum Action: Sendable, Equatable {
        case arrange
        case nextLayout
        case previousLayout
        case rotate
        /// Apply a specific layout.
        case layout(LayoutID)
    }

    public struct Report: Sendable, Equatable {
        public let displayName: String
        public let layout: LayoutID
        /// Windows that were moved (and still exist).
        public let windowCount: Int
        /// Windows beyond the per-display limit, left untouched.
        public let unplacedCount: Int
        /// Windows that exist but don't sit where they were asked to.
        public let mismatchedIDs: [WindowID]
        public let isFeasible: Bool
    }

    public enum Outcome: Sendable, Equatable {
        case arranged(Report)
        case nothingToArrange(displayName: String)
        case noDisplay
        case busy
    }

    public enum UndoResult: Sendable, Equatable {
        case restored(Int)
        case nothingToUndo
        case busy
    }

    /// What Arrange would do right now. Used by the menu preview.
    public struct Preview: Sendable {
        public let display: DisplaySnapshot
        public let plan: LayoutPlan
        public let appNames: [WindowID: String]
        public let bundleIDs: [WindowID: String]
        public let titles: [WindowID: String]
        /// Placed windows, front to back.
        public let windowIDs: [WindowID]
        /// The window that gets the master slot (if the layout has one).
        public let primaryID: WindowID?
    }

    public var preferences: LayoutPreferences
    public var cycleInterval: Duration = .seconds(2)
    /// Maximum number of undo steps kept.
    public var undoLimit = 20

    /// Layout chosen by the user per (display, window count), reused next time.
    public private(set) var preferredLayouts: [String: LayoutID] = [:]
    /// Bundle IDs whose window becomes the primary (master) window when present,
    /// in priority order. Beats the focused window; an explicit pick beats this.
    public var preferredPrimaryApps: [String] = []
    public var canUndo: Bool { !undoStack.isEmpty }

    private struct UndoEntry {
        var frames: [WindowID: Rect]
        /// Preference that was in place before this step, restored by Undo.
        var preference: (key: String, previous: LayoutID?)?
        var sequence: Int
    }

    private struct Resolution {
        var layout: LayoutID?
        var rotation = 0
        var userChoseLayout = false
        var continuing = false
        var key: String
    }

    private let backend: WindowBackend
    private let engine = LayoutEngine()
    private let now: () -> ContinuousClock.Instant
    private var isBusy = false
    private var undoStack: [UndoEntry] = []
    private var sequence = 0
    private var learnedMinSizes: [WindowID: Size] = [:]
    private var last: (displayID: String, windows: Set<WindowID>, layout: LayoutID, at: ContinuousClock.Instant)?

    public init(
        backend: WindowBackend,
        preferences: LayoutPreferences = .init(),
        preferredLayouts: [String: LayoutID] = [:],
        now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.backend = backend
        self.preferences = preferences
        self.preferredLayouts = preferredLayouts
        self.now = now
    }

    // MARK: - Public API

    /// - Parameters:
    ///   - focusedID: the window the user is working in.
    ///   - primaryID: a window the user explicitly picked as primary (menu).
    ///   - display: the display to arrange; `nil` asks the backend (display under the mouse).
    public func perform(
        _ action: Action, focusedID: WindowID?, primaryID: WindowID? = nil, display requested: DisplaySnapshot? = nil
    ) async -> Outcome {
        guard !isBusy else { return .busy }
        isBusy = true
        defer { isBusy = false }

        guard let display = requested ?? backend.targetDisplay() else { return .noDisplay }
        let snapshot = backend.snapshot(of: display, focusedID: focusedID)
        let primary = resolvePrimary(snapshot, focusedID: focusedID, explicit: primaryID)
        let windows = withLearnedSizes(markPrimary(snapshot.windows, primary))
        guard !windows.isEmpty else { return .nothingToArrange(displayName: display.name) }

        let r = resolve(action, display: display, windows: windows)
        if !r.continuing { sequence += 1 }

        let context = LayoutContext(area: display.visibleFrame, windows: windows, preferences: preferences)
        guard var plan = engine.plan(context, layout: r.layout, rotation: r.rotation) else {
            return .nothingToArrange(displayName: display.name)
        }

        recordUndo(windows: windows, plan: plan, resolution: r)
        if r.userChoseLayout { preferredLayouts[r.key] = plan.layout }

        let before = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame) })
        var actual = await backend.apply(plan.frames)

        // Repair pass: learn minimum sizes from windows that refused to shrink,
        // then re-plan from where the windows are now.
        if learn(from: actual, targets: plan.frames, before: before) {
            // Actual frames first, then learned sizes (so a fresh minimum isn't
            // "expired" against the window's pre-arrange size).
            let moved = windows.compactMap { w -> WindowInfo? in
                var m = w
                if plan.frames[w.id] != nil {
                    guard let frame = actual[w.id] ?? nil else { return nil }  // gone or unreadable
                    m.frame = frame
                }
                m.isFocused = false  // follow actual positions, don't re-pin the master
                return m
            }
            let current = withLearnedSizes(moved)
            let repaired = LayoutContext(area: display.visibleFrame, windows: current, preferences: preferences)
            if let replanned = engine.plan(repaired, layout: plan.layout), replanned.frames != plan.frames {
                let previousActual = actual
                plan = replanned
                actual = await backend.apply(plan.frames)
                _ = learn(
                    from: actual, targets: plan.frames,
                    before: previousActual.compactMapValues { $0 })
            }
        }

        let alive = plan.frames.keys.filter { (actual[$0] ?? nil) != nil }
        last = (display.id, Set(alive), plan.layout, now())

        let mismatched = alive.filter { id in
            guard let a = actual[id] ?? nil, let target = plan.frames[id] else { return false }
            return !a.isApproximately(target, tolerance: 2)
        }.sorted()

        return .arranged(
            Report(
                displayName: display.name, layout: plan.layout, windowCount: alive.count,
                unplacedCount: plan.unplaced.count, mismatchedIDs: mismatched, isFeasible: plan.isFeasible))
    }

    /// Forgets every remembered layout choice (Settings › Layouts).
    public func forgetPreferredLayouts() {
        preferredLayouts = [:]
    }

    /// Puts windows back where they were before the last arrange (or run of quick presses).
    public func undo() async -> UndoResult {
        guard !isBusy else { return .busy }
        guard let entry = undoStack.popLast() else { return .nothingToUndo }
        isBusy = true
        defer { isBusy = false }
        let result = await backend.apply(entry.frames)
        if let pref = entry.preference { preferredLayouts[pref.key] = pref.previous }
        last = nil
        return .restored(result.values.filter { $0 != nil }.count)
    }

    /// Dry run: exactly what ``perform(_:focusedID:primaryID:display:)`` would do for `action`.
    public func preview(
        focusedID: WindowID?, primaryID: WindowID? = nil, display requested: DisplaySnapshot? = nil,
        action: Action = .arrange
    ) -> Preview? {
        guard let display = requested ?? backend.targetDisplay() else { return nil }
        let snapshot = backend.snapshot(of: display, focusedID: focusedID)
        let primary = resolvePrimary(snapshot, focusedID: focusedID, explicit: primaryID)
        let windows = withLearnedSizes(markPrimary(snapshot.windows, primary))
        guard !windows.isEmpty else { return nil }
        let r = resolve(action, display: display, windows: windows)
        let context = LayoutContext(area: display.visibleFrame, windows: windows, preferences: preferences)
        guard let plan = engine.plan(context, layout: r.layout, rotation: r.rotation) else { return nil }
        let placed = windows.map(\.id).filter { plan.frames[$0] != nil }
        return Preview(
            display: display, plan: plan, appNames: snapshot.appNames, bundleIDs: snapshot.bundleIDs,
            titles: snapshot.titles, windowIDs: placed, primaryID: primary.flatMap { placed.contains($0) ? $0 : nil })
    }

    // MARK: - Primary window

    /// Explicit pick > first window of a preferred app (front-most of that app) > focused window.
    private func resolvePrimary(_ snapshot: WindowSnapshot, focusedID: WindowID?, explicit: WindowID?) -> WindowID? {
        let ids = snapshot.windows.prefix(max(1, preferences.maxWindows)).map(\.id)
        if let explicit, ids.contains(explicit) { return explicit }
        for bundleID in preferredPrimaryApps {
            if let id = ids.first(where: { snapshot.bundleIDs[$0] == bundleID }) { return id }
        }
        if let focusedID, ids.contains(focusedID) { return focusedID }
        return nil
    }

    private func markPrimary(_ windows: [WindowInfo], _ primary: WindowID?) -> [WindowInfo] {
        windows.map { w in
            var copy = w
            copy.isFocused = w.id == primary
            return copy
        }
    }

    // MARK: - Layout resolution (shared by perform and preview)

    private func resolve(_ action: Action, display: DisplaySnapshot, windows: [WindowInfo]) -> Resolution {
        let placed = Set(windows.prefix(max(1, preferences.maxWindows)).map(\.id))
        let count = placed.count
        let key = "\(display.id)#\(count)"
        let candidates = engine.candidates(count: count, area: display.visibleFrame, preferences: preferences)
        let remembered = preferredLayouts[key].flatMap { candidates.contains($0) ? $0 : nil }
        let continuing = isContinuation(display: display, windows: placed)
        let current = continuing ? last?.layout : nil

        var r = Resolution(key: key)
        r.continuing = continuing
        switch action {
        case .arrange:
            if let current {
                r.layout = step(from: current, by: 1, in: candidates)
                r.userChoseLayout = true
            } else {
                r.layout = remembered
            }
        case .nextLayout:
            r.layout = step(from: current ?? remembered ?? candidates.first, by: 1, in: candidates)
            r.userChoseLayout = true
        case .previousLayout:
            r.layout = step(from: current ?? remembered ?? candidates.first, by: -1, in: candidates)
            r.userChoseLayout = true
        case .rotate:
            r.layout = current ?? remembered
            r.rotation = 1
        case .layout(let id):
            r.layout = id
            r.userChoseLayout = true
        }
        return r
    }

    private func isContinuation(display: DisplaySnapshot, windows: Set<WindowID>) -> Bool {
        guard let last, last.displayID == display.id, last.windows == windows else { return false }
        return now() - last.at <= cycleInterval
    }

    private func step(from layout: LayoutID?, by offset: Int, in candidates: [LayoutID]) -> LayoutID? {
        guard !candidates.isEmpty else { return layout }
        guard let layout, let i = candidates.firstIndex(of: layout) else {
            return offset >= 0 ? candidates.first : candidates.last
        }
        let n = candidates.count
        return candidates[((i + offset) % n + n) % n]
    }

    // MARK: - Undo bookkeeping

    private func recordUndo(windows: [WindowInfo], plan: LayoutPlan, resolution r: Resolution) {
        let before = Dictionary(
            uniqueKeysWithValues: windows.filter { plan.frames[$0.id] != nil }.map { ($0.id, $0.frame) })
        let changesSomething = before.contains { id, frame in
            guard let target = plan.frames[id] else { return false }
            return !frame.isApproximately(target, tolerance: 1)
        }
        let preference = r.userChoseLayout ? (key: r.key, previous: preferredLayouts[r.key]) : nil

        if let top = undoStack.last, top.sequence == sequence {
            // Same run of quick presses: keep the frames from before the first press,
            // and the oldest preference.
            var merged = top
            for (id, frame) in before where merged.frames[id] == nil { merged.frames[id] = frame }
            if merged.preference == nil { merged.preference = preference }
            undoStack[undoStack.count - 1] = merged
        } else if changesSomething {
            undoStack.append(UndoEntry(frames: before, preference: preference, sequence: sequence))
            let limit = max(1, undoLimit)
            if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        }
    }

    // MARK: - Learned minimum sizes

    /// Applies learned minimums, and forgets any that a window has since shown to be wrong
    /// (it is currently smaller than the learned minimum).
    private func withLearnedSizes(_ windows: [WindowInfo]) -> [WindowInfo] {
        windows.map { w in
            guard var learned = learnedMinSizes[w.id] else { return w }
            if w.frame.w < learned.w - 2 { learned.w = 0 }
            if w.frame.h < learned.h - 2 { learned.h = 0 }
            learnedMinSizes[w.id] = (learned.w == 0 && learned.h == 0) ? nil : learned
            var copy = w
            let existing = w.minSize ?? .zero
            copy.minSize = Size(w: max(existing.w, learned.w), h: max(existing.h, learned.h))
            return copy
        }
    }

    /// Records a minimum when a window ended up larger than its target *and* its
    /// size actually changed. An unchanged size more likely means the app hasn't
    /// applied the resize yet (Electron, JetBrains) than a real minimum.
    /// Returns true when something new was learned.
    private func learn(from actual: [WindowID: Rect?], targets: [WindowID: Rect], before: [WindowID: Rect]) -> Bool {
        var changed = false
        for (id, target) in targets {
            guard let a = actual[id] ?? nil else { continue }
            let old = learnedMinSizes[id] ?? .zero
            var new = old
            let prior = before[id]
            if a.w > target.w + 2, prior.map({ abs($0.w - a.w) > 1 }) ?? true { new.w = a.w }
            if a.h > target.h + 2, prior.map({ abs($0.h - a.h) > 1 }) ?? true { new.h = a.h }
            if new != old {
                learnedMinSizes[id] = new
                changed = true
            }
        }
        return changed
    }
}
