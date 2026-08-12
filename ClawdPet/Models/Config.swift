import Foundation
import Combine

/// Qué pasa con lo que escribís en el campo de texto de la mascota.
enum PromptTarget: String, Codable, CaseIterable, Identifiable {
    /// Corre `claude -p` y muestra la respuesta corta en la burbuja. No necesita
    /// permisos ni API key: reusa tu sesión de Claude Code.
    case bubble
    /// Trae Claude Desktop al frente y pega el texto en el chat. Necesita Accesibilidad.
    case claudeDesktop

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bubble: return "Responder en la burbuja"
        case .claudeDesktop: return "Mandar a Claude Desktop"
        }
    }
}

/// Paleta elegible desde Preferencias.
enum PetTheme: String, Codable, CaseIterable, Identifiable {
    case orange
    case dark
    case light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .orange: return "Naranja"
        case .dark: return "Oscuro"
        case .light: return "Claro"
        }
    }
}

/// Configuración persistida en `~/Library/Application Support/ClawdPet/config.json`.
struct PetConfig: Codable, Equatable {
    var enabled: Bool = true
    /// Velocidad de caminata en puntos por segundo.
    var walkSpeed: Double = 45
    var soundEnabled: Bool = false
    /// Segundos que se muestra el mensaje en la burbuja antes de auto-ocultarse.
    var messageDuration: Double = 8
    /// Puerto del servidor HTTP local.
    var httpPort: Int = 8787
    /// Escala del pixel-art (1 px del grid = `scale` puntos).
    var scale: Double = 4
    /// Corrimiento vertical manual respecto de la altura calculada del Dock.
    var verticalOffset: Double = 0
    var launchAtLogin: Bool = false
    var theme: PetTheme = .orange
    /// Si está activo, la mascota camina sólo sobre el ancho de la tira de íconos del
    /// Dock en lugar de todo el ancho de la pantalla.
    var stayOnDock: Bool = true
    /// Click en la mascota (en idle) abre el campo para preguntarle a Claude.
    var clickOpensPrompt: Bool = true
    var promptTarget: PromptTarget = .bubble

    static let `default` = PetConfig()
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
