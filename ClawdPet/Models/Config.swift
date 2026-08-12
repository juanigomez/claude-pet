import Foundation
import Combine

/// Configuración persistida en `~/Library/Application Support/ClawdPet/config.json`.
struct PetConfig: Codable, Equatable {
    var enabled: Bool = true
    var soundEnabled: Bool = false
    /// Puerto del servidor HTTP local.
    var httpPort: Int = 8787
    /// Corrimiento vertical manual respecto de la altura calculada del Dock.
    var verticalOffset: Double = 0
    var launchAtLogin: Bool = false
    /// Si está activo, la mascota camina sólo sobre el ancho de la tira de íconos del
    /// Dock en lugar de todo el ancho de la pantalla.
    var stayOnDock: Bool = true

    static let `default` = PetConfig()
}

/// Tamaño y velocidad son fijos: menos superficie para configurar, menos formas
/// de que quede en un estado raro. Ver `PetController`/`PetWindowController`.
enum PetConstants {
    /// Escala del pixel-art (1 px del grid = `scale` puntos).
    static let scale: Double = 2
    /// Velocidad de caminata en puntos por segundo.
    static let walkSpeed: Double = 75
}

/// Carga/guarda la config y la publica al resto de la app.
@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: PetConfig {
        didSet {
            guard config != oldValue else { return }
            scheduleSave()
        }
    }

    static let shared = ConfigStore()

    private var saveWorkItem: DispatchWorkItem?

    // `nonisolated`: son rutas puras, se pueden consultar desde cualquier contexto.
    nonisolated static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ClawdPet", isDirectory: true)
    }

    nonisolated static var configURL: URL {
        supportDirectory.appendingPathComponent("config.json")
    }

    private init() {
        let loaded = ConfigStore.load()
        config = loaded ?? .default
        try? FileManager.default.createDirectory(at: ConfigStore.supportDirectory,
                                                 withIntermediateDirectories: true)
        // Primera vez: dejamos el archivo escrito para que se pueda editar a mano.
        if loaded == nil { saveNow() }
    }

    private static func load() -> PetConfig? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(PetConfig.self, from: data)
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    func saveNow() {
        do {
            try FileManager.default.createDirectory(at: ConfigStore.supportDirectory,
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: ConfigStore.configURL, options: .atomic)
        } catch {
            NSLog("[ClawdPet] No se pudo guardar la config: \(error)")
        }
    }
}
