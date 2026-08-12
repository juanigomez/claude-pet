import Foundation

/// Le pregunta algo a Claude usando el CLI de Claude Code (`claude -p`) y devuelve
/// una respuesta corta para mostrar en la burbuja.
///
/// Elegimos el CLI en vez de la API HTTP porque **no necesita API key**: reusa la
/// sesión que ya tenés autenticada en Claude Code. Y a diferencia de escribir en
/// Claude Desktop, no hace falta permiso de Accesibilidad.
enum ClaudeCLIBridge {

    enum CLIError: LocalizedError {
        case notFound
        case failed(String)
        case timedOut
        case empty

        var shortMessage: String {
            switch self {
            case .notFound: return "No encontré el comando `claude`"
            case .failed(let detail): return detail.isEmpty ? "Claude devolvió un error" : detail
            case .timedOut: return "Claude tardó demasiado"
            case .empty: return "Claude no respondió nada"
            }
        }

        var errorDescription: String? { shortMessage }
    }

    /// Una app GUI no hereda tu `PATH` del shell, así que buscamos a mano en los
    /// lugares donde se instala Claude Code.
    static func locateBinary() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
            home.appendingPathComponent(".bun/bin/claude"),
            home.appendingPathComponent(".volta/bin/claude")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var isAvailable: Bool { locateBinary() != nil }

    private static let timeout: TimeInterval = 90
    /// Tope de caracteres: la burbuja es chica, no un chat.
    private static let maxAnswerLength = 240

    /// Corre fuera del main thread y llama a `completion` en el main.
    static func ask(_ prompt: String, completion: @escaping (Result<String, CLIError>) -> Void) {
        guard let binary = locateBinary() else {
            DispatchQueue.main.async { completion(.failure(.notFound)) }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = run(binary: binary, prompt: prompt)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func run(binary: URL, prompt: String) -> Result<String, CLIError> {
        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "-p", prompt,
            "--model", "haiku",
            // La respuesta va a una burbuja de dos líneas: pedimos brevedad explícita.
            "--append-system-prompt",
            "Respondé en el mismo idioma de la pregunta, en 2 oraciones cortas como "
            + "máximo. Sin markdown, sin listas, sin preámbulo."
        ]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        // Reconstruimos un PATH razonable: el proceso hijo lo necesita para node/bun.
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extraPaths = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
                          "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existing = environment["PATH"].map { [$0] } ?? []
        environment["PATH"] = (existing + extraPaths).joined(separator: ":")
        process.environment = environment

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        // Sin stdin: si `claude` esperara input interactivo, se colgaría.
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .failure(.failed(error.localizedDescription))
        }

        // Leemos antes de esperar: si el pipe se llena, el hijo se bloquea escribiendo.
        let outData = output.fileHandleForReading.readDataToEndOfFile()
        let errData = errors.fileHandleForReading.readDataToEndOfFile()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            return .failure(.timedOut)
        }

        guard process.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .failure(.failed(String(message.prefix(120))))
        }

        let answer = String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !answer.isEmpty else { return .failure(.empty) }
        return .success(truncate(answer))
    }

    private static func truncate(_ text: String) -> String {
        // Una sola línea: los saltos de línea rompen la burbuja.
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        guard flattened.count > maxAnswerLength else { return flattened }
        return String(flattened.prefix(maxAnswerLength)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
