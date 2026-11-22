import Geometry
import Testing

@testable import LayoutEngine

@Suite struct GridLayoutTests {
    @Test func threeColumnsOnUltrawide() {
        let f = GridLayout.frames(in: Rect(x: 0, y: 25, w: 3440, h: 1390), columns: 3, rows: 1, gap: 10)
        #expect(f.count == 3)
        #expect(abs(f[0].w - 1140) < 0.001)
        #expect(abs(f[1].x - 1150) < 0.001)
        #expect(abs(f[2].x + f[2].w - 3440) < 0.001)
    }

    @Test func rowsComeAfterColumns() {
        let f = GridLayout.frames(in: Rect(x: 0, y: 0, w: 100, h: 100), columns: 2, rows: 2)
        #expect(f.map(\.x) == [0, 50, 0, 50])
        #expect(f.map(\.y) == [0, 0, 50, 50])
    }
}
