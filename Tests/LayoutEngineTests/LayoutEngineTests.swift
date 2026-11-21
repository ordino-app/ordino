import Geometry
import Testing

@testable import LayoutEngine

private let engine = LayoutEngine()
private let prefs = LayoutPreferences()

// MARK: - Invariants for every layout, count and display

@Suite("Invariants")
struct InvariantTests {
    static let cases: [(String, Rect, Int, LayoutID)] = Fixture.displays.flatMap { name, area in
        (1...9).flatMap { n in
            LayoutID.allCases.filter { $0.supports(count: n) }.map { (name, area, n, $0) }
        }
    }

    @Test(
        "every window gets a frame, inside the area, without overlap",
        arguments: cases.indices)
    func framesAreValid(_ i: Int) throws {
        let (_, area, n, layout) = Self.cases[i]
        let ctx = LayoutContext(area: area, windows: Fixture.windows(n, in: area))
        let plan = try #require(engine.plan(ctx, layout: layout))
        let usable = area.inset(by: prefs.outerPadding)

        #expect(plan.layout == layout)
        #expect(plan.frames.count == n)
        #expect(plan.isFeasible)
        let frames = plan.sortedFrames
        for f in frames {
            #expect(usable.contains(f, tolerance: 0.01), "\(f) outside \(usable)")
            #expect(f.w > 0 && f.h > 0)
        }
        for a in 0..<frames.count {
            for b in (a + 1)..<frames.count {
                #expect(!frames[a].overlaps(frames[b], tolerance: 0.01), "\(frames[a]) overlaps \(frames[b])")
            }
        }
    }

    @Test(
        "tiling layouts cover the whole usable area minus gaps",
        arguments: Fixture.displays.map(\.1), [2, 3, 4, 6])
    func coverage(area: Rect, n: Int) throws {
        for layout in [LayoutID.columns, .rows, .masterStack, .bsp] where layout.supports(count: n) {
            let plan = try #require(
                engine.plan(LayoutContext(area: area, windows: Fixture.windows(n, in: area)), layout: layout))
            let usable = area.inset(by: prefs.outerPadding)
            let covered = plan.frames.values.reduce(0) { $0 + $1.area }
            #expect(covered <= usable.area + 0.5)
            // At most n gap strips, each no longer than the long side, are lost to gaps.
            let maxGapArea = prefs.gap * Double(n) * max(usable.w, usable.h)
            #expect(covered >= usable.area - maxGapArea, "\(layout) n=\(n) covers only \(covered / usable.area)")
        }
    }

    @Test("gaps between neighbours equal the preference")
    func gapIsExact() throws {
        let area = Fixture.laptop
        let plan = try #require(
            engine.plan(LayoutContext(area: area, windows: Fixture.windows(2, in: area)), layout: .columns))
        let f = plan.frames.values.sorted { $0.x < $1.x }
        #expect(abs(f[1].minX - f[0].maxX - prefs.gap) < 0.001)
    }

    @Test("no windows -> no plan")
    func empty() {
        #expect(engine.plan(LayoutContext(area: Fixture.laptop, windows: [])) == nil)
    }
}

// MARK: - The default table (single source of truth, see Strategies.candidates)

@Suite("Smart defaults")
struct DefaultTests {
    @Test(arguments: [
        (1, LayoutID.maximize), (2, .columns), (3, .masterStack), (4, .grid),
        (5, .grid), (6, .grid), (7, .grid), (9, .grid),
    ])
    func landscape(n: Int, expected: LayoutID) {
        #expect(engine.candidates(count: n, area: Fixture.laptop).first == expected)
    }

    @Test(arguments: [(1, LayoutID.centered), (2, .columns), (3, .columns), (4, .columns), (6, .grid)])
    func ultrawide(n: Int, expected: LayoutID) {
        #expect(engine.candidates(count: n, area: Fixture.ultrawide).first == expected)
    }

    @Test(arguments: [(2, LayoutID.rows), (3, .rows), (4, .grid)])
    func portrait(n: Int, expected: LayoutID) {
        #expect(engine.candidates(count: n, area: Fixture.portrait).first == expected)
    }

