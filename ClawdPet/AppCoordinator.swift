import AppKit
import Combine

/// Punto central: arma la mascota, la ventana flotante y el servidor de avisos,
/// y los mantiene sincronizados con la config.
@MainActor
final class AppCoordinator: ObservableObject {

    let store: ConfigStore
    let controller: PetController
    private(set) lazy var windowController = PetWindowController(controller: controller, store: store)

    private let server = NotifyServer()

    @Published private(set) var serverStatusText: String = "iniciando…"
    @Published private(set) var isServerRunning: Bool = false
    @Published private(set) var hookScriptURL: URL?

    private var cancellables = Set<AnyCancellable>()

    init(store: ConfigStore) {
        self.store = store
        self.controller = PetController(store: store)
    }

    func start() {
        hookScriptURL = HookScript.ensureInstalled()

        server.onPayload = { [weak self] payload in
            self?.controller.apply(payload)
        }
        // El controller empuja su estado al servidor (ver `NotifyServer.updateDiagnostics`).
        controller.onDiagnostics = { [weak self] snapshot in
            self?.server.updateDiagnostics(snapshot)
        }
        server.onStatusChange = { [weak self] status in
            guard let self else { return }
            self.serverStatusText = status.description
            if case .running = status { self.isServerRunning = true } else { self.isServerRunning = false }
            NSLog("[ClawdPet] servidor de avisos: %@", status.description)
        }
        server.start(port: store.config.httpPort)

        // Si cambia el puerto en Preferencias, reiniciamos solos (con un respiro
        // para no reabrir el socket en cada tecla que escribís).
        store.$config
            .map(\.httpPort)
            .removeDuplicates()
            .debounce(for: .seconds(1.0), scheduler: RunLoop.main)
            .dropFirst()
            .sink { [weak self] port in self?.server.start(port: port) }
            .store(in: &cancellables)

        // Mantener el toggle de login item en sincronía con la realidad del sistema.
        store.config.launchAtLogin = LoginItemManager.isEnabled

        if store.config.enabled {
            windowController.show()
        }

        PermissionsManager.shared.refresh()
        // Si falta el permiso, disparamos el diálogo del sistema. Además de pedirlo,
        // es lo que **registra la app en la lista** de Ajustes ▸ Accesibilidad:
        // agregarla a mano con «+» no siempre funciona para apps accessory.
        if !PermissionsManager.shared.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                PermissionsManager.shared.requestAccess()
            }
        }
    }

    func stop() {
        server.stop()
        windowController.hide()
        store.saveNow()
    }

    func restartServer() {
        server.start(port: store.config.httpPort)
    }

    /// Instala CLI + hook y engancha los hooks de Claude Code de una.
    /// Devuelve un resumen legible para mostrar en Preferencias.
    func installEverything() -> String {
        switch CLIInstaller.install() {
        case .failure(let error):
            return "No pude instalar el CLI: \(error.localizedDescription)"
        case .success:
            break
        }
        do {
            let report = try ClaudeCodeHooks.install(cliDirectory: CLIInstaller.installedDirectory)
            var lines = ["Listo. `clawdpet` y `clawdpet-hook` quedaron en \(CLIInstaller.installedDirectory.path)."]
            if report.replaced.isEmpty {
                lines.append("Hooks agregados: \(ClaudeCodeHooks.mapping.map(\.event).joined(separator: ", ")).")
            } else {
                lines.append("Hooks actualizados: \(report.replaced.joined(separator: ", ")).")
            }
            if report.kept > 0 {
                lines.append("Se conservaron \(report.kept) hooks tuyos que no eran de Claw'd Pet.")
            }
            if let backup = report.backupPath {
                lines.append("Backup: \((backup as NSString).lastPathComponent)")
            }
            lines.append("Abrí una sesión nueva de Claude Code para que tome los hooks.")
            return lines.joined(separator: "\n")
        } catch {
            return "CLI instalado, pero fallaron los hooks: \(error.localizedDescription)"
        }
    }

    /// Relanza la app. Hace falta después de conceder Accesibilidad, porque
    /// `AXIsProcessTrusted()` queda cacheado por proceso.
    func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        stop()
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
