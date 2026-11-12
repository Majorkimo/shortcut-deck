import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Führt Kürzel aus: entweder über einen direkten Systemaufruf oder,
/// nachdem die zuletzt aktive App wieder vorne ist, per CGEvent.
@MainActor
final class Executor: ObservableObject {
    static let shared = Executor()

    struct Feedback: Equatable {
        var text: String
        var ok: Bool
        var shortcutID: String? = nil
        var id = UUID()
    }

    @Published private(set) var lastExternalApp: NSRunningApplication?
    @Published var feedback: Feedback?
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    private var trustTimer: Timer?

    private init() {
        let me = Bundle.main.bundleIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != me {
            lastExternalApp = front
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != me else { return }
            MainActor.assumeIsolated { self?.lastExternalApp = app }
        }
        startTrustPolling()
    }

    // MARK: Bedienungshilfen

    /// Zeigt den System-Dialog „… möchte diesen Computer steuern“.
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        startTrustPolling()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startTrustPolling() {
        trustTimer?.invalidate()
        guard !isTrusted else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.isTrusted = AXIsProcessTrusted()
                if self.isTrusted { timer.invalidate() }
            }
        }
    }

    // MARK: Ausführen

    /// - Parameter dismiss: schließt das Menüleisten-Fenster, bevor das Kürzel gesendet wird.
    func run(_ shortcut: Shortcut, dismiss: (() -> Void)? = nil) {
        dismiss?()
        currentID = shortcut.id

        if let action = shortcut.system, runSystem(action) {
            report("\(shortcut.name) ausgelöst", ok: true)
            return
        }
        guard let combo = shortcut.combo else {
            report("\(shortcut.name): kein Kürzel hinterlegt", ok: false)
            return
        }
        guard AXIsProcessTrusted() else {
            isTrusted = false
            report("Bedienungshilfen-Freigabe fehlt", ok: false)
            requestAccessibility()
            return
        }
        guard let keyCode = combo.key.keyCode else {
            report("Taste „\(combo.key.label)“ gibt es im aktuellen Layout nicht", ok: false)
            return
        }

        let target: NSRunningApplication?
        switch shortcut.delivery {
        case .finder:
            target = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        case .frontApp, .global:
            target = lastExternalApp
        }

        Task { @MainActor in
            if let target { await self.focus(target) }
            switch shortcut.delivery {
            case .global:
                Self.postGlobal(keyCode: keyCode, mods: combo.mods)
            case .frontApp, .finder:
                if let pid = target?.processIdentifier {
                    Self.post(keyCode: keyCode, mods: combo.mods, pid: pid)
                } else {
                    Self.postGlobal(keyCode: keyCode, mods: combo.mods)
                }
            }
            let where_ = (shortcut.delivery == .global) ? "" : " → \(target?.localizedName ?? "aktive App")"
            self.report("\(shortcut.name) \(combo.display)\(where_)", ok: true)
        }
    }

    private var currentID: String?

    private func report(_ text: String, ok: Bool) {
        feedback = Feedback(text: text, ok: ok, shortcutID: currentID)
    }

    /// Holt die Ziel-App nach vorne und wartet, bis sie wirklich aktiv ist.
    private func focus(_ app: NSRunningApplication) async {
        if NSApp.isActive {
            NSApp.yieldActivation(to: app)
            NSApp.deactivate()
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            app.activate(options: [])
        }
        for _ in 0..<25 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        try? await Task.sleep(nanoseconds: 60_000_000)
    }

    // MARK: CGEvent

    private static let modifierKeys: [(Mods, Int)] = [
        (.command, kVK_Command), (.shift, kVK_Shift), (.option, kVK_Option), (.control, kVK_Control),
    ]

    /// Systemweite Hotkeys: Modifier wirklich drücken und loslassen (wichtig für ⌘⇥).
    static func postGlobal(keyCode: CGKeyCode, mods: Mods) {
        let src = CGEventSource(stateID: .hidSystemState)
        var flags: CGEventFlags = []
        let pressed = modifierKeys.filter { mods.contains($0.0) }
        for (m, code) in pressed {
            flags.insert(Mods(rawValue: m.rawValue).cgFlags)
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: true)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
        for (m, code) in pressed.reversed() {
            flags.remove(m.cgFlags)
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: false)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Menübefehle direkt an den Prozess der Ziel-App.
    static func post(keyCode: CGKeyCode, mods: Mods, pid: pid_t) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        down?.flags = mods.cgFlags
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        up?.flags = mods.cgFlags
        down?.postToPid(pid)
        up?.postToPid(pid)
    }

    // MARK: Systemaufrufe

    private func runSystem(_ action: SystemAction) -> Bool {
        switch action {
        case .lockScreen:
            return Self.lockScreen()
        case .screenshotTool:
            return Self.openApp("/System/Applications/Utilities/Screenshot.app")
        case .missionControl:
            return Self.openApp("/System/Applications/Mission Control.app")
        case .sleep:
            return Self.launch("/usr/bin/pmset", ["sleepnow"])
        case .displaySleep:
            return Self.launch("/usr/bin/pmset", ["displaysleepnow"])
        }
    }

    private static func openApp(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
        return true
    }

    private static func launch(_ path: String, _ args: [String]) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do { try p.run(); return true } catch { return false }
    }

    /// Sofort sperren über login.framework (wie das Apple-Menü). Fällt sonst auf ⌃⌘Q zurück.
    private static func lockScreen() -> Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
              let sym = dlsym(handle, "SACLockScreenImmediate") else { return false }
        typealias Fn = @convention(c) () -> Int32
        _ = unsafeBitCast(sym, to: Fn.self)()
        return true
    }
}
