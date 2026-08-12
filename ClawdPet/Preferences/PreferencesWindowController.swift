import AppKit
import SwiftUI

/// Ventana de Preferencias hecha a mano.
///
/// Se usa un `NSWindow` propio en vez del scene `Settings` de SwiftUI porque en una
/// app `LSUIElement` abrir Settings depende de selectores privados que cambiaron
/// entre versiones de macOS (`showPreferencesWindow:` / `showSettingsWindow:`).
@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {

    convenience init(coordinator: AppCoordinator) {
        let view = PreferencesView(coordinator: coordinator, store: coordinator.store)
        let hosting = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: hosting)
        window.title = "Claw'd Pet"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 480, height: 392))
        window.center()

        self.init(window: window)
        window.delegate = self
    }

    func show() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        // La app es accessory (sin ícono en el Dock): sin `activate` la ventana se abre
        // detrás de la app que tengas adelante. El `orderFrontRegardless` de después
        // cubre el caso en que `activate` llegue tarde (pasa al llamar a `show()` muy
        // temprano, durante el arranque).
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        // Persistimos ya, sin esperar el debounce.
        ConfigStore.shared.saveNow()
        // Ojo: nada de `NSApp.hide(nil)` acá — escondería también la ventana de la mascota.
    }
}
