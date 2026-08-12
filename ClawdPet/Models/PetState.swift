import Foundation

/// Los tres estados visuales de la mascota.
enum PetState: String, Codable, CaseIterable {
    /// Camina de un lado a otro sobre el Dock.
    case idle
    /// Se queda quieta con la burbuja de "..." animada.
    case thinking
    /// Camina hacia la app que reclama atención y rebota ahí.
    case needsAction
}

/// Hacia dónde mira el sprite.
enum Facing {
    case left, right

    var scaleX: CGFloat { self == .left ? -1 : 1 }
}

/// Payload que acepta el endpoint HTTP local y el CLI.
///
/// ```json
/// { "app": "claude-code", "state": "needs_action" }
/// ```
struct NotifyPayload: Codable {
    /// Alias, bundle id o nombre de la app. Opcional: si viene `pid` se ignora.
    var app: String?
    var state: String
    /// PID del proceso que manda el aviso (lo pone el hook con `$$`). Con esto la app
    /// sube por el árbol de procesos y descubre sola de qué terminal/editor viene,
    /// sin que haya que configurar bundle ids. Ver `ProcessTree`.
    var pid: Int32?

    enum CodingKeys: String, CodingKey {
        case app, state, pid
    }

    init(app: String? = nil, state: String = "", pid: Int32? = nil) {
        self.app = app
        self.state = state
        self.pid = pid
    }

    /// Decodificación tolerante: el cuerpo puede ser el JSON crudo de Claude Code, que
    /// no trae `state` (ese viene por query string). Nada es obligatorio.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = try c.decodeIfPresent(String.self, forKey: .app)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
    }

    /// Acepta `needs_action`, `needsAction` y `needs-action` indistintamente.
    var petState: PetState? {
        switch state.lowercased().replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "") {
        case "idle", "done", "reset": return .idle
        case "thinking", "working", "busy": return .thinking
        case "needsaction", "alert", "attention", "waiting": return .needsAction
        default: return nil
        }
    }
}

struct NotifyResponse: Codable {
    var ok: Bool
    var state: String?
    var app: String?
    var error: String?
    /// Sólo en `/health`: si falta, la mascota no puede ubicar ventanas ni medir el Dock.
    var accessibility: Bool?
    /// Sólo en `/health`: tira de íconos del Dock detectada, para diagnosticar el
    /// límite del paseo. `nil` si no hay permiso o el Dock no está abajo.
    var dock: String?
    /// Sólo en `/health`: qué está haciendo la mascota ahora mismo. Diagnóstico.
    var pet: String?
}
