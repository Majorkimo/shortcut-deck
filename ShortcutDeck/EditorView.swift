import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Formular für eigene Kürzel, als Überlagerung im Panel (Sheets sind in
/// Menüleisten-Fenstern unzuverlässig).
struct EditorView: View {
    let original: Shortcut
    let done: (Shortcut?) -> Void

    @State private var name: String
    @State private var symbol: String
    @State private var combo: KeyCombo?
    @State private var delivery: Delivery
    @State private var recording = false
    @State private var monitor: Any?
    @State private var window: NSWindow?

    private let suggestions = ["keyboard", "star", "bolt", "terminal", "globe", "music.note", "mic",
                               "photo", "paintbrush", "envelope", "calendar", "bookmark", "link", "wand.and.stars"]

    init(original: Shortcut, done: @escaping (Shortcut?) -> Void) {
        self.original = original
        self.done = done
        _name = State(initialValue: original.name)
        _symbol = State(initialValue: original.symbol)
        _combo = State(initialValue: original.combo)
        _delivery = State(initialValue: original.delivery)
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.18)).onTapGesture { finish(nil) }
            VStack(alignment: .leading, spacing: 12) {
                Text(original.name.isEmpty ? "Eigenes Kürzel" : "Kürzel bearbeiten")
                    .font(.system(size: 14, weight: .semibold))

                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(nsColor: ShortcutGroup.custom.tint).gradient)
                            .frame(width: 38, height: 38)
                        Image(systemName: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil
                              ? "questionmark" : symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Symbol (SF Symbols)").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("z. B. star", text: $symbol).textFieldStyle(.roundedBorder)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(suggestions, id: \.self) { s in
                                Button { symbol = s } label: {
                                    Image(systemName: s)
                                        .frame(width: 24, height: 22)
                                        .background(RoundedRectangle(cornerRadius: 5)
                                            .fill(symbol == s ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tastenkürzel").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button {
                        recording ? stopRecording() : startRecording()
                    } label: {
                        HStack {
                            Image(systemName: recording ? "record.circle" : "keyboard")
                                .foregroundStyle(recording ? .red : .secondary)
                            Text(recording ? "Jetzt Tasten drücken …" : (combo?.display ?? "Zum Aufnehmen klicken"))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(0.15),
                                          lineWidth: recording ? 2 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Picker("Senden an", selection: $delivery) {
                    Text("Zuletzt aktive App").tag(Delivery.frontApp)
                    Text("Systemweit").tag(Delivery.global)
                    Text("Finder").tag(Delivery.finder)
                }
                .pickerStyle(.menu)

                HStack {
                    Spacer()
                    Button("Abbrechen") { finish(nil) }
                        .keyboardShortcut(.cancelAction)
                    Button("Sichern") {
                        var s = original
                        s.name = name.trimmingCharacters(in: .whitespaces)
                        s.symbol = symbol.isEmpty ? "keyboard" : symbol
                        s.combo = combo
                        s.delivery = delivery
                        s.group = .custom
                        finish(s)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || combo == nil || recording)
                }
            }
            .padding(16)
            .frame(width: 320)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
            .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        }
        .background(WindowReader { window = $0 })
        .onDisappear { stopRecording() }
    }

    private func finish(_ s: Shortcut?) {
        stopRecording()
        done(s)
    }

    private func startRecording() {
        window?.makeKey()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                stopRecording()
                return nil
            }
            combo = KeyCombo(mods: Mods(event.modifierFlags), key: Self.key(for: event))
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    private static let special: [Int: String] = [
        kVK_Space: "Leertaste", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_Return: "↩︎", kVK_ANSI_KeypadEnter: "⌤", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func key(for event: NSEvent) -> Key {
        if let label = special[Int(event.keyCode)] {
            return .code(event.keyCode, label: label)
        }
        let ch = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? ""
        if ch.count == 1, KeyLayout.keyCode(for: ch) != nil { return .char(ch.lowercased()) }
        return .code(event.keyCode, label: ch.uppercased())
    }
}
