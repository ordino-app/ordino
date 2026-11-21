import Foundation
import Geometry

/// Decides which window goes into which slot.
///
/// Rule: the focused window takes the master slot (if the layout has one);
/// everyone else is placed so that the total "disruption" is minimal: windows
/// stay close to where they were, keep a similar shape, and avoid slots that
/// are smaller than their minimum size. Ties are broken by window ID, so the
/// result does not depend on z-order and pressing the hotkey twice is a no-op.
struct SlotAssigner {
    let focusedIsMaster: Bool

    /// - Returns: `result[slotIndex] = index into windows`.
    func assign(windows: [WindowInfo], slots: [Rect], roles: [SlotRole], area: Rect) -> [Int] {
        precondition(windows.count == slots.count && slots.count == roles.count)
        let n = windows.count
        guard n > 0 else { return [] }

        var slotToWindow = Array(repeating: -1, count: n)
        var freeSlots = Array(0..<n)
        // Deterministic order independent of z-order.
        var freeWindows = (0..<n).sorted { windows[$0].id < windows[$1].id }

        if focusedIsMaster,
            let masterSlot = roles.firstIndex(of: .master),
            let focused = windows.firstIndex(where: \.isFocused)
        {
            slotToWindow[masterSlot] = focused
            freeSlots.removeAll { $0 == masterSlot }
            freeWindows.removeAll { $0 == focused }
        }

        let diag = max(1, area.diagonal)
        func cost(_ w: Int, _ s: Int) -> Double {
            let win = windows[w]
            let slot = slots[s]
            let dx = win.frame.midX - slot.midX
            let dy = win.frame.midY - slot.midY
            var c = (dx * dx + dy * dy).squareRoot() / diag
            if win.frame.aspect > 0, slot.aspect > 0 {
                c += 0.3 * abs(log(win.frame.aspect / slot.aspect))
            }
            if let m = win.minSize {
                c += 2 * (max(0, (m.w - slot.w) / max(1, slot.w)) + max(0, (m.h - slot.h) / max(1, slot.h)))
            }
            return c
        }

        let matching =
            freeWindows.count <= 12
            ? optimalMatching(windows: freeWindows, slots: freeSlots, cost: cost)
            : greedyMatching(windows: freeWindows, slots: freeSlots, cost: cost)
        for (w, s) in matching { slotToWindow[s] = w }
        return slotToWindow
    }

    /// Exact minimum-cost matching by DP over subsets of slots: O(n^2 * 2^n).
    private func optimalMatching(windows: [Int], slots: [Int], cost: (Int, Int) -> Double) -> [(Int, Int)] {
        let n = windows.count
        guard n > 0 else { return [] }
        let full = (1 << n) - 1
        var best = Array(repeating: Double.infinity, count: 1 << n)
        var choice = Array(repeating: -1, count: 1 << n)
        best[0] = 0
        // best[mask]: cost of assigning the first popcount(mask) windows to the slots in mask.
        for mask in 0..<full where best[mask] < .infinity {
            let w = mask.nonzeroBitCount
            for s in 0..<n where mask & (1 << s) == 0 {
                let next = mask | (1 << s)
                let c = best[mask] + cost(windows[w], slots[s])
                if c < best[next] - 1e-12 {
                    best[next] = c
                    choice[next] = s
                }
            }
        }
        var result: [(Int, Int)] = []
        var mask = full
        while mask != 0 {
            let s = choice[mask]
            let w = mask.nonzeroBitCount - 1
            result.append((windows[w], slots[s]))
            mask &= ~(1 << s)
        }
        return result
    }

    private func greedyMatching(windows: [Int], slots: [Int], cost: (Int, Int) -> Double) -> [(Int, Int)] {
        var remaining = slots
        var result: [(Int, Int)] = []
        for w in windows {
            guard let s = remaining.min(by: { cost(w, $0) < cost(w, $1) }) else { break }
            result.append((w, s))
            remaining.removeAll { $0 == s }
        }
        return result
    }
}
