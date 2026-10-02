import SwiftUI

/// Shows a shortcut as key caps. Click the field, then press the new keys. The X button removes
/// the shortcut.
struct ShortcutField: View {
    let shortcut: Shortcut?
    let isRecording: Bool
    /// The modifier keys (Carbon flags) that the user holds down while Patter records.
    let heldModifiers: Int
    let onClick: () -> Void
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onClick) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(isRecording ? "Press the new keys, or press Escape to cancel" : "Click to change")

            if let shortcut, !isRecording {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove the shortcut")
                .accessibilityLabel("Remove the shortcut \(shortcut.spokenName)")
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .frame(width: 170, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(hovering || isRecording ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isRecording ? Theme.blue : Color.primary.opacity(0.12),
                    lineWidth: isRecording ? 1.5 : 1)
        )
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var content: some View {
        if isRecording && heldModifiers != 0 {
            keys(Shortcut.modifierSymbols(heldModifiers))
        } else if isRecording {
            placeholder("Type the shortcut")
        } else if let shortcut {
            keys(shortcut.symbols)
        } else {
            placeholder("Click to set")
        }
    }

    private func keys(_ symbols: [String]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { KeyCap(symbol: $0.element, size: 10) }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
    }

    private var accessibilityLabel: String {
        if isRecording { return "Recording a new shortcut" }
        return shortcut.map { "Shortcut \($0.spokenName)" } ?? "No shortcut"
    }
}
