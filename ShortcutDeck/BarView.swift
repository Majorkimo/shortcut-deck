import AppKit
import SwiftUI

/// Die längliche Leiste: nur die selbst gewählten Kürzel, zum direkten Anklicken.
struct BarView: View {
    @EnvironmentObject private var store: ShortcutStore
    @EnvironmentObject private var executor: Executor
    @State private var dragging: String?
    @ObservedObject private var library = LibraryController.shared
    private var libraryOpen: Bool { library.isOpen }

    var body: some View {
        HStack(spacing: 2) {
            Grip()

            if !executor.isTrusted {
                BarIconButton(symbol: "hand.raised.fill", help: "Bedienungshilfen freigeben: nötig, damit Klicks Tastenkürzel senden",
                              tint: .orange) { executor.requestAccessibility() }
                BarDivider()
            }

            if store.bar.isEmpty {
                Button { LibraryController.shared.show() } label: {
                    Label("Kürzel hinzufügen", systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }

            ForEach(store.bar) { s in
                BarItem(shortcut: s, showLabel: store.showLabels,
                        flash: executor.feedback?.shortcutID == s.id ? executor.feedback : nil) {
                    executor.run(s)
                }
                .opacity(dragging == s.id ? 0.4 : 1)
                .onDrag {
                    dragging = s.id
                    return NSItemProvider(object: s.id as NSString)
                }
                .onDrop(of: [.text], delegate: ReorderDrop(target: s.id, items: $store.barItems, dragging: $dragging))
                .contextMenu {
                    Button("Ausführen") { executor.run(s) }
                    Divider()
                    Button("Nach links") { store.move(s, by: -1) }
                        .disabled(store.barItems.first == s.id)
                    Button("Nach rechts") { store.move(s, by: 1) }
                        .disabled(store.barItems.last == s.id)
                    Button("Aus der Leiste entfernen") { store.toggleInBar(s) }
                    Divider()
                    Button("Leiste zusammenstellen …") { LibraryController.shared.show() }
                }
            }

            BarDivider()

            BarIconButton(symbol: "square.grid.2x2", help: "Leiste zusammenstellen", active: libraryOpen) {
                LibraryController.shared.toggle()
            }
            BarIconButton(symbol: store.pinned ? "pin.fill" : "pin",
                          help: store.pinned ? "Nicht mehr im Vordergrund halten" : "Immer im Vordergrund",
                          active: store.pinned) {
                store.pinned.toggle()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(WindowDragArea())
        .background(VisualEffect(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .fixedSize()
        .onDrop(of: [.text], isTargeted: nil) { _ in dragging = nil; return true }
    }
}

// MARK: - Ein Eintrag

struct BarItem: View {
    let shortcut: Shortcut
    let showLabel: Bool
    let flash: Executor.Feedback?
    let action: () -> Void

    @State private var hover = false
    @State private var showFlash = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ShortcutIcon(shortcut: shortcut, size: showLabel ? 30 : 32)
                    .overlay(alignment: .bottomTrailing) {
                        if showFlash, let flash {
                            Image(systemName: flash.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white, flash.ok ? Color.green : Color.orange)
                                .offset(x: 4, y: 4)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                if showLabel {
                    Text(shortcut.name)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                    Text(shortcut.comboText.isEmpty ? " " : shortcut.comboText)
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: showLabel ? 58 : 40)
            .padding(.vertical, showLabel ? 5 : 4)
            .padding(.horizontal, showLabel ? 6 : 2)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(hover ? 0.10 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(shortcut.comboText.isEmpty ? shortcut.name : "\(shortcut.name)  \(shortcut.comboText)")
        .accessibilityLabel(shortcut.name)
        .accessibilityHint(shortcut.comboText)
        .onChange(of: flash?.id) { _, id in
            guard id != nil else { return }
            withAnimation(.spring(duration: 0.25)) { showFlash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                withAnimation(.easeOut(duration: 0.3)) { showFlash = false }
            }
        }
    }
}

struct ShortcutIcon: View {
    let shortcut: Shortcut
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Color(nsColor: shortcut.group.tint).gradient)
                .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
            Image(systemName: shortcut.symbol)
                .font(.system(size: size * 0.47, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Bausteine

struct BarIconButton: View {
    let symbol: String
    let help: String
    var active = false
    var tint: Color? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? (active ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hover ? 0.1 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct BarDivider: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 30).padding(.horizontal, 4)
    }
}

/// Griff zum Verschieben (die ganze Leiste ist ziehbar, der Griff zeigt es an).
struct Grip: View {
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3) { _ in
                HStack(spacing: 3) {
                    Circle().frame(width: 2.5, height: 2.5)
                    Circle().frame(width: 2.5, height: 2.5)
                }
            }
        }
        .foregroundStyle(.tertiary)
        .frame(width: 14, height: 30)
        .padding(.horizontal, 3)
        .overlay(WindowDragArea())
        .onHover { inside in
            if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
        .help("Leiste verschieben")
    }
}

struct ReorderDrop: DropDelegate {
    let target: String
    @Binding var items: [String]
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != target,
              let from = items.firstIndex(of: d), let to = items.firstIndex(of: target) else { return }
        items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

/// Fläche, an der man das Fenster ziehen kann (SwiftUI-Inhalt schluckt sonst das Ziehen).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
