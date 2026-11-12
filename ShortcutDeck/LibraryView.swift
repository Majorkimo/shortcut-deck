import AppKit
import SwiftUI

/// Hält Tastatur-Auswahl und Aktionen für den lokalen Key-Monitor.
@MainActor
final class NavModel: ObservableObject {
    @Published var selection: Int = -1
    var items: [Shortcut] = []
    var columns = 4
    var window: NSWindow?
    var paused = false
    var activate: (Shortcut) -> Void = { _ in }
    var escape: () -> Void = {}
    var focusSearch: () -> Void = {}
    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.paused, event.window === self.window else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        if selection < 0 { selection = 0; return }
        selection = min(max(selection + delta, 0), items.count - 1)
    }

    private func handle(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        switch Int(e.keyCode) {
        case 125: move(selection < 0 ? 0 : columns); return true      // ↓
        case 126: move(-columns); return true                         // ↑
        case 123 where selection >= 0: move(-1); return true          // ←
        case 124 where selection >= 0: move(1); return true           // →
        case 36, 76:                                                  // ↩︎
            let i = selection < 0 ? 0 : selection
            if items.indices.contains(i) { activate(items[i]) }
            return true
        case 53: escape(); return true                                // ⎋
        case 3 where cmd: focusSearch(); return true                  // ⌘F
        default: return false
        }
    }
}

/// Alle Kürzel. Klick nimmt ein Kürzel in die Leiste auf oder entfernt es.
struct LibraryView: View {
    enum Mode { case menuBar, window }
    let mode: Mode

    @EnvironmentObject private var store: ShortcutStore
    @EnvironmentObject private var executor: Executor
    @StateObject private var nav = NavModel()
    @State private var query = ""
    @State private var filter: ShortcutGroup?
    @State private var editing: Shortcut?
    @FocusState private var searchFocused: Bool

