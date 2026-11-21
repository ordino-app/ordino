import Geometry
import LayoutEngine
import Testing

@testable import ArrangeCore

/// In-memory windows. Optional per-window minimum sizes are enforced like a
/// real app would: the window refuses to get smaller.
@MainActor
final class FakeBackend: WindowBackend {
    var display: DisplaySnapshot? = DisplaySnapshot(
        id: "uuid-1", name: "Test Display", visibleFrame: Rect(x: 0, y: 25, w: 2560, h: 1415))
    var frames: [WindowID: Rect]
    var order: [WindowID]
    var minSizes: [WindowID: Size] = [:]
    var applyDelay: Duration = .zero
    /// Windows that accept moves but apply resizes "later" (report the old size).
    var lagging: Set<WindowID> = []
    /// Windows that disappear during the next apply.
    var vanishing: Set<WindowID> = []
    private(set) var applyCount = 0

    init(count: Int) {
        order = (1...count).map { WindowID($0) }
        frames = Dictionary(
            uniqueKeysWithValues: order.map { id in
                (id, Rect(x: 100 + Double(id) * 40, y: 100 + Double(id) * 30, w: 1000, h: 700))
            })
    }

    func targetDisplay() -> DisplaySnapshot? { display }

    func snapshot(of display: DisplaySnapshot, focusedID: WindowID?) -> WindowSnapshot {
        WindowSnapshot(
            windows: order.compactMap { id in
                frames[id].map { WindowInfo(id: id, frame: $0, isFocused: id == focusedID) }
            },
            appNames: Dictionary(uniqueKeysWithValues: order.map { ($0, "App \($0)") }))
    }

    func apply(_ targets: [WindowID: Rect]) async -> [WindowID: Rect?] {
        applyCount += 1
        if applyDelay > .zero { try? await Task.sleep(for: applyDelay) }
        var result: [WindowID: Rect?] = [:]
        for id in vanishing {
            frames[id] = nil
            order.removeAll { $0 == id }
        }
        vanishing = []
        for (id, t) in targets {
            guard let old = frames[id] else {
                result[id] = .some(nil)
                continue
            }
            var f = t
            if lagging.contains(id) {
                f.w = old.w
                f.h = old.h
            }
            if let m = minSizes[id] {
                f.w = max(f.w, m.w)
                f.h = max(f.h, m.h)
            }
            frames[id] = f
            result[id] = f
        }
        return result
    }
}

/// Manually advanced clock for cycle-interval tests.
final class TestClock: @unchecked Sendable {
    var instant = ContinuousClock.now
    func advance(_ d: Duration) { instant = instant.advanced(by: d) }
}

@MainActor
@Suite("ArrangeCoordinator")
struct ArrangeCoordinatorTests {
    func make(_ n: Int) -> (FakeBackend, ArrangeCoordinator, TestClock) {
        let backend = FakeBackend(count: n)
        let clock = TestClock()
        let coordinator = ArrangeCoordinator(backend: backend, now: { clock.instant })
        return (backend, coordinator, clock)
    }

    func report(_ outcome: ArrangeCoordinator.Outcome) throws -> ArrangeCoordinator.Report {
        guard case .arranged(let r) = outcome else {
            Issue.record("expected .arranged, got \(outcome)")
            throw CancellationError()
        }
        return r
    }

