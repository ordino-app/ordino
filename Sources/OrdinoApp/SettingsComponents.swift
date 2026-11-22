import SwiftUI

/// Building blocks for the Settings panes: every row has a small monochrome
/// icon, a label, an optional "?" that explains it, and its control on the right.

/// Section title with an icon, e.g. "◑ Arranging".
struct SectionTitle: View {
    let title: String
    let symbol: String

    init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
        .font(.system(size: 13, weight: .semibold))
    }
}

/// One setting: icon, label, optional help, control.
struct SettingRow<Control: View>: View {
    let symbol: String
    let title: String
    var help: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title)
            if let help { HelpBadge(text: help, topic: title) }
            Spacer(minLength: 12)
            control()
        }
        .frame(minHeight: 22)
    }
}

/// A switch row.
struct ToggleRow: View {
    let symbol: String
    let title: String
    var help: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(symbol: symbol, title: title, help: help) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// The small "?" after a label: click for a short explanation.
struct HelpBadge: View {
    let text: String
    let topic: String
    @State private var shown = false

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help(text)
        .accessibilityLabel("About \(topic)")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(14)
        }
    }
}

/// Options that only matter when their parent is on, in an inset card.
struct SubGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}
