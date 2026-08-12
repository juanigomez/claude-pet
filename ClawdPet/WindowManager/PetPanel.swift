import AppKit

/// Ventana flotante de la mascota.
///
/// ### Sobre el nivel de ventana
/// El Dock vive en `kCGDockWindowLevel` (= 20). Los niveles públicos de `NSWindow.Level`
/// mapean así:
///
/// | Nivel                | raw | ¿arriba del Dock? |
/// |----------------------|-----|-------------------|
/// | `.floating`          | 3   | no                |
/// | `.mainMenu`          | 24  | sí (pero tapa el menú) |
/// | `.statusBar`         | 25  | **sí**            |
/// | `.popUpMenu`         | 101 | sí (tapa menús contextuales) |
/// | `.screenSaver`       | 1000| sí (tapa TODO, incluido Spotlight) |
///
/// Elegimos **`.statusBar` (25)**: es el nivel público más bajo que queda por encima
/// del Dock, y a la vez sigue estando por debajo de `.popUpMenu`, así que los menús
/// contextuales, Spotlight y las hojas de sistema se dibujan sobre la mascota en
/// lugar de quedar tapados. `.screenSaver` también funciona pero es demasiado
/// agresivo: la mascota terminaría flotando encima de diálogos modales.
///
/// Si en tu setup querés que quede aún más arriba, cambiá `PetPanel.preferredLevel`.
final class PetPanel: NSPanel {

    /// Nivel elegido. Ver la nota de arriba antes de tocarlo.
    static let preferredLevel: NSWindow.Level = .statusBar

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = PetPanel.preferredLevel

        // Visible en todos los espacios, no se mueve al cambiar de Space, y aparece
        // también sobre apps en pantalla completa.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Por defecto es "transparente al mouse": sólo se activa cuando el cursor
        // está encima de la mascota o la burbuja (ver PetWindowController).
        ignoresMouseEvents = true
    }

    /// Normalmente la mascota nunca roba el foco. La excepción es el campo de texto
    /// para preguntarle a Claude: mientras está abierto el panel tiene que poder ser
    /// *key* para recibir teclas. Como es un `.nonactivatingPanel`, recibe el teclado
    /// **sin** activar la app ni sacarle el foco a tu editor (igual que Spotlight).
    var acceptsKeyInput = false {
        didSet {
            guard acceptsKeyInput != oldValue else { return }
            if acceptsKeyInput {
                makeKeyAndOrderFront(nil)
            } else if isKeyWindow {
                resignKey()
                orderFrontRegardless()
            }
        }
    }

    override var canBecomeKey: Bool { acceptsKeyInput }
    override var canBecomeMain: Bool { false }
}
