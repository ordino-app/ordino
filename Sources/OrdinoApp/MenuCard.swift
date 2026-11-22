import ArrangeCore
import Geometry
import LayoutEngine
import SwiftUI

/// State of the arrange card at the top of the menu.
@MainActor
@Observable
final class MenuCardModel {
    var preview: ArrangeCoordinator.Preview?
    /// Layout under the pointer in the alternatives row (preview only).
    var hoveredLayout: LayoutID?
    var hoverPreview: ArrangeCoordinator.Preview?
    var shownPreview: ArrangeCoordinator.Preview? { hoverPreview ?? preview }
}

/// Arrange card: a miniature of the display as it will look, with one-click alternatives.
struct MenuCard: View {
    let model: MenuCardModel
    let arrangeShortcut: String?
    let onArrange: (LayoutID) -> Void
    let onHover: (LayoutID?) -> Void
    let onPickPrimary: (WindowID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let preview = model.shownPreview {
                header(preview)
                ScreenPreview(
                    preview: preview,
                    onPick: preview.plan.layout == .masterStack ? onPickPrimary : nil
                )
                .frame(height: 158)
                .contentShape(Rectangle())
                .onTapGesture { if preview.plan.layout != .masterStack { onArrange(preview.plan.layout) } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.describe(preview))
                .accessibilityAddTraits(preview.plan.layout == .masterStack ? [] : .isButton)
                .modifier(PrimaryActions(preview: preview, onPick: onPickPrimary))
                LayoutPicker(
                    candidates: (model.preview ?? preview).plan.candidates,
                    current: model.hoveredLayout ?? (model.preview ?? preview).plan.layout,
                    windowCount: preview.windowIDs.count,
                    onArrange: onArrange,
                    onHover: onHover)
            } else {
                Label("No windows to arrange here", systemImage: "rectangle.dashed")
                    .font(.system(size: 13, weight: .semibold))
                Text("Full-screen windows and other Spaces aren't included.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(width: 320, alignment: .leading)
    }

    private func header(_ p: ArrangeCoordinator.Preview) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text(p.plan.layout.description)
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.opacity)
                Spacer()
                if let arrangeShortcut {
                    Text(arrangeShortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(Self.subtitle(p))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    static func subtitle(_ p: ArrangeCoordinator.Preview) -> String {
        let n = p.windowIDs.count
        var parts = ["\(n) window\(n == 1 ? "" : "s") on \(p.display.name)"]
        if p.plan.layout == .masterStack, let id = p.primaryID, let app = p.appNames[id] {
            parts.append("\(app) in front")
        }
        return parts.joined(separator: " · ")
    }

    static func describe(_ p: ArrangeCoordinator.Preview) -> String {
        let names = p.plan.frames.sorted { ($0.value.y, $0.value.x) < ($1.value.y, $1.value.x) }
            .map { p.appNames[$0.key] ?? "Window" }
        var text = "\(p.plan.layout.description) layout preview. "
        if p.plan.layout == .masterStack, let id = p.primaryID {
            text += "Primary: \(p.appNames[id] ?? "window"). "
        }
        return text + names.joined(separator: ", ")
    }
}

/// A miniature of the display: its desktop picture, a menu bar, and each window
/// as a small macOS window (title bar, app icon, name) where ordino will put it.
struct ScreenPreview: View {
    let preview: ArrangeCoordinator.Preview
    /// Called with the window whose slot was clicked (makes it primary).
    var onPick: ((WindowID) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: WindowID?

    var body: some View {
        GeometryReader { geo in
            let area = preview.display.visibleFrame
            // The whole screen: a menu bar strip above the visible frame.
            let menuBar = 24.0
            let screenH = area.h + menuBar
            let scale = min(geo.size.width / area.w, geo.size.height / screenH)
            let size = CGSize(width: area.w * scale, height: screenH * scale)
            let origin = CGPoint(x: (geo.size.width - size.width) / 2, y: (geo.size.height - size.height) / 2)
            let barH = max(3, menuBar * scale)
            ZStack(alignment: .topLeading) {
                desktop
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5)
                    )
                    .offset(x: origin.x, y: origin.y)
                // Menu bar.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(width: size.width, height: barH)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7, style: .continuous))
                    .offset(x: origin.x, y: origin.y)
                ForEach(preview.plan.frames.keys.sorted(), id: \.self) { id in
                    let f = preview.plan.frames[id]!
                    // Real gaps shrink to nothing at this scale; keep a visible seam of wallpaper.
                    let rect = CGRect(
                        x: origin.x + (f.x - area.x) * scale, y: origin.y + barH + (f.y - area.y) * scale,
                        width: f.w * scale, height: f.h * scale
                    ).insetBy(dx: 1.5, dy: 1.5)
                    MiniWindow(
                        appName: preview.appNames[id] ?? "Window",
                        icon: MenuVisuals.icon(forBundleID: preview.bundleIDs[id]),
                        isPrimary: id == preview.primaryID && preview.plan.layout == .masterStack,
                        isHovered: hovered == id && onPick != nil,
                        size: rect.size
                    )
                    .frame(width: max(1, rect.width), height: max(1, rect.height))
                    .contentShape(Rectangle())
                    .onTapGesture { onPick?(id) }
                    .onHover { inside in hovered = inside ? id : (hovered == id ? nil : hovered) }
                    .help(onPick == nil ? "" : "Put \(preview.appNames[id] ?? "this window") in front")
                    .offset(x: rect.minX, y: rect.minY)
                    .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.12), value: rect)
                }
            }
        }
    }

