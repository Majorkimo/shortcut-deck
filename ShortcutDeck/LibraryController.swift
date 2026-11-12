import AppKit
import SwiftUI

/// Fenster „Leiste zusammenstellen“: öffnet sich direkt an der Leiste.
@MainActor
final class LibraryController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = LibraryController()

    @Published private(set) var isOpen = false
    private var panel: BarPanel?

    func toggle() { isOpen ? close() : show() }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.level = ShortcutStore.shared.pinned ? .floating : .normal
        panel.orderFrontRegardless()
        panel.makeKey()
        isOpen = true
    }

    func close() {
        panel?.orderOut(nil)
        isOpen = false
    }

    func windowWillClose(_ notification: Notification) { isOpen = false }

    /// Unter der Leiste, wenn Platz ist, sonst darüber; rechtsbündig zur Leiste.
    private func position(_ panel: NSPanel) {
        guard let bar = BarController.shared.frame,
              let screen = (NSScreen.screens.first { $0.frame.intersects(bar) } ?? NSScreen.main)?.visibleFrame
        else { panel.center(); return }
        let size = panel.frame.size
        var x = bar.maxX - size.width
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        var y = bar.minY - size.height - 8
        if y < screen.minY { y = bar.maxY + 8 }
        y = min(max(y, screen.minY + 8), screen.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func makePanel() -> BarPanel {
        let panel = BarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "Leiste zusammenstellen"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        let host = NSHostingView(rootView: LibraryView(mode: .window)
            .environmentObject(ShortcutStore.shared)
            .environmentObject(Executor.shared))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
        return panel
    }
}
