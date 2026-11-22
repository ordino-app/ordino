import Foundation
import Testing

@testable import LayoutEngine

@Suite struct AutomationURLTests {
    private func parse(_ s: String) -> AutomationURL? { URL(string: s).flatMap(AutomationURL.init) }

    @Test func arrangeAndRecent() {
        #expect(parse("ordino://arrange") == .arrange(recent: nil))
        #expect(parse("ordino://arrange?recent=2") == .arrange(recent: 2))
    }

    @Test func layoutsAndActionsIgnoreCase() {
        #expect(parse("ordino://layout/Columns") == .layout(.columns))
        #expect(parse("ordino://window/lefthalf") == .window(.leftHalf))
        #expect(parse("ordino://undo") == .undo)
    }

    @Test func namesArePercentDecoded() {
        #expect(parse("ordino://workspace/Coding") == .workspace("Coding"))
        #expect(parse("ordino://custom/3%20Columns") == .custom("3 Columns"))
    }

    @Test func unknownLinksAreRejected() {
        #expect(parse("ordino://layout/nope") == nil)
        #expect(parse("https://arrange") == nil)
        #expect(parse("ordino://whatever") == nil)
    }
}