    @ViewBuilder private var desktop: some View {
        if let wallpaper = MenuVisuals.wallpaper(forDisplayUUID: preview.display.id) {
            Image(nsImage: wallpaper).resizable().aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: [Color(red: 0.36, green: 0.42, blue: 0.52), Color(red: 0.16, green: 0.19, blue: 0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// One window in the preview, drawn like a tiny macOS window.
struct MiniWindow: View {
    let appName: String
    let icon: NSImage?
    let isPrimary: Bool
    let isHovered: Bool
    let size: CGSize

    var body: some View {
        let radius = min(5, size.height * 0.08)
        let titleH = min(9, max(5, size.height * 0.14))
        let iconSide = min(30, size.width * 0.34, (size.height - titleH) * 0.52)
        let showName = size.width >= 64 && size.height >= 46
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
            // Title bar with traffic lights.
            HStack(spacing: max(1.5, titleH * 0.22)) {
                ForEach(
                    [
                        Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                        Color(red: 0.16, green: 0.79, blue: 0.25),
                    ], id: \.self
                ) { c in
                    Circle().fill(c).frame(width: titleH * 0.42, height: titleH * 0.42)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, titleH * 0.5)
            .frame(height: titleH)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.05))
            // Content: the app's icon, and its name when there's room.
            VStack(spacing: 2) {
                if let icon, iconSide >= 8 {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: iconSide, height: iconSide)
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                }
                if showName {
                    Text(appName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, titleH)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    isPrimary ? Color.accentColor : Color.black.opacity(isHovered ? 0.35 : 0.14),
                    lineWidth: isPrimary ? 1.5 : 0.5)
        )
        .shadow(color: .black.opacity(isPrimary ? 0.32 : 0.22), radius: isPrimary ? 3 : 1.5, y: 1)
        .brightness(isHovered && !isPrimary ? 0.03 : 0)
    }
}

/// The layout alternatives, styled like a native segmented control.
struct LayoutPicker: View {
    let candidates: [LayoutID]
    let current: LayoutID
    let windowCount: Int
    let onArrange: (LayoutID) -> Void
    let onHover: (LayoutID?) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(candidates, id: \.self) { layout in
                let selected = layout == current
                Button {
                    onArrange(layout)
                } label: {
                    Image(nsImage: ActionIcons.image(for: layout, windowCount: windowCount))
                        .renderingMode(.template)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.16) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(layout.description)
                .accessibilityLabel("Arrange as \(layout.description)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .onHover { inside in onHover(inside ? layout : nil) }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

/// VoiceOver: one "Make <app> primary" action per window for Master + Stack.
private struct PrimaryActions: ViewModifier {
    let preview: ArrangeCoordinator.Preview
    let onPick: (WindowID) -> Void

    func body(content: Content) -> some View {
        if preview.plan.layout == .masterStack {
            preview.windowIDs.reduce(AnyView(content)) { view, id in
                AnyView(
                    view.accessibilityAction(named: "Make \(preview.appNames[id] ?? "window") primary") { onPick(id) })
            }
        } else {
            content
        }
    }
}
