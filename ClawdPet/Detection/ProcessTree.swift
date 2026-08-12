import AppKit
import Darwin

/// Resuelve "¿de qué app viene este aviso?" sin que tengas que configurar nada.
///
/// El hook corre como un proceso hijo del agente, que a su vez es hijo de la terminal,
/// que es hija de la app (Terminal.app, iTerm, VS Code, Ghostty…). Subiendo por el
/// árbol de procesos desde el PID del hook llegamos a la app dueña.
///
/// Ejemplo real de la cadena:
/// ```
/// clawdpet-hook (pid 4711)
///   └─ claude          (pid 4390)
///        └─ zsh        (pid 4102)
///             └─ Code Helper
///                  └─ Visual Studio Code   ← esta es la que buscamos
/// ```
enum ProcessTree {

    /// Cuántos saltos máximo antes de rendirse (evita loops si algo raro pasa).
    private static let maxDepth = 24

    /// PID del padre de `pid`, o `nil` si no existe / no se puede leer.
    static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }

    /// Sube por el árbol hasta encontrar un proceso que sea una app con interfaz.
    static func owningApplication(of pid: pid_t) -> NSRunningApplication? {
        var current: pid_t? = pid
        var depth = 0
        while let candidate = current, candidate > 1, depth < maxDepth {
            if let app = application(for: candidate) { return app }
            current = parent(of: candidate)
            depth += 1
        }
        return nil
    }

    /// Una app "de verdad": tiene bundle id y aparece en el Dock/⌘-Tab.
    /// Descartamos las `.prohibited` (helpers, XPC) y las `.accessory` (agents),
    /// que no tienen ventanas propias que valga la pena señalar.
    private static func application(for pid: pid_t) -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else { return nil }
        return app
    }
}
