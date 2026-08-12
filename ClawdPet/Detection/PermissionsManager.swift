import AppKit
import ApplicationServices
import Combine

/// Maneja el permiso de Accesibilidad, que sólo hace falta para el estado
/// "necesita tu acción" (ubicar la ventana frontal de otra app).
///
/// La app funciona sin el permiso: si no está concedido, la mascota rebota donde
/// esté en vez de caminar hasta la ventana de la app.
@MainActor
final class PermissionsManager: ObservableObject {

    static let shared = PermissionsManager()

    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private var pollTimer: Timer?

    private init() {}

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
    }

    /// Muestra el diálogo del sistema pidiendo el permiso y empieza a chequear
    /// si el usuario lo concede (el sistema no avisa por notificación).
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        guard !isTrusted else { return }
        startPolling()
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        startPolling()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.refresh()
                if self.isTrusted { timer.invalidate(); self.pollTimer = nil }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// Por qué a veces "ya lo di" y sigue apareciendo en rojo.
    static let staleGrantExplanation = """
    macOS asocia el permiso a la firma del binario, no a su ruta. Cada vez que \
    recompilás, la firma ad-hoc cambia y el permiso que habías dado deja de aplicar \
    aunque el switch siga encendido en Ajustes.

    Además `AXIsProcessTrusted()` queda cacheado dentro del proceso: si concediste el \
    permiso con la app ya abierta, hace falta reiniciarla para que lo vea.

    Receta: en Ajustes ▸ Privacidad y seguridad ▸ Accesibilidad, quitá ClawdPet con \
    «−», volvé a agregarlo con «+», y reiniciá la app acá abajo.
    """

    /// Texto que se muestra en Preferencias cuando falta el permiso.
    static let explanation = """
    Claw'd Pet usa Accesibilidad para tres cosas: leer dónde está la ventana de la app \
    que te reclama algo, medir el ancho real del Dock para no pasarse de largo, y \
    escribir el texto en Claude Desktop cuando le preguntás algo desde la burbuja.

    Sin el permiso el resto sigue andando: la mascota rebota donde esté en vez de \
    moverse hacia la app, camina sobre todo el ancho de la pantalla, y el texto que le \
    escribas queda copiado en el portapapeles para que lo pegues vos.
    """
}