    private struct Section: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let items: [Shortcut]
    }

    private var sections: [Section] {
        let all = store.all.filter { filter == nil || $0.group == filter }
        if !query.isEmpty {
            let hits = all.filter { $0.matches(query) }
            return hits.isEmpty ? [] : [Section(id: "hits", title: "Treffer", symbol: "magnifyingglass", items: hits)]
        }
        return ShortcutGroup.allCases.compactMap { g in
            let items = all.filter { $0.group == g }
            return items.isEmpty ? nil : Section(id: g.rawValue, title: g.title, symbol: g.symbol, items: items)
        }
    }

    var body: some View {
        let sections = self.sections
        let flat = sections.flatMap(\.items)
        nav.items = flat
        nav.activate = { toggle($0) }
        nav.escape = escape
        nav.focusSearch = { searchFocused = true }
        nav.paused = editing != nil

        return VStack(spacing: 0) {
            header
            searchField.padding(.horizontal, 14).padding(.bottom, 8)
            chips.padding(.bottom, 6)
            if !executor.isTrusted { AccessibilityBanner().padding(.horizontal, 14).padding(.bottom, 8) }
            Divider().opacity(0.5)
            grid(sections: sections, flat: flat)
            footer
        }
        .frame(width: 460, height: mode == .menuBar ? 600 : nil)
        .frame(maxHeight: .infinity)
        .background(WindowReader { nav.window = $0 })
        .overlay {
            if let editing {
                EditorView(original: editing) { result in
                    if let result { store.upsert(result) }
                    self.editing = nil
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.snappy(duration: 0.2), value: editing)
        .onAppear {
            nav.install()
            searchFocused = true
        }
        .onDisappear { nav.uninstall() }
        .onChange(of: query) { _, q in nav.selection = q.isEmpty ? -1 : 0 }
        .onChange(of: filter) { _, _ in nav.selection = -1 }
    }

    // MARK: Teile

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "command.square.fill")
                .font(.system(size: 18))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text("Shortcut Deck").font(.system(size: 14, weight: .semibold))
                Text("Klick nimmt ein Kürzel in die Leiste auf · \(store.barItems.count) in der Leiste")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            BarIconButton(symbol: "plus", help: "Eigenes Kürzel anlegen") {
                editing = Shortcut(id: "custom-\(UUID().uuidString)", name: "", symbol: "keyboard",
                                   group: .custom, combo: nil)
            }
            Menu {
                Button(BarController.shared.isVisible ? "Leiste ausblenden" : "Leiste zeigen") {
                    BarController.shared.toggle()
                }
                Toggle("Namen und Kürzel in der Leiste zeigen", isOn: $store.showLabels)
                Toggle("Leiste immer im Vordergrund", isOn: $store.pinned)
                Button("Leiste auf Standard zurücksetzen") { store.barItems = ShortcutStore.defaultBar }
                Divider()
                Picker("Erscheinungsbild", selection: $store.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                Divider()
                Button(executor.isTrusted ? "Bedienungshilfen: freigegeben" : "Bedienungshilfen freigeben …") {
                    executor.requestAccessibility()
                }
                .disabled(executor.isTrusted)
                Divider()
                Button("Shortcut Deck beenden") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Mehr")
        }
        .padding(.horizontal, 14)
        .padding(.top, mode == .window ? 30 : 12)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Alle Kürzel durchsuchen", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Suche leeren")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(searchFocused ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 2))
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(title: "Alle", symbol: "square.grid.2x2", selected: filter == nil) { filter = nil }
                ForEach(ShortcutGroup.allCases.filter { $0 != .custom || !store.custom.isEmpty }) { g in
                    Chip(title: g.title, symbol: g.symbol, selected: filter == g) {
                        filter = (filter == g) ? nil : g
                    }
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func grid(sections: [Section], flat: [Shortcut]) -> some View {
        let cols = 4
        let _ = (nav.columns = cols)
        return ScrollViewReader { proxy in
            ScrollView {
                if sections.isEmpty {
                    ContentUnavailableView.search(text: query).padding(.top, 40)
                }
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(section.title, systemImage: section.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.leading, 2)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: cols),
                                      spacing: 8) {
                                ForEach(section.items) { s in
                                    let index = flat.firstIndex(of: s) ?? -1
                                    TileView(shortcut: s, selected: index == nav.selection,
                                             inBar: store.inBar(s)) { toggle(s) }
                                        .id("\(section.id)-\(s.id)")
                                        .contextMenu { contextMenu(for: s) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: nav.selection) { _, i in
                guard flat.indices.contains(i) else { return }
                let s = flat[i]
                if let sec = sections.first(where: { $0.items.contains(s) }) {
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo("\(sec.id)-\(s.id)", anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for s: Shortcut) -> some View {
        Button(store.inBar(s) ? "Aus der Leiste entfernen" : "Zur Leiste hinzufügen") { toggle(s) }
        Button("Jetzt ausführen") { run(s) }
        if s.group == .custom {
            Divider()
            Button("Bearbeiten …") { editing = s }
            Button("Löschen", role: .destructive) { store.remove(s) }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard").foregroundStyle(.tertiary)
            Text("Pfeile wählen · ↩︎ hinzufügen/entfernen · ⌘F suchen")
            Spacer(minLength: 0)
            Button(BarController.shared.isVisible ? "Leiste ausblenden" : "Leiste zeigen") {
                BarController.shared.toggle()
            }
            .controlSize(.small)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar.opacity(0.4))
    }

    // MARK: Aktionen

    private func toggle(_ s: Shortcut) {
        if let i = nav.items.firstIndex(of: s) { nav.selection = i }
        store.toggleInBar(s)
        if store.inBar(s), !BarController.shared.isVisible { BarController.shared.show() }
    }

    private func run(_ s: Shortcut) {
        let dismiss: (() -> Void)? = mode == .menuBar ? { nav.window?.close() } : nil
        executor.run(s, dismiss: dismiss)
    }

    private func escape() {
        if !query.isEmpty { query = "" }
        else if mode == .window { LibraryController.shared.close() }
        else { nav.window?.close() }
    }
}

// MARK: - Kleine Bausteine

struct Chip: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(Capsule().fill(selected ? AnyShapeStyle(Color.accentColor)
                                                    : AnyShapeStyle(Color.primary.opacity(hover ? 0.1 : 0.05))))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct AccessibilityBanner: View {
    @EnvironmentObject private var executor: Executor

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Freigabe für Bedienungshilfen nötig").font(.system(size: 12, weight: .semibold))
                Text("Damit ein Klick in der Leiste Tastenkürzel an die vorige App senden kann, muss macOS „Shortcut Deck“ unter Datenschutz & Sicherheit → Bedienungshilfen erlauben. Sperren, Screenshot-Werkzeug, Mission Control und Ruhezustand gehen auch ohne.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Freigabe anfragen") { executor.requestAccessibility() }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    Button("Einstellungen öffnen") { executor.openAccessibilitySettings() }
                        .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}

/// Liefert das NSWindow, in dem die View steckt.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onWindow(v.window) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(v.window) }
    }
}
