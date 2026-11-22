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

/// Arrange card: what ⌃⌥⌘A would do right now, with one-click alternatives.
struct MenuCard: View {
    let model: MenuCardModel
    let arrangeShortcut: String?
    let onArrange: (LayoutID) -> Void
    let onHover: (LayoutID?) -> Void
    let onPickPrimary: (WindowID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let preview = model.shownPreview {
                HStack(alignment: .firstTextBaseline) {
                    Text("Arrange Windows").font(.headline)
                    Spacer()
                    if let arrangeShortcut {
                        Text(arrangeShortcut).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text(Self.subtitle(preview))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                LayoutThumbnail(
                    preview: preview,
                    onPick: preview.plan.layout == .masterStack ? onPickPrimary : nil
                )
                .frame(height: 118)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.describe(preview))
                .accessibilityAddTraits(preview.plan.layout == .masterStack ? [] : .isButton)
                .modifier(PrimaryActions(preview: preview, onPick: onPickPrimary))
                .onTapGesture { if preview.plan.layout != .masterStack { onArrange(preview.plan.layout) } }
                alternatives(model.preview ?? preview)
            } else {
                Label("No windows to arrange here", systemImage: "rectangle.dashed").font(.headline)
                Text("Full-screen windows and other Spaces aren't included.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 300, alignment: .leading)
    }

    private func alternatives(_ p: ArrangeCoordinator.Preview) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(p.plan.candidates.enumerated()), id: \.element) { index, layout in
                let isShown = layout == (model.hoveredLayout ?? p.plan.layout)
                Button {
                    onArrange(layout)
                } label: {
                    Image(nsImage: ActionIcons.image(for: layout, windowCount: p.windowIDs.count))
                        .frame(width: 46, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isShown ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help("\(layout.description)")
                .accessibilityLabel("Arrange as \(layout.description)")
                .accessibilityAddTraits(isShown ? .isSelected : [])
                .onHover { inside in onHover(inside ? layout : nil) }
                .id(index)
            }
            Spacer(minLength: 0)
        }
    }

    static func subtitle(_ p: ArrangeCoordinator.Preview) -> String {
        let n = p.windowIDs.count
        var parts = [p.display.name, "\(n) window\(n == 1 ? "" : "s")", p.plan.layout.description]
        if p.plan.layout == .masterStack, let id = p.primaryID, let app = p.appNames[id] {
            parts.append("\(app) primary")
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

/// Scaled drawing of the planned slots with app names.
struct LayoutThumbnail: View {
    let preview: ArrangeCoordinator.Preview
    /// Called with the window whose slot was clicked (makes it primary).
    var onPick: ((WindowID) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let area = preview.display.visibleFrame
            let scale = min(geo.size.width / area.w, geo.size.height / area.h)
            let size = CGSize(width: area.w * scale, height: area.h * scale)
            let origin = CGPoint(x: (geo.size.width - size.width) / 2, y: (geo.size.height - size.height) / 2)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .frame(width: size.width, height: size.height)
                    .offset(x: origin.x, y: origin.y)
                ForEach(preview.plan.frames.keys.sorted(), id: \.self) { id in
                    let f = preview.plan.frames[id]!
                    let rect = CGRect(
                        x: origin.x + (f.x - area.x) * scale, y: origin.y + (f.y - area.y) * scale,
                        width: f.w * scale, height: f.h * scale)
                    let isPrimary = id == preview.primaryID && preview.plan.layout == .masterStack
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.accentColor.opacity(isPrimary ? 0.38 : 0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1)
                        )
                        .overlay(
                            Text(preview.appNames[id] ?? "Window")
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .padding(3)
                        )
                        .frame(width: max(1, rect.width), height: max(1, rect.height))
                        .contentShape(Rectangle())
                        .onTapGesture { onPick?(id) }
                        .help(onPick == nil ? "" : "Make \(preview.appNames[id] ?? "this window") the primary window")
                        .offset(x: rect.minX, y: rect.minY)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: rect)
                }
            }
        }
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
