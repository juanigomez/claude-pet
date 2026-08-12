import Foundation

/// Los tres estados visuales de la mascota.
enum PetState: String, Codable, CaseIterable {
    /// Camina de un lado a otro sobre el Dock.
    case idle
    /// Se queda quieta con la burbuja de "..." animada.
    case thinking
    /// Camina hacia la app que reclama atención y rebota ahí.
    case needsAction

    var displayName: String {
        switch self {
        case .idle: return "Idle (caminando)"
        case .thinking: return "Pensando"
        case .needsAction: return "Necesita tu acción"
        }
    }
}

/// Hacia dónde mira el sprite.
enum Facing {
    case left, right

    var scaleX: CGFloat { self == .left ? -1 : 1 }
}

/// Payload que acepta el endpoint HTTP local y el CLI.
///
/// ```json
/// { "app": "claude-code", "state": "needs_action", "message": "Necesito tu OK" }
/// ```
struct NotifyPayload: Codable {
    /// Alias, bundle id o nombre de la app. Opcional: si viene `pid` se ignora.
    var app: String?
    var state: String
    var message: String?
    /// Segundos que dura el mensaje en la burbuja. Si es nil se usa el valor de la config.
    var duration: Double?
    /// PID del proceso que manda el aviso (lo pone el hook con `$$`). Con esto la app
    /// sube por el árbol de procesos y descubre sola de qué terminal/editor viene,
    /// sin que haya que configurar bundle ids. Ver `ProcessTree`.
    var pid: Int32?

    // ── Campos que reenvía el hook tal cual se los pasa Claude Code ──
    // Sin esto la burbuja sólo puede decir "Necesito tu OK", que no te dice para qué.
    var hookEventName: String?
    var toolName: String?
    var toolInput: ToolInput?

    struct ToolInput: Codable {
        var command: String?
        var description: String?
        var filePath: String?
        var pattern: String?
        var url: String?

        enum CodingKeys: String, CodingKey {
            case command, description, pattern, url
            case filePath = "file_path"
        }
    }

    enum CodingKeys: String, CodingKey {
        case app, state, message, duration, pid
        case hookEventName = "hook_event_name"
        case toolName = "tool_name"
        case toolInput = "tool_input"
    }

    init(app: String? = nil, state: String = "", message: String? = nil,
         duration: Double? = nil, pid: Int32? = nil) {
        self.app = app
        self.state = state
        self.message = message
        self.duration = duration
        self.pid = pid
    }

    /// Decodificación tolerante: el cuerpo puede ser el JSON crudo de Claude Code, que
    /// no trae `state` (ese viene por query string). Nada es obligatorio.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = try c.decodeIfPresent(String.self, forKey: .app)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        message = try c.decodeIfPresent(String.self, forKey: .message)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
        hookEventName = try c.decodeIfPresent(String.self, forKey: .hookEventName)
        toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        toolInput = try? c.decodeIfPresent(ToolInput.self, forKey: .toolInput)
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

    /// Qué mostrar en la burbuja. Prioridad: el mensaje explícito, después el texto que
    /// ya redactó Claude Code (`Notification`), y por último un resumen de la
    /// herramienta que quiere correr (`PermissionRequest`).
    var displayMessage: String? {
        if let message, !message.isEmpty { return shortened(message) }
        guard let toolName else { return nil }

        if let input = toolInput {
            // Para Bash la descripción es lo más legible; si no, el comando.
            if toolName == "Bash", let description = input.description, !description.isEmpty {
                return shortened(description)
            }
            if let command = input.command, !command.isEmpty {
                return shortened(command)
            }
            if let path = input.filePath, !path.isEmpty {
                return "\(toolName) · \((path as NSString).lastPathComponent)"
            }
            if let pattern = input.pattern, !pattern.isEmpty {
                return "\(toolName) · \(shortened(pattern))"
            }
            if let url = input.url, !url.isEmpty {
                return "\(toolName) · \(shortened(url))"
            }
        }
        return toolName
    }

    /// La burbuja son dos líneas, no un log.
    private func shortened(_ text: String, limit: Int = 90) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count <= limit ? flat : String(flat.prefix(limit)) + "…"
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
