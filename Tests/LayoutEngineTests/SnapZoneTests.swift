import Geometry
import Testing

@testable import LayoutEngine

@Suite struct SnapZoneTests {
    let screen = Rect(x: 0, y: 0, w: 1440, h: 900)

    @Test func edgesSnapToHalvesAndMaximize() {
        #expect(SnapZone.action(x: 2, y: 450, in: screen) == .leftHalf)
        #expect(SnapZone.action(x: 1438, y: 450, in: screen) == .rightHalf)
        #expect(SnapZone.action(x: 720, y: 1, in: screen) == .maximize)
    }

    @Test func cornersWinOverEdges() {
        #expect(SnapZone.action(x: 1, y: 20, in: screen) == .topLeft)
        // A title bar dragged along the left edge near the top is a half, not a corner.
        #expect(SnapZone.action(x: 1, y: 45, in: screen) == .leftHalf)
        #expect(SnapZone.action(x: 20, y: 2, in: screen) == .topLeft)
        #expect(SnapZone.action(x: 1439, y: 885, in: screen) == .bottomRight)
        #expect(SnapZone.action(x: 1420, y: 899, in: screen) == .bottomRight)
    }

    @Test func middleAndBottomEdgeDoNothing() {
        #expect(SnapZone.action(x: 720, y: 450, in: screen) == nil)
        #expect(SnapZone.action(x: 720, y: 899, in: screen) == nil)
    }

    @Test func secondDisplayUsesItsOwnFrame() {
        let right = Rect(x: 1440, y: -200, w: 1920, h: 1080)
        #expect(SnapZone.action(x: 1442, y: 300, in: right) == .leftHalf)
        #expect(SnapZone.action(x: 2400, y: -199, in: right) == .maximize)
    }

    @Test func edgesSharedWithAnotherDisplayDontSnap() {
        let right = Rect(x: 1440, y: 0, w: 1920, h: 1080)
        // Moving across into the right display: the shared edge is a doorway on both sides.
        #expect(SnapZone.action(x: 1438, y: 450, in: screen, others: [right]) == nil)
        #expect(SnapZone.action(x: 1442, y: 450, in: right, others: [screen]) == nil)
        // The outer edges still snap.
        #expect(SnapZone.action(x: 2, y: 450, in: screen, others: [right]) == .leftHalf)
        #expect(SnapZone.action(x: 3358, y: 450, in: right, others: [screen]) == .rightHalf)
    }
}
