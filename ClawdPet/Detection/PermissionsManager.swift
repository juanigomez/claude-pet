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
    macOS ties the permission to the binary's signature, not its path. Every time you \
    rebuild, the ad-hoc signature changes and the permission you granted stops applying \
    even though the switch is still on in Settings.

    Also, `AXIsProcessTrusted()` is cached inside the process: if you granted the \
    permission while the app was already open, it needs a restart to see it.

    Fix: in Settings ▸ Privacy & Security ▸ Accessibility, remove ClawdPet with "−", \
    add it back with "+", and restart the app below.
    """

    /// Texto que se muestra en Preferencias cuando falta el permiso.
    static let explanation = """
    Claw'd Pet uses Accessibility for two things: reading where the window of the app \
    that needs you is, and measuring the real width of the Dock so it doesn't wander \
    past it.

    Everything else still works without the permission: the mascot bounces wherever it \
    is instead of moving to the app, and it walks across the whole width of the screen.
    """
}
