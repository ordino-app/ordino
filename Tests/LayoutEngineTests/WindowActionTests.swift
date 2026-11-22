import Foundation
import Geometry
import Testing

@testable import LayoutEngine

private let offsetArea = Rect(x: -1920, y: -300, w: 1920, h: 1055)
private let actionAreas: [Rect] = Fixture.displays.map(\.1) + [offsetArea]
private let gaps: [Double] = [0, 8]
private let sampleWindow = Rect(x: 200, y: 150, w: 800, h: 600)
private let eps = 1e-6

private func window(in area: Rect) -> Rect {
    Rect(x: area.x + 120, y: area.y + 90, w: min(800, area.w / 2), h: min(600, area.h / 2))
}

private func frames(_ actions: [WindowAction], _ engine: WindowActionEngine, _ area: Rect) -> [Rect] {
    actions.map { engine.frame(for: $0, window: window(in: area), area: area)! }
}

/// No pair overlaps, and together they cover exactly `area.area - expectedGapArea`.
private func expectTiles(_ rects: [Rect], area: Rect, gapArea: Double) {
    for i in rects.indices {
        for j in rects.indices where j > i {
            #expect(!rects[i].overlaps(rects[j], tolerance: eps), "\(rects[i]) overlaps \(rects[j])")
        }
    }
    let total = rects.reduce(0) { $0 + $1.area }
    #expect(abs(total + gapArea - area.area) < 1e-3)
}

@Suite("WindowAction metadata")
struct WindowActionMetadataTests {
    @Test func everyCaseHasTitleAndGroup() {
        for action in WindowAction.allCases {
            #expect(!action.title.isEmpty)
            #expect(action.id == action.rawValue)
            #expect(WindowAction.Group.allCases.contains(action.group))
        }
        #expect(Set(WindowAction.allCases.map(\.title)).count == WindowAction.allCases.count)
        #expect(WindowAction.center.title == "Move to Center")
    }

    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(WindowAction.allCases)
        #expect(try JSONDecoder().decode([WindowAction].self, from: data) == WindowAction.allCases)
    }

    @Test func unitRectNilForFreeformActions() {
        let free: [WindowAction] = [
            .larger, .smaller, .center, .moveLeft, .moveRight, .moveUp, .moveDown, .restore, .nextDisplay,
            .previousDisplay,
        ]
        for action in WindowAction.allCases {
            #expect((action.unitRect == nil) == free.contains(action), "\(action)")
        }
    }

    @Test func unitRectMatchesFrameOnUnitArea() {
        let engine = WindowActionEngine()
        let unit = Rect(x: 0, y: 0, w: 1, h: 1)
        for action in WindowAction.allCases {
            guard let u = action.unitRect else { continue }
            let w = action == .maximizeHeight ? Rect(x: 0.25, y: 0.3, w: 0.5, h: 0.2) : Rect(x: 0, y: 0, w: 0.1, h: 0.1)
            let f = engine.frame(for: action, window: w, area: unit)!
            #expect(f.isApproximately(u, tolerance: eps), "\(action): \(f) vs \(u)")
            #expect(unit.contains(u, tolerance: eps))
        }
    }
}

@Suite("WindowActionEngine")
struct WindowActionEngineTests {
    @Test func callerHandledActionsReturnNil() {
        let engine = WindowActionEngine()
        for action in [WindowAction.restore, .nextDisplay, .previousDisplay] {
            #expect(engine.frame(for: action, window: sampleWindow, area: Fixture.laptop) == nil)
        }
    }

