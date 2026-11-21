import AppKit
import SwiftUI

/// Small capsule near the top of the active screen that confirms what happened.
@MainActor
final class HUD {
    private var panel: NSPanel?
    private var generation = 0

    func show(_ text: String, duration: TimeInterval = 1.8) {
        generation += 1
        let current = generation
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: HUDView(text: text))
        panel.contentView = hosting
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let v = screen?.visibleFrame {
            panel.setFrame(
                NSRect(
                    x: v.midX - size.width / 2, y: v.maxY - size.height - 24,
                    width: size.width, height: size.height), display: true)
        }
        // A zero-length animation replaces any fade-out still in flight.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                NSAnimationContext.runAnimationGroup(
                    { ctx in
                        ctx.duration = 0.25
                        self.panel?.animator().alphaValue = 0
                    },
                    completionHandler: {
                        MainActor.assumeIsolated {
                            if self.generation == current { self.panel?.orderOut(nil) }
                        }
                    })
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

private struct HUDView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .modifier(CapsuleBackground())
            .padding(8)
    }
}

private struct CapsuleBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
    }
}
