import AppKit

/// El binario `clawdpet` viaja adentro del bundle de la app.
/// Esto lo deja disponible en el `PATH` con un symlink, sin pedir sudo.
enum CLIInstaller {

    /// Ruta del ejecutable embebido en `ClawdPet.app/Contents/Resources/clawdpet`.
    static var bundledBinary: URL? {
        Bundle.main.url(forResource: "clawdpet", withExtension: nil)
    }

    /// Destino sin privilegios. `/usr/local/bin` necesitaría sudo.
    static var installDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin", isDirectory: true)
    }

    static var installedPath: URL {
        installDirectory.appendingPathComponent("clawdpet")
    }

    static var isInstalled: Bool {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: installedPath.path)
        else { return FileManager.default.isExecutableFile(atPath: installedPath.path) }
        return destination == bundledBinary?.path
    }

    /// Instala `clawdpet` (el binario) y `clawdpet-hook` (el script para Claude Code).
    @discardableResult
    static func install() -> Result<URL, Error> {
        guard let source = bundledBinary else {
            return .failure(CLIError.notBundled)
        }
        do {
            try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
            try link(from: source, to: installedPath)
            if let hook = HookScript.ensureInstalled() {
                try link(from: hook, to: installDirectory.appendingPathComponent("clawdpet-hook"))
            }
            return .success(installedPath)
        } catch {
            return .failure(error)
        }
    }

    private static func link(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        // `fileExists` sigue el symlink, así que un link roto no lo detecta: probamos las dos.
        if fm.fileExists(atPath: destination.path) ||
            (try? fm.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            try fm.removeItem(at: destination)
        }
        try fm.createSymbolicLink(at: destination, withDestinationURL: source)
    }

    static func uninstall() {
        try? FileManager.default.removeItem(at: installedPath)
        try? FileManager.default.removeItem(at: installDirectory.appendingPathComponent("clawdpet-hook"))
    }

    /// Dónde quedan los symlinks después de `install()`.
    static var installedDirectory: URL { installDirectory }

    /// Comando alternativo para pegar en la terminal si se prefiere `/usr/local/bin`.
    static var manualCommand: String {
        let source = bundledBinary?.path ?? "/Applications/ClawdPet.app/Contents/Resources/clawdpet"
        return "sudo ln -sf \"\(source)\" /usr/local/bin/clawdpet"
    }

    enum CLIError: LocalizedError {
        case notBundled
        var errorDescription: String? {
            "No se encontró el ejecutable `clawdpet` dentro del bundle. "
            + "Compilá el target ClawdPetCLI (viene en el mismo proyecto) y volvé a correr la app."
        }
    }
}