    @Test func arrangeUsesTheSmartDefault() async throws {
        let (backend, coordinator, _) = make(4)
        let r = try report(await coordinator.perform(.arrange, focusedID: 1))
        #expect(r.layout == .grid)
        #expect(r.windowCount == 4)
        #expect(r.mismatchedIDs.isEmpty)
        let frames = Array(backend.frames.values)
        for a in frames.indices { for b in frames.indices where a < b { #expect(!frames[a].overlaps(frames[b])) } }
    }

    @Test func pressingAgainQuicklyCyclesLayouts() async throws {
        let (_, coordinator, clock) = make(4)
        let first = try report(await coordinator.perform(.arrange, focusedID: 1))
        clock.advance(.milliseconds(800))
        let second = try report(await coordinator.perform(.arrange, focusedID: 1))
        #expect(first.layout == .grid)
        #expect(second.layout == .masterStack)
    }

    @Test func pressingAgainLaterDoesNotCycleButRemembersChoice() async throws {
        let (_, coordinator, clock) = make(3)
        _ = try report(await coordinator.perform(.arrange, focusedID: 1))  // masterStack
        clock.advance(.milliseconds(500))
        let cycled = try report(await coordinator.perform(.arrange, focusedID: 1))  // columns
        clock.advance(.seconds(10))
        let later = try report(await coordinator.perform(.arrange, focusedID: 1))
        #expect(cycled.layout == .columns)
        #expect(later.layout == .columns, "the cycled-to layout becomes the preference for 3 windows")
    }

    @Test func differentWindowsDoNotCycle() async throws {
        let (backend, coordinator, clock) = make(4)
        _ = try report(await coordinator.perform(.arrange, focusedID: 1))
        backend.order.removeLast()
        clock.advance(.milliseconds(300))
        let r = try report(await coordinator.perform(.arrange, focusedID: 1))
        #expect(r.layout == .masterStack, "3 windows -> default, not a cycle")
        #expect(r.windowCount == 3)
    }

    @Test func nextAndPreviousLayout() async throws {
        let (_, coordinator, clock) = make(4)
        let a = try report(await coordinator.perform(.arrange, focusedID: 1))
        clock.advance(.milliseconds(100))
        let b = try report(await coordinator.perform(.nextLayout, focusedID: 1))
        clock.advance(.milliseconds(100))
        let c = try report(await coordinator.perform(.previousLayout, focusedID: 1))
        #expect(a.layout == .grid && b.layout == .masterStack && c.layout == .grid)
    }

    @Test func undoRestoresPreviousFrames() async throws {
        let (backend, coordinator, _) = make(3)
        let original = backend.frames
        _ = try report(await coordinator.perform(.arrange, focusedID: 1))
        #expect(backend.frames != original)
        #expect(coordinator.canUndo)
        #expect(await coordinator.undo() == .restored(3))
        #expect(backend.frames == original)
        #expect(await coordinator.undo() == .nothingToUndo)
    }

    @Test func arrangingAnArrangedScreenAddsNoUndoStep() async throws {
        let (_, coordinator, clock) = make(3)
        _ = try report(await coordinator.perform(.arrange, focusedID: 1))
        clock.advance(.seconds(10))
        _ = try report(await coordinator.perform(.arrange, focusedID: 1))  // no-op
        _ = await coordinator.undo()
        #expect(!coordinator.canUndo, "the no-op arrange must not have pushed a second step")
    }

    @Test func rotateMovesEveryWindow() async throws {
        let (backend, coordinator, clock) = make(3)
        _ = try report(await coordinator.perform(.arrange, focusedID: 1))
        let before = backend.frames
        clock.advance(.milliseconds(200))
        let r = try report(await coordinator.perform(.rotate, focusedID: 1))
        #expect(r.layout == .masterStack)
        #expect(Set(backend.frames.values) == Set(before.values))
        for id in before.keys { #expect(backend.frames[id] != before[id]) }
    }

    @Test func learnsMinimumSizesSoNeighboursDoNotOverlap() async throws {
        let (backend, coordinator, _) = make(3)
        backend.minSizes[2] = Size(w: 1300, h: 0)  // wider than a 3-column slot
        _ = try report(await coordinator.perform(.layout(.columns), focusedID: nil))
        #expect(
            backend.applyCount == 2, "one apply, one repair pass; got \(backend.applyCount) frames \(backend.frames)")
        let frames = Array(backend.frames.values)
        for a in frames.indices {
            for b in frames.indices where a < b {
                #expect(!frames[a].overlaps(frames[b]), "\(frames[a]) vs \(frames[b])")
            }
        }
        #expect(backend.frames[2]!.w >= 1300)
    }

    @Test func concurrentPressIsRejected() async throws {
        let (backend, coordinator, _) = make(2)
        backend.applyDelay = .milliseconds(100)
        async let first = coordinator.perform(.arrange, focusedID: 1)
        try await Task.sleep(for: .milliseconds(20))
        let second = await coordinator.perform(.arrange, focusedID: 1)
        #expect(second == .busy)
        _ = try report(await first)
    }

    @Test func emptyAndMissingDisplay() async {
        let (backend, coordinator, _) = make(1)
        backend.order = []
        #expect(await coordinator.perform(.arrange, focusedID: nil) == .nothingToArrange(displayName: "Test Display"))
        backend.display = nil
        #expect(await coordinator.perform(.arrange, focusedID: nil) == .noDisplay)
    }

    @Test func previewDoesNotMoveAnything() throws {
        let (backend, coordinator, _) = make(4)
        let before = backend.frames
        let preview = try #require(coordinator.preview(focusedID: 1))
        #expect(preview.plan.layout == .grid)
        #expect(preview.appNames[1] == "App 1")
        #expect(backend.frames == before)
        #expect(backend.applyCount == 0)
    }
}

@MainActor
@Suite("ArrangeCoordinator review regressions")
struct ArrangeCoordinatorRegressionTests {
    func make(_ n: Int) -> (FakeBackend, ArrangeCoordinator, TestClock) {
        let backend = FakeBackend(count: n)
        let clock = TestClock()
        return (backend, ArrangeCoordinator(backend: backend, now: { clock.instant }), clock)
    }

    func layout(_ o: ArrangeCoordinator.Outcome) -> LayoutID? {
        if case .arranged(let r) = o { return r.layout }
        return nil
    }

    @Test("a repair pass after Rotate keeps the rotation")
    func rotateSurvivesRepair() async {
        let (backend, coordinator, clock) = make(3)
        _ = await coordinator.perform(.layout(.masterStack), focusedID: 1)
        let master = backend.frames[1]!
        clock.advance(.milliseconds(300))
        backend.minSizes[1] = Size(w: 1300, h: 0)  // forces a repair while window 1 is in the stack
        _ = await coordinator.perform(.rotate, focusedID: 1)
        #expect(backend.frames[1]!.area < master.area, "window 1 must have rotated out of the master slot")
        let biggest = backend.frames.max { $0.value.area < $1.value.area }!.key
        #expect(biggest != 1)
    }

    @Test("preview shows exactly what Arrange will do, including cycling and stale preferences")
    func previewMatchesPerform() async {
        let (_, coordinator, clock) = make(4)
        _ = await coordinator.perform(.arrange, focusedID: 1)  // grid
        clock.advance(.milliseconds(400))
        let preview = coordinator.preview(focusedID: 1)?.plan.layout
        let performed = layout(await coordinator.perform(.arrange, focusedID: 1))
        #expect(preview == performed)
        #expect(performed == .masterStack)
    }

    @Test("a stale preferred layout is ignored by preview and perform alike")
    func stalePreference() async {
        let backend = FakeBackend(count: 2)
        backend.display = DisplaySnapshot(
            id: "uuid-1", name: "Portrait", visibleFrame: Rect(x: 0, y: 0, w: 1080, h: 1920))
        let coordinator = ArrangeCoordinator(backend: backend, preferredLayouts: ["uuid-1#2": .masterStack])
        let preview = coordinator.preview(focusedID: nil)?.plan.layout
        let performed = layout(await coordinator.perform(.arrange, focusedID: nil))
        #expect(preview == .rows && performed == .rows)
    }

    @Test("one Undo reverts a whole run of quick presses, including the remembered layout")
    func undoRevertsCycleRun() async {
        let (backend, coordinator, clock) = make(4)
        let original = backend.frames
        _ = await coordinator.perform(.arrange, focusedID: 1)
        clock.advance(.milliseconds(300))
        _ = await coordinator.perform(.arrange, focusedID: 1)
        clock.advance(.milliseconds(300))
        _ = await coordinator.perform(.arrange, focusedID: 1)
        #expect(coordinator.preferredLayouts["uuid-1#4"] == .columns)
        #expect(await coordinator.undo() == .restored(4))
        #expect(backend.frames == original)
        #expect(coordinator.preferredLayouts["uuid-1#4"] == nil)
        #expect(!coordinator.canUndo)
    }

    @Test("a resize the app applies late is not learned as a minimum size")
    func laggingResizeNotLearned() async {
        let (backend, coordinator, clock) = make(3)
        backend.lagging = [2]
        _ = await coordinator.perform(.layout(.columns), focusedID: nil)
        #expect(backend.applyCount == 1, "no repair pass for an unchanged size")
        backend.lagging = []
        clock.advance(.seconds(5))
        _ = await coordinator.perform(.layout(.columns), focusedID: nil)
        let widths = Set(backend.frames.values.map { Int($0.w.rounded()) })
        #expect(widths.count == 1, "all three columns equal once the app catches up: \(widths)")
    }

    @Test("a window that closes during arranging doesn't keep a slot or count as restored")
    func vanishedWindow() async {
        let (backend, coordinator, _) = make(3)
        backend.minSizes[2] = Size(w: 1300, h: 0)  // triggers a repair pass
        backend.vanishing = [3]
        guard case .arranged(let r) = await coordinator.perform(.layout(.columns), focusedID: nil) else {
            Issue.record("expected arranged")
            return
        }
        #expect(r.windowCount == 2)
        #expect(r.mismatchedIDs.isEmpty, "mismatched \(r.mismatchedIDs) frames \(backend.frames)")
        let covered = backend.frames.values.reduce(0) { $0 + $1.w }
        #expect(covered > 2400, "the two remaining windows share the full width")
        #expect(await coordinator.undo() == .restored(2))
    }

    @Test func undoWhileBusyIsReported() async throws {
        let (backend, coordinator, _) = make(2)
        _ = await coordinator.perform(.arrange, focusedID: 1)
        backend.applyDelay = .milliseconds(100)
        async let running = coordinator.perform(.layout(.rows), focusedID: 1)
        try await Task.sleep(for: .milliseconds(20))
        #expect(await coordinator.undo() == .busy)
        _ = await running
    }
}
