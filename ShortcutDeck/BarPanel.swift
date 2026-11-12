import AppKit
import Combine
import SwiftUI

/// Rahmenloses, nicht aktivierendes Panel für die Leiste: Ein Klick nimmt der
/// Arbeits-App den Fokus nicht weg.
final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class BarController: NSObject, NSWindowDelegate {
    static let shared = BarController()

    private var panel: BarPanel?
    private var bag = Set<AnyCancellable>()
    private let store = ShortcutStore.shared
    private var terminating = false
    private var host: NSView?

    override init() {
        super.init()
        store.$pinned
            .sink { [weak self] pinned in self?.applyPin(pinned) }
            .store(in: &bag)
        Publishers.Merge3(store.$barItems.map { _ in () },
                          store.$showLabels.map { _ in () },
                          Executor.shared.$isTrusted.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.scheduleResize() }
            .store(in: &bag)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.terminating = true } }
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    var frame: NSRect? { panel?.isVisible == true ? panel?.frame : nil }

    /// Nach dem nächsten Layout-Durchlauf an den Inhalt anpassen, obere linke Ecke bleibt.
    private func scheduleResize() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, let host = self.host else { return }
            let size = host.fittingSize
            guard size.width > 0, size.height > 0, size != panel.frame.size else { return }
            let top = panel.frame.maxY
            panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height,
                                  width: size.width, height: size.height), display: true, animate: false)
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let f = panel?.frame else { return }
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: f.minX, y: f.maxY)), forKey: "barTopLeft")
    }

    private func placeDefault(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        panel.setFrameTopLeftPoint(NSPoint(x: screen.midX - size.width / 2, y: screen.maxY - 12))
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        applyPin(store.pinned)
        panel.orderFrontRegardless()
        store.barVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        if !terminating { store.barVisible = false }
    }

    func toggle() { isVisible ? hide() : show() }

    private func applyPin(_ pinned: Bool) {
        guard let panel else { return }
        panel.level = pinned ? .floating : .normal
        panel.isFloatingPanel = pinned
        panel.collectionBehavior = pinned
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.managed, .participatesInCycle]
    }

    private func makePanel() -> BarPanel {
        let panel = BarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "Shortcut Deck"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self

        let host = NSHostingView(rootView: BarView()
            .environmentObject(ShortcutStore.shared)
            .environmentObject(Executor.shared))
        // Größe steuern wir selbst (siehe resizeToFit) – automatische Größe aus dem
        // Inhalt erzeugte zusammen mit Animationen eine Layout-Endlosschleife.
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.host = host

        // Position selbst merken (obere linke Ecke), weil die Größe vom Inhalt kommt.
        let size = host.fittingSize
        panel.setContentSize(size)
        if let saved = UserDefaults.standard.string(forKey: "barTopLeft") {
            let p = NSPointFromString(saved)
            if NSScreen.screens.contains(where: { $0.frame.insetBy(dx: -20, dy: -20).contains(p) }) {
                panel.setFrameTopLeftPoint(p)
            } else {
                placeDefault(panel, size: size)
            }
        } else {
            placeDefault(panel, size: size)
        }
        return panel
    }
}
