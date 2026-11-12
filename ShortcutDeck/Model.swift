import AppKit
import Carbon.HIToolbox

// MARK: - Taste + Modifikatoren

/// Eine Taste. Buchstaben/Ziffern/Satzzeichen werden über das aktuelle
/// Tastaturlayout in einen Keycode übersetzt (QWERTZ: ⌘Z bleibt ⌘Z).
/// Sondertasten (Leertaste, Pfeile …) haben einen festen Keycode.
enum Key: Codable, Hashable {
    case char(String)
    case code(UInt16, label: String)

    var keyCode: CGKeyCode? {
        switch self {
        case .char(let c): return KeyLayout.keyCode(for: c)
        case .code(let code, _): return CGKeyCode(code)
        }
    }

    var label: String {
        switch self {
        case .char(let c): return c.uppercased()
        case .code(let code, let label):
            return label.isEmpty ? (KeyLayout.character(for: CGKeyCode(code))?.uppercased() ?? "?") : label
        }
    }

    static let space = Key.code(UInt16(kVK_Space), label: "Leertaste")
    static let tab = Key.code(UInt16(kVK_Tab), label: "⇥")
    static let delete = Key.code(UInt16(kVK_Delete), label: "⌫")
    static let escape = Key.code(UInt16(kVK_Escape), label: "⎋")
    static let up = Key.code(UInt16(kVK_UpArrow), label: "↑")
    static let down = Key.code(UInt16(kVK_DownArrow), label: "↓")
    static let f11 = Key.code(UInt16(kVK_F11), label: "F11")
    /// Taste links neben der 1 bzw. „Nächstes Fenster“ (Keycode-basiert).
    static let backtick = Key.code(UInt16(kVK_ANSI_Grave), label: "")
}

struct Mods: OptionSet, Codable, Hashable {
    let rawValue: Int
    static let control = Mods(rawValue: 1 << 0)
    static let option = Mods(rawValue: 1 << 1)
    static let shift = Mods(rawValue: 1 << 2)
    static let command = Mods(rawValue: 1 << 3)

    /// Apple-Reihenfolge ⌃⌥⇧⌘
    var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }

    var cgFlags: CGEventFlags {
        var f: CGEventFlags = []
        if contains(.control) { f.insert(.maskControl) }
        if contains(.option) { f.insert(.maskAlternate) }
        if contains(.shift) { f.insert(.maskShift) }
        if contains(.command) { f.insert(.maskCommand) }
        return f
    }

    init(rawValue: Int) { self.rawValue = rawValue }

    init(_ flags: NSEvent.ModifierFlags) {
        var m: Mods = []
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.command) { m.insert(.command) }
        self = m
    }
}

struct KeyCombo: Codable, Hashable {
    var mods: Mods
    var key: Key
    var display: String { mods.symbols + key.label }
}

// MARK: - Direkte Systemaufrufe

enum SystemAction: String, Codable {
    case lockScreen, screenshotTool, missionControl, sleep, displaySleep
}

// MARK: - Gruppen

enum ShortcutGroup: String, Codable, CaseIterable, Identifiable {
    case system, window, text, screenshots, finder, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .window: "Fenster"
        case .text: "Text"
        case .screenshots: "Screenshots"
        case .finder: "Finder"
        case .custom: "Eigene"
        }
    }

    var symbol: String {
        switch self {
        case .system: "gearshape.2"
        case .window: "macwindow"
        case .text: "textformat"
        case .screenshots: "camera.viewfinder"
        case .finder: "folder"
        case .custom: "star.square"
        }
    }

    var tint: NSColor {
        switch self {
        case .system: .systemBlue
        case .window: .systemIndigo
        case .text: .systemOrange
        case .screenshots: .systemPink
        case .finder: .systemTeal
        case .custom: .systemGreen
        }
    }
}

/// Wohin die Tastendrücke gehen.
enum Delivery: String, Codable {
    /// Systemweiter Hotkey (Spotlight, ⌘⇥, Screenshots): über das HID-Event-Tap.
    case global
    /// Menübefehl der zuletzt aktiven App: App aktivieren, dann direkt an deren Prozess.
    case frontApp
    /// Immer an den Finder.
    case finder
}

struct Shortcut: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var group: ShortcutGroup
    var combo: KeyCombo?
    var system: SystemAction? = nil
    var delivery: Delivery = .frontApp
    var keywords: String = ""

    var comboText: String { combo?.display ?? "" }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        let hay = "\(name) \(keywords) \(group.title) \(comboText)".lowercased()
        return q.split(separator: " ").allSatisfy { hay.contains($0) }
    }
}

// MARK: - Tastaturlayout

enum KeyLayout {
    /// Zeichen → Keycode im aktuellen Layout (Cache wird bei Layoutwechsel neu gebaut).
    static func keyCode(for ch: String) -> CGKeyCode? {
        let target = ch.lowercased()
        for code in 0..<128 {
            if character(for: CGKeyCode(code))?.lowercased() == target { return CGKeyCode(code) }
        }
        return nil
    }

    static func character(for keyCode: CGKeyCode) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var dead: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                        &dead, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            let s = String(utf16CodeUnits: chars, count: length)
            return s.trimmingCharacters(in: .controlCharacters).isEmpty ? nil : s
        }
    }
}
