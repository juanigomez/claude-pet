import AppKit
import SwiftUI
import Combine

/// Crea y mantiene la ventana-franja donde camina la mascota.
///
/// La ventana ocupa TODO el ancho de la pantalla en una franja de abajo (en vez de ser
/// una ventanita que se mueve con la mascota). Ventajas:
///  - la animación es SwiftUI puro, sin mover un `NSWindow` 60 veces por segundo;
///  - no hay parpadeos ni desfasajes al cruzar la pantalla.
/// El costo es que la franja cubriría el Dock entero, así que `ignoresMouseEvents`
/// se activa/desactiva según el cursor esté o no encima de la mascota.
@MainActor
final class PetWindowController {

    private var panel: PetPanel?
    private let controller: PetController
    private let store: ConfigStore

    /// Rect clickeable en coordenadas de la ventana (origen abajo-izquierda, y hacia arriba).
    private var hitRectInWindow: CGRect = .zero
    private var mouseTimer: Timer?
    private var geometryTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastIgnoresMouse = true

    /// Margen extra alrededor de la mascota para que sea fácil de clickear.
    private let hitPadding: CGFloat = 6

    init(controller: PetController, store: ConfigStore) {
        self.controller = controller
        self.store = store

        // `receive(on:)` no es decorativo: `@Published` publica en `willSet`, así que
        // dentro del sink `store.config` todavía tiene el valor VIEJO. Diferir un turno
        // de runloop garantiza que los closures lean la config ya actualizada.
        store.$config
            .map(\.enabled)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                enabled ? self?.show() : self?.hide()
            }
            .store(in: &cancellables)

        store.$config
            .map(\.verticalOffset)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateGeometry() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateGeometry() }
        }
    }

    // MARK: - Mostrar / ocultar

    func show() {
        if panel == nil { buildPanel() }
        updateGeometry()
        panel?.orderFrontRegardless()
        controller.start()
        startTimers()
    }

    func hide() {
        panel?.orderOut(nil)
        controller.stop()
        stopTimers()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Construcción

    private func buildPanel() {
        let panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 200))
        let root = PetRootView(controller: controller) { [weak self] rect in
            self?.updateHitRect(rect)
        }
        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel
    }

    // MARK: - Geometría

    /// Pantalla donde vive la mascota: la que tiene el mouse, o la principal.
    private var targetScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func updateGeometry() {
        guard let panel, let screen = targetScreen else { return }

        let screenFrame = screen.frame
        let visible = screen.visibleFrame
        // Alto del Dock cuando está abajo (0 si está a los costados o auto-oculto).
        let dockHeight = max(0, visible.minY - screenFrame.minY)

        let scale = PetConstants.scale
        let spriteSide = Double(ClawdSprite.gridSize) * scale
        // **Todo entero.** Si la franja mide alto fraccionario, el sprite termina
        // dibujado en medio píxel y el pixel-art se ve borroso y "torcido".
        // Con `floorY`, `stripHeight` y `spriteSide` enteros, la posición final del
        // sprite en pantalla cae siempre en un punto entero.
        let floorY = max(0, (dockHeight + store.config.verticalOffset).rounded())
        // Lugar reservado arriba para la burbuja de "pensando": es la única que existe
        // y su tamaño es fijo (no hay texto que crezca), así que alcanza con una
        // estimación en base a la escala.
        let overhead = spriteSide * 1.8 + 16
        let stripHeight = (floorY + spriteSide + overhead).rounded(.up)

        let newFrame = NSRect(x: screenFrame.minX,
                              y: screenFrame.minY,
                              width: screenFrame.width,
                              height: stripHeight)

        if panel.frame != newFrame {
            panel.setFrame(newFrame, display: true)
            DockLocator.invalidateCache()
        }

        var layout = controller.layout
        layout.width = Double(screenFrame.width)
        layout.height = stripHeight
        layout.floorY = floorY
        layout.scale = scale
        if controller.layout != layout {
            controller.layout = layout
        }
        controller.layoutOriginX = Double(screenFrame.minX)
    }

    // MARK: - `ignoresMouseEvents` dinámico

    /// `rect` viene en coordenadas SwiftUI (origen arriba-izquierda, y hacia abajo).
    private func updateHitRect(_ rect: CGRect) {
        guard let panel else { return }
        let h = panel.frame.height
        hitRectInWindow = CGRect(x: rect.minX,
                                 y: h - rect.maxY,
                                 width: rect.width,
                                 height: rect.height)
            .insetBy(dx: -hitPadding, dy: -hitPadding)
    }

    private func startTimers() {
        stopTimers()

        // Chequear la posición del mouse. Usamos polling en vez de un monitor global
        // de eventos porque es más confiable con la ventana no-activable y no necesita
        // ningún permiso extra.
        let mouseTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouseTransparency() }
        }
        RunLoop.main.add(mouseTimer, forMode: .common)
        self.mouseTimer = mouseTimer

        // El Dock puede aparecer/desaparecer (auto-hide) sin notificación; lo miramos
        // cada tanto para reacomodar la franja.
        let geometryTimer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateGeometry() }
        }
        RunLoop.main.add(geometryTimer, forMode: .common)
        self.geometryTimer = geometryTimer
    }

    private func stopTimers() {
        mouseTimer?.invalidate(); mouseTimer = nil
        geometryTimer?.invalidate(); geometryTimer = nil
    }

    private func updateMouseTransparency() {
        guard let panel, panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation                     // pantalla, y hacia arriba
        let local = CGPoint(x: mouse.x - panel.frame.minX,
                            y: mouse.y - panel.frame.minY)    // ventana, y hacia arriba
        let overPet = hitRectInWindow.contains(local)
        let shouldIgnore = !overPet
        if shouldIgnore != lastIgnoresMouse {
            lastIgnoresMouse = shouldIgnore
            panel.ignoresMouseEvents = shouldIgnore
        }
    }
}
