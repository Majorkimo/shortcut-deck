import SwiftUI

/// Kachel in der Bibliothek. Klick = in die Leiste aufnehmen / entfernen.
struct TileView: View {
    let shortcut: Shortcut
    let selected: Bool
    let inBar: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ShortcutIcon(shortcut: shortcut, size: 32)
                    .padding(.top, 2)
                Text(shortcut.name)
                    .font(.system(size: 11, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                Text(shortcut.comboText.isEmpty ? "Systemaufruf" : shortcut.comboText)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(inBar ? Color.accentColor.opacity(hover ? 0.18 : 0.12)
                                : Color.primary.opacity(hover ? 0.09 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : (inBar ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06)),
                                  lineWidth: selected ? 2 : (inBar ? 1 : 0.5))
            )
            .overlay(alignment: .topTrailing) {
                if inBar || hover {
                    Image(systemName: inBar ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(inBar ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .padding(5)
                        .transition(.opacity)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(inBar ? "\(shortcut.name) aus der Leiste entfernen" : "\(shortcut.name) zur Leiste hinzufügen")
        .accessibilityLabel(shortcut.name)
        .accessibilityValue(inBar ? "In der Leiste" : "Nicht in der Leiste")
        .accessibilityHint(shortcut.comboText)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
