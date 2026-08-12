import Foundation

/// Escribe los hooks de Claw'd Pet en la config de Claude Code.
///
/// Toca `~/.claude/settings.json`, que es un archivo tuyo: por eso siempre deja un
/// backup con timestamp antes de escribir, y sólo reemplaza las entradas cuyo comando
/// contiene `clawdpet-hook` — cualquier otro hook que tengas se conserva.
enum ClaudeCodeHooks {

    static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    /// Eventos que enchufamos, con el comando que corre cada uno.
    ///
    /// El orden real de Claude Code para una herramienta que pide permiso es:
    ///
    /// ```
    /// UserPromptSubmit → PreToolUse → [aparece el prompt] → PermissionRequest
    ///                  → [respondés] → PostToolUse → … → Stop
    /// ```
    ///
    /// Dos detalles que importan y que es fácil equivocar:
    ///
    /// - **`PreToolUse` corre ANTES de que aparezca el prompt**, no después de que
    ///   respondas. Usarlo para salir del estado de alerta no sirve: nunca vuelve a
    ///   dispararse mientras esperás. Por eso no está en esta lista.
    /// - **`PermissionRequest` es el prompt mismo**, así que es lo que da el aviso en
    ///   el instante exacto en que Claude te pide algo. `Notification` es un evento
    ///   genérico y llega más tarde; lo dejamos igual porque cubre otros avisos (por
    ///   ejemplo cuando queda esperando input un rato largo).
    /// - **`PostToolUse` corre justo después de que aprobás** y la herramienta termina:
    ///   ese es el que saca a la mascota del salto.
    static let mapping: [(event: String, command: String)] = [
        ("UserPromptSubmit", "clawdpet-hook thinking"),
        // Sin mensaje literal: el hook reenvía el JSON de Claude Code y la burbuja
        // muestra qué te está pidiendo (la notificación o la herramienta concreta).
        ("PermissionRequest", "clawdpet-hook needs_action"),
        ("Notification", "clawdpet-hook needs_action"),
        ("PostToolUse", "clawdpet-hook thinking"),
        ("Stop", "clawdpet-hook idle")
    ]

    struct Report {
        var backupPath: String?
        var replaced: [String] = []
        var kept: Int = 0
    }

    enum HookError: LocalizedError {
        case unreadable(String)
        case unwritable(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let detail): return "No pude leer settings.json: \(detail)"
            case .unwritable(let detail): return "No pude escribir settings.json: \(detail)"
            }
        }
    }

    static func install(cliDirectory: URL,
                        settingsURL: URL = defaultSettingsURL) throws -> Report {
        let fm = FileManager.default
        var report = Report()

        var root: [String: Any] = [:]
        if fm.fileExists(atPath: settingsURL.path) {
            let data = try Data(contentsOf: settingsURL)
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HookError.unreadable("no es JSON válido")
            }
            root = parsed

            // Backup antes de tocar nada.
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let backup = settingsURL.deletingLastPathComponent()
                .appendingPathComponent("settings.json.clawdpet-backup-\(stamp)")
            try data.write(to: backup, options: .atomic)
            report.backupPath = backup.path
        } else {
            try fm.createDirectory(at: settingsURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        // Ruta absoluta: los hooks de Claude Code no heredan necesariamente tu PATH.
        let hookBinary = cliDirectory.appendingPathComponent("clawdpet-hook").path

        func isOurs(_ entry: [String: Any]) -> Bool {
            let inner = entry["hooks"] as? [[String: Any]] ?? []
            return inner.contains { ($0["command"] as? String)?.contains("clawdpet-hook") == true }
        }

        // Barrido: sacamos NUESTRAS entradas de todos los eventos, no sólo de los que
        // están en `mapping`. Si en una versión sacamos un evento de la lista, su
        // entrada vieja quedaría huérfana disparando estados que ya no queremos.
        for (event, value) in hooks {
            guard var matchers = value as? [[String: Any]] else { continue }
            let before = matchers.count
            matchers.removeAll(where: isOurs)
            guard matchers.count != before else {
                report.kept += matchers.count
                continue
            }
            report.replaced.append(event)
            report.kept += matchers.count
            // Un evento que queda sin nada se borra en vez de dejar un array vacío.
            if matchers.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = matchers }
        }

        for (event, command) in mapping {
            let absolute = command.replacingOccurrences(of: "clawdpet-hook",
                                                        with: "\"\(hookBinary)\"")
            var matchers = hooks[event] as? [[String: Any]] ?? []
            matchers.append([
                "matcher": "",
                "hooks": [["type": "command", "command": absolute]]
            ])
            hooks[event] = matchers
        }

        root["hooks"] = hooks
        let output = try JSONSerialization.data(withJSONObject: root,
                                                options: [.prettyPrinted, .sortedKeys])
        do {
            try output.write(to: settingsURL, options: .atomic)
        } catch {
            throw HookError.unwritable(error.localizedDescription)
        }
        return report
    }
}
