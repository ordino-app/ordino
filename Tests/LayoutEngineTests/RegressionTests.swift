import Geometry
import Testing

@testable import LayoutEngine

/// One test per finding from the first code review.
@Suite("Review regressions")
struct RegressionTests {
    let engine = LayoutEngine()

    @Test("infeasible minimums never collapse a window to zero")
    func noZeroFrames() throws {
        let area = Rect(x: 0, y: 0, w: 1516, h: 1000)
        var windows = Fixture.windows(3, in: area, focused: nil)
        windows[0].minSize = Size(w: 2000, h: 0)
        let plan = try #require(engine.plan(LayoutContext(area: area, windows: windows), layout: .columns))
        #expect(!plan.isFeasible)
        let usable = area.inset(by: LayoutPreferences().outerPadding)
        for f in plan.frames.values {
            #expect(f.w >= FrameSolver.minimumShare - 0.001)
            #expect(usable.contains(f, tolerance: 0.01))
        }
    }

    @Test("repeated Rotate 1 cycles through every arrangement", arguments: [LayoutID.masterStack, .columns, .grid])
    func rotateCycles(layout: LayoutID) throws {
        let area = Fixture.laptop
        let n = 3
        var windows = Fixture.windows(n, in: area)  // window 1 focused
        let first = try #require(engine.plan(LayoutContext(area: area, windows: windows), layout: layout))
        func apply(_ p: LayoutPlan) { for i in windows.indices { windows[i].frame = p.frames[windows[i].id]! } }
        apply(first)
        var states: [[WindowID: Rect]] = [first.frames]
        for _ in 0..<n {
            let p = try #require(engine.plan(LayoutContext(area: area, windows: windows), layout: layout, rotation: 1))
            apply(p)
            states.append(p.frames)
        }
        #expect(Set(states.prefix(n).map { $0.description }).count == n, "rotation did not visit \(n) states")
        #expect(states[n] == states[0], "n rotations must return to the start")
    }

    @Test("arranging twice is a no-op even with minimum sizes (randomised)")
    func idempotentWithMinimums() throws {
        var rng = SplitMix(seed: 42)
        var failures = 0
        for trial in 0..<400 {
            let (_, area) = Fixture.displays[trial % Fixture.displays.count]
            let n = 2 + trial % 5
            var windows = Fixture.windows(n, in: area, focused: trial % 3 == 0 ? nil : 1)
            let k = Int(rng.next() % UInt64(n))
            windows[k].minSize = Size(w: 300 + Double(rng.next() % 600), h: 200 + Double(rng.next() % 400))
            let layout = [LayoutID.columns, .rows, .masterStack, .grid][trial % 4]
            guard let first = engine.plan(LayoutContext(area: area, windows: windows), layout: layout),
                first.isFeasible
            else { continue }
            for i in windows.indices { windows[i].frame = first.frames[windows[i].id]! }
            let second = try #require(engine.plan(LayoutContext(area: area, windows: windows), layout: layout))
            if second.frames != first.frames { failures += 1 }
        }
        #expect(failures == 0)
    }

    @Test("cycling from a forced, non-candidate layout returns to the candidates")
    func cycleFromForcedLayout() throws {
        let plan = try #require(
            engine.plan(
                LayoutContext(area: Fixture.laptop, windows: Fixture.windows(4, in: Fixture.laptop)), layout: .rows))
        #expect(plan.layout == .rows)
        #expect(plan.nextLayout == plan.candidates.first)
        #expect(plan.previousLayout == plan.candidates.last)
    }

    @Test("grid shape scored is the grid shape built", arguments: 2...16)
    func gridScoredMatchesBuilt(n: Int) {
        let s = Strategies(prefs: LayoutPreferences())
        for (_, area) in Fixture.displays {
            let (cols, rows) = s.gridDimensions(count: n, area: area)
            let tree = s.gridTree(count: n, cols: cols, rows: rows)
            guard case .split(.vertical, let rowNodes, _) = tree else {
                #expect(rows == 1)
                continue
            }
            #expect(rowNodes.count == rows)
            #expect(rowNodes.map(\.leafCount).max() == cols)
        }
    }
}

/// Small deterministic PRNG for reproducible randomised tests.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
