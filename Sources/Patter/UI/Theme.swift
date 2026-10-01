import SwiftUI

enum Theme {
    static let violet = Color(red: 0.55, green: 0.42, blue: 1.0)
    static let blue = Color(red: 0.36, green: 0.58, blue: 1.0)
    static let cyan = Color(red: 0.27, green: 0.84, blue: 0.98)
    static let stopRed = Color(red: 1.0, green: 0.30, blue: 0.32)
    static let success = Color(red: 0.24, green: 0.86, blue: 0.52)
    static let warning = Color(red: 1.0, green: 0.74, blue: 0.28)

    static let accentColors = [violet, blue, cyan]

    static var accent: LinearGradient {
        LinearGradient(colors: accentColors, startPoint: .leading, endPoint: .trailing)
    }

    static var accentDiagonal: LinearGradient {
        LinearGradient(colors: accentColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The near-black fill of the floating indicator.
    static let pillFill = Color(red: 0.06, green: 0.06, blue: 0.08)
}

/// A key cap, for example for ⌃ ⇧ R.
struct KeyCap: View {
    let symbol: String
    var size: CGFloat = 12

    var body: some View {
        Text(symbol)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary.opacity(0.85))
            .frame(minWidth: size * 1.9, minHeight: size * 1.9)
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: size * 0.45, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.45, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            )
    }
}

struct ShortcutKeys: View {
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Shortcut.symbols, id: \.self) { KeyCap(symbol: $0, size: size) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Control Shift R")
    }
}
