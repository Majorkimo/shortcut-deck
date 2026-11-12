import AppKit
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "Wie System"; case .light: "Hell"; case .dark: "Dunkel" }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Leisten-Auswahl, eigene Kürzel und Einstellungen – alles in UserDefaults.
@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()
    private let defaults = UserDefaults.standard

    static let defaultBar = ["screenshot", "spotlight", "missioncontrol", "copy", "paste",
                             "undo", "closewindow", "fullscreen", "emoji", "lock"]

    /// IDs der Kürzel in der Leiste, in Anzeige-Reihenfolge.
    @Published var barItems: [String] { didSet { defaults.set(barItems, forKey: "barItems") } }
    @Published var custom: [Shortcut] { didSet { saveCustom() } }
    @Published var pinned: Bool { didSet { defaults.set(pinned, forKey: "pinned") } }
    @Published var barVisible: Bool { didSet { defaults.set(barVisible, forKey: "barVisible") } }
    @Published var showLabels: Bool { didSet { defaults.set(showLabels, forKey: "showLabels") } }
    @Published var appearance: AppearanceMode {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            NSApp.appearance = appearance.nsAppearance
        }
    }

    private init() {
        barItems = defaults.stringArray(forKey: "barItems") ?? Self.defaultBar
        pinned = defaults.object(forKey: "pinned") as? Bool ?? true
        barVisible = defaults.object(forKey: "barVisible") as? Bool ?? true
        showLabels = defaults.object(forKey: "showLabels") as? Bool ?? true
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        if let data = defaults.data(forKey: "custom"),
           let list = try? JSONDecoder().decode([Shortcut].self, from: data) {
            custom = list
        } else {
            custom = []
        }
    }

    var all: [Shortcut] { Catalog.builtIn + custom }

    var bar: [Shortcut] {
        let all = self.all
        return barItems.compactMap { id in all.first { $0.id == id } }
    }

    func inBar(_ s: Shortcut) -> Bool { barItems.contains(s.id) }

    func toggleInBar(_ s: Shortcut) {
        if let i = barItems.firstIndex(of: s.id) { barItems.remove(at: i) } else { barItems.append(s.id) }
    }

    func move(_ s: Shortcut, by delta: Int) {
        guard let i = barItems.firstIndex(of: s.id) else { return }
        let j = min(max(i + delta, 0), barItems.count - 1)
        guard i != j else { return }
        barItems.swapAt(i, j)
    }

    func upsert(_ s: Shortcut) {
        if let i = custom.firstIndex(where: { $0.id == s.id }) {
            custom[i] = s
        } else {
            custom.append(s)
            barItems.append(s.id)   // neue eigene Kürzel landen direkt in der Leiste
        }
    }

    func remove(_ s: Shortcut) {
        custom.removeAll { $0.id == s.id }
        barItems.removeAll { $0 == s.id }
    }

    private func saveCustom() {
        if let data = try? JSONEncoder().encode(custom) { defaults.set(data, forKey: "custom") }
    }
}
