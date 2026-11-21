import Testing

@testable import Geometry

@Suite("Rect")
struct RectTests {
    @Test func flipIsItsOwnInverse() {
        let r = Rect(x: 10, y: 20, w: 300, h: 200)
        #expect(r.flippedVertically(primaryHeight: 1117).flippedVertically(primaryHeight: 1117) == r)
    }

    @Test func flipMapsAppKitToQuartz() {
        // Primary 1512x982. A window whose AppKit frame sits on the bottom edge
        // must end at Quartz y == 982.
        let appKit = Rect(x: 0, y: 0, w: 400, h: 300)
        let quartz = appKit.flippedVertically(primaryHeight: 982)
        #expect(quartz == Rect(x: 0, y: 682, w: 400, h: 300))
    }

    @Test func flipHandlesDisplayAbovePrimary() {
        // Secondary display stacked above the primary: AppKit y > primary height,
        // Quartz y becomes negative.
        let secondary = Rect(x: 0, y: 982, w: 1920, h: 1080)
        #expect(secondary.flippedVertically(primaryHeight: 982) == Rect(x: 0, y: -1080, w: 1920, h: 1080))
    }

    @Test func insetNeverGoesNegative() {
        let r = Rect(x: 0, y: 0, w: 10, h: 10).inset(by: Insets(all: 20))
        #expect(r.w == 0 && r.h == 0)
    }

    @Test func intersectionAndOverlap() {
        let a = Rect(x: 0, y: 0, w: 100, h: 100)
        let b = Rect(x: 50, y: 50, w: 100, h: 100)
        let c = Rect(x: 100, y: 0, w: 100, h: 100)
        #expect(a.intersection(b) == Rect(x: 50, y: 50, w: 50, h: 50))
        #expect(a.overlaps(b))
        #expect(!a.overlaps(c))  // touching edges is not overlap
    }

    @Test func centeredClampsIntoBounds() {
        let bounds = Rect(x: 0, y: 0, w: 1000, h: 800)
        let slot = Rect(x: 900, y: 0, w: 100, h: 100)
        let r = slot.centered(size: Size(w: 300, h: 200), clampedTo: bounds)
        #expect(r.maxX <= bounds.maxX + 0.001)
        #expect(r.minY >= bounds.minY - 0.001)
        #expect(r.w == 300 && r.h == 200)
    }
}
