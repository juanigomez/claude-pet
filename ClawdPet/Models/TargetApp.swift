import AppKit

/// La app que la mascota tiene que señalar. Se arma sola: no hay lista que configurar.
struct TargetApp: Equatable {
    var bundleID: String
    var name: String

    init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    init?(_ running: NSRunningApplication) {
        guard let bundleID = running.bundleIdentifier else { return nil }
        self.bundleID = bundleID
        self.name = running.localizedName ?? bundleID
    }

    /// Trae la app al frente (o la abre si no está corriendo).
    @MainActor
    func activate() {
        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID && !$0.isTerminated }) {
            running.activate(options: [.activateAllWindows])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}

/// Cómo decidimos a qué app apuntar, en orden de confianza.
enum AppResolver {

    /// Alias cortos para el CLI, para no tener que tipear bundle ids.
    /// No es configuración: es azúcar para `clawdpet --app vscode`.
    private static let aliases: [String: String] = [
        "vscode": "com.microsoft.VSCode",
        "code": "com.microsoft.VSCode",
        "cursor": "com.todesktop.230313mzl4w4u92",
        "terminal": "com.apple.Terminal",
        "iterm": "com.googlecode.iterm2",
        "iterm2": "com.googlecode.iterm2",
        "ghostty": "com.mitchellh.ghostty",
        "warp": "dev.warp.Warp-Stable",
        "claude": "com.anthropic.claudefordesktop",
        "claude-desktop": "com.anthropic.claudefordesktop",
        "xcode": "com.apple.dt.Xcode"
    ]

    /// 1. Si vino el PID del hook, subimos por el árbol de procesos: es lo más exacto,
    ///    porque identifica la ventana concreta donde estás trabajando.
    /// 2. Si vino un `app`, lo resolvemos como alias, bundle id o nombre de app corriendo.
    /// 3. Si no vino nada, usamos la app que está al frente en ese momento.
    @MainActor
    static func resolve(pid: pid_t?, identifier: String?) -> TargetApp? {
        if let pid, pid > 0, let running = ProcessTree.owningApplication(of: pid),
           let target = TargetApp(running) {
            return target
        }
        if let identifier, !identifier.isEmpty, let target = resolveIdentifier(identifier) {
            return target
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            return TargetApp(frontmost)
        }
        return nil
    }

    @MainActor
    private static func resolveIdentifier(_ identifier: String) -> TargetApp? {
        let needle = identifier.lowercased()
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }

        let bundleID = aliases[needle] ?? identifier
        if let match = running.first(where: { $0.bundleIdentifier?.lowercased() == bundleID.lowercased() }) {
            return TargetApp(match)
        }
        // Por nombre visible: `--app "Visual Studio Code"` o `--app code`.
        if let match = running.first(where: { ($0.localizedName ?? "").lowercased().contains(needle) }) {
            return TargetApp(match)
        }
        // No está corriendo pero parece un bundle id: lo aceptamos igual (se abrirá al clickear).
        if bundleID.contains(".") {
            return TargetApp(bundleID: bundleID, name: bundleID)
        }
        return nil
    }
}
