import Geometry
import Testing

@testable import LayoutEngine

@Suite struct FreeAreaTests {
    let area = Rect(x: 0, y: 25, w: 1440, h: 850)

    @Test func rightHalfRuleLeavesTheLeftHalf() {
        let ruled = Rect(x: 720, y: 25, w: 720, h: 850)
        #expect(FreeArea.largest(in: area, avoiding: [ruled]) == Rect(x: 0, y: 25, w: 720, h: 850))
    }

    @Test func cornerRuleLeavesTheBiggestStrip() {
        // A bottom-right quarter: the full-height strip on the left beats the full-width strip above.
        let ruled = Rect(x: 720, y: 450, w: 720, h: 425)
        #expect(FreeArea.largest(in: area, avoiding: [ruled]) == Rect(x: 0, y: 25, w: 720, h: 850))
    }

    @Test func twoRulesShrinkTwice() {
        let right = Rect(x: 960, y: 25, w: 480, h: 850)
        let left = Rect(x: 0, y: 25, w: 480, h: 850)
        #expect(FreeArea.largest(in: area, avoiding: [right, left]) == Rect(x: 480, y: 25, w: 480, h: 850))
    }

    @Test func noOverlapKeepsTheArea() {
        #expect(FreeArea.largest(in: area, avoiding: [Rect(x: 2000, y: 0, w: 100, h: 100)]) == area)
    }
}
