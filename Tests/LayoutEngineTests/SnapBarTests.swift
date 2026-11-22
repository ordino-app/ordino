import Geometry
import Testing

@testable import LayoutEngine

@Suite struct SnapBarTests {
    let visible = Rect(x: 0, y: 25, w: 1440, h: 850)

    @Test func barIsCentredBelowTheMenuBar() {
        let bar = SnapBar.frame(in: visible)
        #expect(abs(bar.x + bar.w / 2 - 720) < 0.5)
        #expect(bar.y == 33)
    }

    @Test func hoveringCellsPicksTheirPlacement() {
        let bar = SnapBar.frame(in: visible)
        let halves = SnapBar.groupFrame(0, in: bar)
        #expect(SnapBar.hit(x: halves.x + 5, y: halves.y + 20, bar: bar)?.cell.action == .leftHalf)
        #expect(SnapBar.hit(x: halves.x + halves.w - 5, y: halves.y + 20, bar: bar)?.cell.action == .rightHalf)
        let quarters = SnapBar.groupFrame(4, in: bar)
        #expect(
            SnapBar.hit(x: quarters.x + quarters.w - 3, y: quarters.y + quarters.h - 3, bar: bar)?.cell.action
                == .bottomRight)
        let last = SnapBar.groupFrame(SnapBar.groups.count - 1, in: bar)
        #expect(SnapBar.hit(x: last.x + 30, y: last.y + 20, bar: bar)?.cell.action == .maximize)
    }

    @Test func gapsAndOutsideHitNothing() {
        let bar = SnapBar.frame(in: visible)
        let first = SnapBar.groupFrame(0, in: bar)
        #expect(SnapBar.hit(x: first.x + first.w + SnapBar.gap / 2, y: first.y + 10, bar: bar) == nil)
        #expect(SnapBar.hit(x: 5, y: 500, bar: bar) == nil)
    }

    @Test func barAppearsOnlyNearTheTop() {
        #expect(SnapBar.isShown(cursorY: 100, visible: visible))
        #expect(!SnapBar.isShown(cursorY: 400, visible: visible))
    }

    @Test func portraitDisplaysOfferTopAndBottomHalves() {
        let bar = SnapBar.frame(in: Rect(x: 0, y: 25, w: 1080, h: 1895))
        let halves = SnapBar.groupFrame(0, in: bar)
        #expect(SnapBar.hit(x: halves.midX, y: halves.y + 5, bar: bar, portrait: true)?.cell.action == .topHalf)
        #expect(SnapBar.hit(x: halves.midX, y: halves.maxY - 5, bar: bar, portrait: true)?.cell.action == .bottomHalf)
        let thirds = SnapBar.groupFrame(1, in: bar)
        #expect(SnapBar.hit(x: thirds.midX, y: thirds.maxY - 3, bar: bar, portrait: true)?.cell.action == .lastThird)
    }

    @Test func thirdsAreRowsOnPortraitDisplays() {
        let engine = WindowActionEngine()
        let tall = Rect(x: 0, y: 0, w: 1080, h: 1920)
        let f = engine.frame(for: .firstThird, window: .zero, area: tall)
        #expect(f?.w == 1080)
        #expect((f?.h ?? 0) < 700)
    }
}