    @Test func fourWindowsOnLaptopIsTwoByTwo() throws {
        let plan = try #require(
            engine.plan(LayoutContext(area: Fixture.laptop, windows: Fixture.windows(4, in: Fixture.laptop))))
        let xs = Set(plan.frames.values.map { Int($0.x.rounded()) })
        let ys = Set(plan.frames.values.map { Int($0.y.rounded()) })
        #expect(xs.count == 2 && ys.count == 2)
    }

    @Test func sixWindowsOnLaptopIsThreeByTwo() throws {
        let plan = try #require(
            engine.plan(LayoutContext(area: Fixture.laptop, windows: Fixture.windows(6, in: Fixture.laptop))))
        let xs = Set(plan.frames.values.map { Int($0.x.rounded()) })
        let ys = Set(plan.frames.values.map { Int($0.y.rounded()) })
        #expect(xs.count == 3 && ys.count == 2)
    }

    @Test("7 windows spread 3-2-2, never a lonely last row")
    func sevenSpreadsEvenly() throws {
        let plan = try #require(
            engine.plan(LayoutContext(area: Fixture.external, windows: Fixture.windows(7, in: Fixture.external))))
        var perRow: [Int: Int] = [:]
        for f in plan.frames.values { perRow[Int(f.y.rounded()), default: 0] += 1 }
        #expect(perRow.values.sorted() == [2, 2, 3])
    }

    @Test func candidatesAreUniqueAndSupported() {
        for (_, area) in Fixture.displays {
            for n in 1...12 {
                let c = engine.candidates(count: n, area: area)
                #expect(!c.isEmpty)
                #expect(Set(c).count == c.count)
                #expect(c.allSatisfy { $0.supports(count: n) })
            }
        }
    }

    @Test func cyclingWrapsAround() throws {
        let plan = try #require(
            engine.plan(LayoutContext(area: Fixture.laptop, windows: Fixture.windows(4, in: Fixture.laptop))))
        var layout = plan.layout
        var seen: [LayoutID] = []
        for _ in plan.candidates {
            seen.append(layout)
            let next = try #require(
                engine.plan(
                    LayoutContext(area: Fixture.laptop, windows: Fixture.windows(4, in: Fixture.laptop)), layout: layout
                ))
            layout = next.nextLayout
        }
        #expect(seen == plan.candidates)
        #expect(layout == plan.layout)
        #expect(plan.previousLayout == plan.candidates.last)
    }

    @Test("unsupported forced layout falls back to the default")
    func forcedFallback() throws {
        let plan = try #require(
            engine.plan(
                LayoutContext(area: Fixture.laptop, windows: Fixture.windows(3, in: Fixture.laptop)), layout: .maximize)
        )
        #expect(plan.layout == .masterStack)
    }
}

// MARK: - Assignment

@Suite("Assignment")
struct AssignmentTests {
    @Test func focusedWindowBecomesMaster() throws {
        let area = Fixture.laptop
        let windows = Fixture.windows(3, in: area, focused: 3)
        let plan = try #require(engine.plan(LayoutContext(area: area, windows: windows), layout: .masterStack))
        let largest = try #require(plan.frames.max { $0.value.area < $1.value.area })
        #expect(largest.key == 3)
    }

    @Test(
        "arranging an already arranged screen changes nothing (idempotent)",
        arguments: [2, 3, 4, 5, 6, 8])
    func idempotent(n: Int) throws {
        let area = Fixture.external
        var windows = Fixture.windows(n, in: area)
        let first = try #require(engine.plan(LayoutContext(area: area, windows: windows)))
        for i in windows.indices { windows[i].frame = first.frames[windows[i].id]! }
        let second = try #require(engine.plan(LayoutContext(area: area, windows: windows), layout: first.layout))
        #expect(second.frames == first.frames)
    }

    @Test("result does not depend on z-order")
    func zOrderIndependent() throws {
        let area = Fixture.external
        let windows = Fixture.windows(5, in: area, focused: nil)
        let a = try #require(engine.plan(LayoutContext(area: area, windows: windows)))
        let b = try #require(engine.plan(LayoutContext(area: area, windows: windows.reversed())))
        #expect(a.frames == b.frames)
    }