    @Test func everyResultInsideArea() {
        for area in actionAreas {
            for gap in gaps {
                for padding in [Insets.zero, Insets(all: 10)] {
                    let engine = WindowActionEngine(gap: gap, outerPadding: padding)
                    let usable = area.inset(by: padding)
                    let windows = [
                        window(in: area), Rect(x: area.x - 500, y: area.y - 400, w: area.w * 2, h: area.h * 2),
                        Rect(x: area.maxX - 50, y: area.maxY - 50, w: 400, h: 300),
                    ]
                    for w in windows {
                        for action in WindowAction.allCases {
                            for rep in 0..<4 {
                                guard let f = engine.frame(for: action, window: w, area: area, repeatCount: rep)
                                else { continue }
                                #expect(usable.contains(f, tolerance: eps), "\(action) \(f) not in \(usable)")
                                #expect(f.w > 0 && f.h > 0)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func tilingGroupsTileWithExactGaps() {
        for area in actionAreas {
            for gap in gaps {
                let e = WindowActionEngine(gap: gap)
                // Columns: n columns -> (n-1) vertical gaps of full height.
                let lr = frames([.leftHalf, .rightHalf], e, area)
                expectTiles(lr, area: area, gapArea: gap * area.h)
                #expect(abs(lr[1].minX - lr[0].maxX - gap) < eps)
                #expect(abs(lr[0].minX - area.minX) < eps && abs(lr[1].maxX - area.maxX) < eps)

                let tb = frames([.topHalf, .bottomHalf], e, area)
                expectTiles(tb, area: area, gapArea: gap * area.w)
                #expect(abs(tb[1].minY - tb[0].maxY - gap) < eps)

                let thirds = frames([.firstThird, .centerThird, .lastThird], e, area)
                expectTiles(thirds, area: area, gapArea: 2 * gap * area.h)
                for i in 1..<3 { #expect(abs(thirds[i].minX - thirds[i - 1].maxX - gap) < eps) }

                expectTiles(frames([.firstTwoThirds, .lastThird], e, area), area: area, gapArea: gap * area.h)
                expectTiles(frames([.firstThird, .lastTwoThirds], e, area), area: area, gapArea: gap * area.h)

                let fourths = frames([.firstFourth, .secondFourth, .thirdFourth, .lastFourth], e, area)
                expectTiles(fourths, area: area, gapArea: 3 * gap * area.h)
                for i in 1..<4 { #expect(abs(fourths[i].minX - fourths[i - 1].maxX - gap) < eps) }
                expectTiles(frames([.firstThreeFourths, .lastFourth], e, area), area: area, gapArea: gap * area.h)
                expectTiles(frames([.firstFourth, .lastThreeFourths], e, area), area: area, gapArea: gap * area.h)

                // Grids: gap area = vertical lines + horizontal lines - crossings.
                let corners = frames([.topLeft, .topRight, .bottomLeft, .bottomRight], e, area)
                expectTiles(corners, area: area, gapArea: gap * area.h + gap * area.w - gap * gap)

                let sixths = frames(
                    [
                        .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth,
                        .bottomRightSixth,
                    ], e, area)
                expectTiles(sixths, area: area, gapArea: 2 * gap * area.h + gap * area.w - 2 * gap * gap)
                // Middle column loses gap/2 on both inner edges; outer columns only on one.
                for (i, s) in sixths.enumerated() {
                    let expectedW = (area.w - 2 * gap) / 3 + (i % 3 == 1 ? -gap / 3 : gap / 6)
                    #expect(abs(s.w - expectedW) < eps && abs(s.h - (area.h - gap) / 2) < eps)
                }
            }
        }
    }

    @Test func centeredRegions() {
        for area in actionAreas {
            let e = WindowActionEngine()
            let w = window(in: area)
            let ch = e.frame(for: .centerHalf, window: w, area: area)!
            #expect(
                ch.isApproximately(Rect(x: area.x + area.w / 4, y: area.y, w: area.w / 2, h: area.h), tolerance: eps))
            let c2 = e.frame(for: .centerTwoThirds, window: w, area: area)!
            #expect(abs(c2.w - area.w * 2 / 3) < eps && abs(c2.midX - area.midX) < eps)
            #expect(e.frame(for: .maximize, window: w, area: area)!.isApproximately(area, tolerance: eps))
            let am = e.frame(for: .almostMaximize, window: w, area: area)!
            #expect(abs(am.w - area.w * 0.9) < eps && abs(am.h - area.h * 0.9) < eps)
            #expect(abs(am.midX - area.midX) < eps && abs(am.midY - area.midY) < eps)
            let mh = e.frame(for: .maximizeHeight, window: w, area: area)!
            #expect(mh.x == w.x && mh.w == w.w && mh.y == area.y && mh.h == area.h)
        }
    }

    @Test func outerPaddingIsRespected() {
        let pad = Insets(top: 5, left: 10, bottom: 15, right: 20)
        let e = WindowActionEngine(outerPadding: pad)
        let f = e.frame(for: .maximize, window: sampleWindow, area: Fixture.laptop)!
        #expect(f.isApproximately(Fixture.laptop.inset(by: pad), tolerance: eps))
    }

    @Test func halvesCycleOnRepeat() {
        for area in actionAreas {
            for gap in gaps {
                let e = WindowActionEngine(gap: gap)
                let w = window(in: area)
                let expected = [1.0 / 2, 2.0 / 3, 1.0 / 3, 1.0 / 2, 2.0 / 3]
                for (rep, f) in expected.enumerated() {
                    let l = e.frame(for: .leftHalf, window: w, area: area, repeatCount: rep)!
                    let r = e.frame(for: .rightHalf, window: w, area: area, repeatCount: rep)!
                    let t = e.frame(for: .topHalf, window: w, area: area, repeatCount: rep)!
                    let b = e.frame(for: .bottomHalf, window: w, area: area, repeatCount: rep)!
                    #expect(abs(l.w - (area.w * f - gap / 2)) < eps && abs(l.minX - area.minX) < eps)
                    #expect(abs(r.w - (area.w * f - gap / 2)) < eps && abs(r.maxX - area.maxX) < eps)
                    #expect(abs(t.h - (area.h * f - gap / 2)) < eps && abs(t.minY - area.minY) < eps)
                    #expect(abs(b.h - (area.h * f - gap / 2)) < eps && abs(b.maxY - area.maxY) < eps)
                    #expect(l.h == area.h && t.w == area.w)
                }
                // Non-halves ignore repeatCount.
                let a0 = e.frame(for: .firstThird, window: w, area: area, repeatCount: 0)
                let a1 = e.frame(for: .firstThird, window: w, area: area, repeatCount: 1)
                #expect(a0 == a1)
            }
        }
    }

    @Test func moveKeepsSizeAndSnapsToEdge() {
        for area in actionAreas {
            let e = WindowActionEngine(gap: 8)
            let w = window(in: area)
            let l = e.frame(for: .moveLeft, window: w, area: area)!
            let r = e.frame(for: .moveRight, window: w, area: area)!
            let u = e.frame(for: .moveUp, window: w, area: area)!
            let d = e.frame(for: .moveDown, window: w, area: area)!
            for f in [l, r, u, d] { #expect(f.size == w.size) }
            #expect(l.minX == area.minX && l.y == w.y)
            #expect(abs(r.maxX - area.maxX) < eps && r.y == w.y)
            #expect(u.minY == area.minY && u.x == w.x)
            #expect(abs(d.maxY - area.maxY) < eps && d.x == w.x)
            // Oversized windows are clamped to the area.
            let big = Rect(x: area.x - 100, y: area.y - 100, w: area.w + 300, h: area.h + 300)
            let bl = e.frame(for: .moveLeft, window: big, area: area)!
            #expect(bl.isApproximately(area, tolerance: eps))
        }
    }

    @Test func centerKeepsSize() {
        for area in actionAreas {
            let e = WindowActionEngine()
            let w = window(in: area)
            let c = e.frame(for: .center, window: w, area: area)!
            #expect(c.size == w.size)
            #expect(abs(c.midX - area.midX) < eps && abs(c.midY - area.midY) < eps)
            let big = Rect(x: 0, y: 0, w: area.w * 3, h: area.h * 3)
            #expect(e.frame(for: .center, window: big, area: area)!.isApproximately(area, tolerance: eps))
        }
    }

    @Test func largerThenSmallerRoundTrips() {
        for area in actionAreas {
            let e = WindowActionEngine()
            let w = Rect(x: area.midX - 300, y: area.midY - 200, w: 600, h: 400)
            let big = e.frame(for: .larger, window: w, area: area)!
            #expect(abs(big.w - (w.w + 64)) < eps && abs(big.h - (w.h + 64)) < eps)
            #expect(abs(big.midX - w.midX) < eps && abs(big.midY - w.midY) < eps)
            let back = e.frame(for: .smaller, window: big, area: area)!
            #expect(back.isApproximately(w, tolerance: 1))
        }
    }

    @Test func largerIsClampedToArea() {
        let area = Fixture.laptop
        let e = WindowActionEngine()
        var w = Rect(x: area.x, y: area.y, w: 400, h: 300)
        for _ in 0..<100 { w = e.frame(for: .larger, window: w, area: area)! }
        #expect(w.isApproximately(area, tolerance: eps))
    }

    @Test func smallerRespectsMinimum() {
        let area = Fixture.external
        let e = WindowActionEngine(minimumSize: Size(w: 320, h: 220))
        var w = Rect(x: area.x + 500, y: area.y + 300, w: 900, h: 700)
        for _ in 0..<50 { w = e.frame(for: .smaller, window: w, area: area)! }
        #expect(w.w == 320 && w.h == 220)
        // A window already below the minimum is never grown.
        let tiny = Rect(x: area.x + 10, y: area.y + 10, w: 200, h: 150)
        let t = e.frame(for: .smaller, window: tiny, area: area)!
        #expect(t.size == tiny.size)
    }

    @Test func displayMappingIsProportional() {
        let e = WindowActionEngine()
        let src = Fixture.laptop
        let dst = Fixture.external
        let w = Rect(x: src.x + src.w * 0.1, y: src.y + src.h * 0.2, w: src.w * 0.5, h: src.h * 0.4)
        let m = e.frame(movingWindow: w, from: src, to: dst)
        let expected = Rect(x: dst.x + dst.w * 0.1, y: dst.y + dst.h * 0.2, w: dst.w * 0.5, h: dst.h * 0.4)
        #expect(m.isApproximately(expected, tolerance: 1e-3))
        // Round trip.
        #expect(e.frame(movingWindow: m, from: dst, to: src).isApproximately(w, tolerance: 1e-3))
    }

    @Test func displayMappingMaximized() {
        let e = WindowActionEngine(outerPadding: Insets(all: 8))
        let src = Fixture.laptop
        let dst = Fixture.ultrawide
        let filling = src.inset(by: Insets(all: 10))
        #expect(e.frame(movingWindow: filling, from: src, to: dst) == dst.inset(by: Insets(all: 8)))
    }

    @Test func displayMappingClamps() {
        let e = WindowActionEngine()
        for (src, dst) in [(Fixture.ultrawide, Fixture.portrait), (Fixture.portrait, offsetArea)] {
            let windows = [
                Rect(x: src.maxX - 100, y: src.maxY - 50, w: 900, h: 700),
                Rect(x: src.x - 400, y: src.y - 300, w: src.w * 0.5, h: src.h * 0.5),
                Rect(x: src.x, y: src.y, w: src.w * 2, h: 100),
            ]
            for w in windows {
                let m = e.frame(movingWindow: w, from: src, to: dst)
                #expect(dst.contains(m, tolerance: eps), "\(m) not in \(dst)")
            }
        }
    }
}
