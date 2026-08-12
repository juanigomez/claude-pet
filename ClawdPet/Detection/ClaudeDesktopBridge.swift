import AppKit

/// Manda un texto al chat de Claude Desktop.
///
/// Claude Desktop no expone un URL scheme documentado para prefill, así que hacemos lo
/// que haría una persona: copiar al portapapeles, traer la app al frente y simular
/// ⌘V + ⏎. Es la vía que no depende de APIs privadas ni de una API key.
///
/// Simular teclas necesita el permiso de **Accesibilidad**. Si no está concedido no
/// fallamos en silencio: dejamos el texto en el portapapeles y lo decimos.
enum ClaudeDesktopBridge {

    static let bundleID = "com.anthropic.claudefordesktop"

    enum BridgeError: Error {
        case notInstalled
        case notTrusted
        case couldNotActivate

        var shortMessage: String {
            switch self {
            case .notInstalled: return "No encontré Claude Desktop"
            case .notTrusted: return "Copiado — falta permiso"
            case .couldNotActivate: return "No pude abrir Claude"
            }
        }
    }

    @MainActor
    static func send(_ prompt: String) -> Result<Void, BridgeError> {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return .failure(.notInstalled)
        }

        // 1. Portapapeles. Guardamos lo que había para devolverlo después.
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(prompt, forType: .string)

        // 2. Traer Claude al frente.
        activate(appURL: appURL)

        guard AXIsProcessTrusted() else {
            // El texto ya quedó en el portapapeles: sólo falta que pegue la persona.
            return .failure(.notTrusted)
        }

        // 3. Esperar a que sea la app del frente y recién ahí tipear.
        //    Si tipeamos antes, las teclas se las come la app anterior.
        waitUntilFrontmost(timeout: 2.0) { ready in
            guard ready else { return }
            postPasteAndReturn()
            // Devolver el portapapeles como estaba, una vez que Claude ya leyó.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let previous {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
        return .success(())
    }

    // MARK: - Interno

    @MainActor
    private static func activate(appURL: URL) {
        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID && !$0.isTerminated }) {
            running.activate(options: [.activateAllWindows])
        } else {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
    }

    /// Poll corto: `NSRunningApplication.activate` es asincrónico y no avisa cuándo terminó.
    @MainActor
    private static func waitUntilFrontmost(timeout: TimeInterval,
                                           completion: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func check() {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID {
                // Un respiro extra para que el campo de texto tome el foco.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { completion(true) }
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { check() }
            } else {
                completion(false)
            }
        }
        check()
    }

    private static let keyV: CGKeyCode = 9
    private static let keyReturn: CGKeyCode = 36

    private static func postPasteAndReturn() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        func post(_ key: CGKeyCode, flags: CGEventFlags = []) {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
            else { return }
            down.flags = flags
            up.flags = flags
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
        }

        post(keyV, flags: .maskCommand)
        // Enter va después, con un respiro: pegar es sincrónico para el usuario pero
        // la app necesita un tick para procesar el texto antes de mandarlo.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            post(keyReturn)
        }
    }
}
