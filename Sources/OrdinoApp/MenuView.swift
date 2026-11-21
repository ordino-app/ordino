import ArrangeCore
import Geometry
import LayoutEngine
import SwiftUI

struct MenuView: View {
    @Bindable var model: MenuModel
    let onArrange: (LayoutID?) -> Void
    let onSelect: (LayoutID?) -> Void
    let onPrimary: (WindowID?) -> Void
    let onAlwaysPrimary: (String, Bool) -> Void
    let onUndo: () -> Void
    let onGap: (Double) -> Void
    let onLaunchAtLogin: (Bool) -> Void
    let onGrantAccess: () -> Void
    let onCheckForUpdates: () -> Void
    let onBetaUpdates: (Bool) -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.trusted {
                permissionCard
            } else if let preview = model.shownPreview {
                header(preview)
                LayoutThumbnail(
                    preview: preview,
                    onPick: preview.plan.layout == .masterStack ? { onPrimary($0) } : nil
                )
                .frame(height: 150)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.describe(preview))
                Button {
                    onArrange(nil)
                } label: {
                    HStack {
                        Text("Arrange windows")
                        Spacer()
                        if let hint = model.arrangeHint { Text(hint).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .modifier(ProminentButton())
                alternatives(model.preview ?? preview)
                // Shown whenever Master + Stack is on offer, not only while it's
                // hovered, so the picker never disappears under the pointer.
                if let base = model.preview, base.plan.candidates.contains(.masterStack), base.windowIDs.count > 1 {
                    primaryPicker(preview.plan.layout == .masterStack ? preview : base)
                }
            } else {
                emptyState
            }

            if let warning = model.shortcutWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()

            HStack(spacing: 8) {
                Text("Gaps").frame(width: 40, alignment: .leading).accessibilityHidden(true)
                // Saved on every change, so keyboard and VoiceOver adjustments stick too.
                Slider(
                    value: Binding(
                        get: { model.gap },
                        set: {
                            model.gap = $0
                            onGap($0)
                        }),
                    in: 0...24, step: 2
                ) { Text("Gaps") }
                .labelsHidden()
                .accessibilityLabel("Gaps between windows")
                .accessibilityValue("\(Int(model.gap)) points")
                Text("\(Int(model.gap)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 40)
                    .accessibilityHidden(true)
            }
            Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { onLaunchAtLogin($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)

            if model.updatesAvailable {
                HStack(spacing: 8) {
                    if model.updateAvailable {
                        Button("Update available…", systemImage: "arrow.down.circle.fill", action: onCheckForUpdates)
                            .foregroundStyle(.tint)
                    } else {
                        Button("Check for updates…", action: onCheckForUpdates)
                            .disabled(!model.canCheckForUpdates)
                    }
                    Spacer()
                    Toggle("Beta", isOn: Binding(get: { model.betaUpdates }, set: { onBetaUpdates($0) }))
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .help("Also receive beta versions")
                        .accessibilityLabel("Receive beta updates")
                }
                .buttonStyle(.borderless)
            }
            Text(model.version).font(.caption2).foregroundStyle(.tertiary)

            HStack {
                Button("Undo", systemImage: "arrow.uturn.backward", action: onUndo)
                    .disabled(!model.canUndo)
                    .help("⌃⌥⌘Z")
                Spacer()
                Button("Quit ordino", action: onQuit)
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 340)
        .modifier(PanelBackground())
    }

    // MARK: Pieces

    private func header(_ p: ArrangeCoordinator.Preview) -> some View {
        HStack {
            Label(p.display.name, systemImage: "display").lineLimit(1)
            Spacer()
            let n = p.plan.frames.count
            Text("\(n) window\(n == 1 ? "" : "s") · \(p.plan.layout.description)")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func alternatives(_ p: ArrangeCoordinator.Preview) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(p.plan.candidates.enumerated()), id: \.element) { index, layout in
                let isCurrent = layout == (model.selectedLayout ?? p.plan.layout)
                Button {
                    onArrange(layout)
                } label: {
                    Image(systemName: Self.symbol(for: layout))
                        .frame(width: 44, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isCurrent ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("\(layout.description) (\(index + 1))")
                .accessibilityLabel(layout.description)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
                .onHover { inside in onSelect(inside ? layout : nil) }
            }
            Spacer()
        }
    }

    /// "Which window gets the big slot": automatic (focused / always-primary app)
    /// or a specific window. Clicking a slot in the thumbnail does the same.
    private func primaryPicker(_ p: ArrangeCoordinator.Preview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(
                "Primary window (Master + Stack)",
                selection: Binding(get: { model.primaryOverride }, set: { onPrimary($0) })
            ) {
                Text(automaticLabel(p)).tag(WindowID?.none)
                Divider()
                ForEach(p.windowIDs, id: \.self) { id in
                    Text(Self.windowLabel(id, p)).tag(WindowID?.some(id))
                }
            }
            .pickerStyle(.menu)
            .help("The window that gets the large slot. You can also click a window in the preview.")

            if let id = p.primaryID, let bundleID = p.bundleIDs[id] {
                let app = p.appNames[id] ?? "this app"
                Toggle(
                    "Always make \(app) primary",
                    isOn: Binding(
                        get: { model.alwaysPrimaryApps.contains(bundleID) },
                        set: { onAlwaysPrimary(bundleID, $0) })
                )
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }
        }
        .font(.callout)
    }

    private func automaticLabel(_ p: ArrangeCoordinator.Preview) -> String {
        guard model.primaryOverride == nil, let id = p.primaryID else { return "Automatic" }
        return "Automatic (\(p.appNames[id] ?? "focused window"))"
    }

    static func windowLabel(_ id: WindowID, _ p: ArrangeCoordinator.Preview) -> String {
        let app = p.appNames[id] ?? "Window"
        let title = (p.titles[id] ?? "").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, title != app else { return app }
        return "\(app) – \(title.count > 40 ? String(title.prefix(40)) + "…" : title)"
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ordino needs Accessibility access", systemImage: "hand.raised")
                .font(.headline)
            Text("macOS only lets apps move other apps' windows if you allow it.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Grant access…", action: onGrantAccess).modifier(ProminentButton())
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("No windows to arrange", systemImage: "rectangle.dashed").font(.headline)
            Text("Windows in full screen or on other Spaces aren't included.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    static func symbol(for layout: LayoutID) -> String {
        switch layout {
        case .maximize: "macwindow"
        case .centered: "rectangle.center.inset.filled"
        case .columns: "rectangle.split.3x1"
        case .rows: "rectangle.split.1x2"
        case .masterStack: "sidebar.left"
        case .grid: "square.grid.2x2"
        case .bsp: "rectangle.split.2x2"
        }
    }

    static func describe(_ p: ArrangeCoordinator.Preview) -> String {
        let names = p.plan.frames.sorted { ($0.value.y, $0.value.x) < ($1.value.y, $1.value.x) }
            .map { p.appNames[$0.key] ?? "Window" }
        var text = "\(p.plan.layout.description) layout. "
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
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: size.width, height: size.height)
                    .offset(x: origin.x, y: origin.y)
                ForEach(preview.plan.frames.keys.sorted(), id: \.self) { id in
                    let f = preview.plan.frames[id]!
                    let rect = CGRect(
                        x: origin.x + (f.x - area.x) * scale, y: origin.y + (f.y - area.y) * scale,
                        width: f.w * scale, height: f.h * scale)
                    let isPrimary = id == preview.primaryID && preview.plan.layout == .masterStack
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(isPrimary ? 0.32 : 0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1)
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

/// Liquid Glass on macOS 26+, material before.
struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct ProminentButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}
