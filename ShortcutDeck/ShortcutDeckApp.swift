import AppKit
import SwiftUI

@main
struct ShortcutDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = ShortcutStore.shared
    @StateObject private var executor = Executor.shared

    var body: some Scene {
        // Menüleiste: die Bibliothek zum Zusammenstellen der Leiste.
        MenuBarExtra {
            LibraryView(mode: .menuBar)
                .environmentObject(store)
                .environmentObject(executor)
        } label: {
            Image(systemName: "command.square")
                .accessibilityLabel("Shortcut Deck")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let store = ShortcutStore.shared
            NSApp.appearance = store.appearance.nsAppearance
            _ = Executor.shared
            // Nur für Tests/Automatisierung: mit Dock-Symbol starten.
            if CommandLine.arguments.contains("--regular") { NSApp.setActivationPolicy(.regular) }
            if store.barVisible || CommandLine.arguments.contains("--show-bar") {
                BarController.shared.show()
            }
        }
    }

    /// Erneutes Öffnen im Finder zeigt die Leiste.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { BarController.shared.show() }
        return true
    }
}