    @Test("windows stay on their side: left window goes to a left slot")
    func minimalMovement() throws {
        let area = Fixture.laptop
        let left = WindowInfo(id: 10, frame: Rect(x: 0, y: 40, w: 700, h: 900))
        let right = WindowInfo(id: 20, frame: Rect(x: 800, y: 40, w: 700, h: 900))
        let plan = try #require(engine.plan(LayoutContext(area: area, windows: [right, left]), layout: .columns))
        #expect(plan.frames[10]!.x < plan.frames[20]!.x)
    }

    @Test func rotationShiftsEveryWindow() throws {
        let area = Fixture.laptop
        let ctx = LayoutContext(area: area, windows: Fixture.windows(3, in: area))
        let base = try #require(engine.plan(ctx, layout: .columns))
        let rotated = try #require(engine.plan(ctx, layout: .columns, rotation: 1))
        #expect(Set(base.frames.values) == Set(rotated.frames.values))
        for id in base.frames.keys { #expect(base.frames[id] != rotated.frames[id]) }
        let full = try #require(engine.plan(ctx, layout: .columns, rotation: 3))
        #expect(full.frames == base.frames)
    }

    @Test func extraWindowsAreLeftAlone() throws {
        var p = LayoutPreferences()
        p.maxWindows = 4
        let area = Fixture.external
        let plan = try #require(
            engine.plan(LayoutContext(area: area, windows: Fixture.windows(6, in: area), preferences: p)))
        #expect(plan.frames.count == 4)
        #expect(plan.unplaced == [5, 6])
    }
}

// MARK: - Minimum sizes and fixed windows

@Suite("Constraints")
struct ConstraintTests {
    @Test func minimumWidthIsHonouredAndNeighboursShrink() throws {
        let area = Fixture.laptop
        var windows = Fixture.windows(3, in: area, focused: nil)
        windows[0].minSize = Size(w: 700, h: 0)
        let plan = try #require(engine.plan(LayoutContext(area: area, windows: windows), layout: .columns))
        #expect(plan.isFeasible)
        #expect(plan.frames[1]!.w >= 700 - 0.001)
        let others = plan.frames.filter { $0.key != 1 }.map(\.value.w)
        #expect(others.allSatisfy { $0 < 700 })
        let usable = area.inset(by: LayoutPreferences().outerPadding)
        #expect(plan.frames.values.allSatisfy { usable.contains($0, tolerance: 0.01) })
    }

    @Test func windowWithBigMinimumAvoidsSmallSlot() throws {
        let area = Fixture.laptop
        var windows = Fixture.windows(3, in: area, focused: nil)
        windows[2].minSize = Size(w: 760, h: 0)  // only fits the master column
        let plan = try #require(engine.plan(LayoutContext(area: area, windows: windows), layout: .masterStack))
        let largest = try #require(plan.frames.max { $0.value.area < $1.value.area })
        #expect(largest.key == 3)
        #expect(plan.isFeasible)
    }

    @Test func impossibleMinimumsAreReported() throws {
        let area = Fixture.laptop
        var windows = Fixture.windows(3, in: area, focused: nil)
        for i in windows.indices { windows[i].minSize = Size(w: 800, h: 0) }
        let plan = try #require(engine.plan(LayoutContext(area: area, windows: windows), layout: .columns))
        #expect(!plan.isFeasible)
        #expect(plan.frames.count == 3)
    }

    @Test func fixedSizeWindowKeepsItsSize() throws {
        let area = Fixture.external
        var windows = Fixture.windows(4, in: area, focused: nil)
        windows[1].isResizable = false
        windows[1].frame = Rect(x: 0, y: 0, w: 500, h: 400)
        let plan = try #require(engine.plan(LayoutContext(area: area, windows: windows)))
        let f = plan.frames[2]!
        #expect(f.w == 500 && f.h == 400)
        #expect(area.contains(f, tolerance: 0.01))
    }

    @Test func distributeWaterFills() {
        let (shares, ok) = FrameSolver.distribute(900, weights: [1, 1, 1], mins: [500, 0, 0])
        #expect(ok)
        #expect(shares == [500, 200, 200])
    }

    @Test func distributeScalesWhenInfeasible() {
        let (shares, ok) = FrameSolver.distribute(900, weights: [1, 1], mins: [600, 600])
        #expect(!ok)
        #expect(abs(shares.reduce(0, +) - 900) < 0.001)
    }
}
