import AppKit
import ApplicationServices

/// Sonda de diagnóstico: vuelca el árbol de Accesibilidad de una app.
///
/// Sirve para averiguar si una app expone alguna señal de "está generando" con la que
/// se pueda enganchar la mascota. Claude Code tiene hooks (una API de verdad); Claude
/// Desktop y el navegador no, así que lo único que queda es mirarles la interfaz.
enum AXProbe {

    static func describe(bundleID: String, maxDepth: Int = 6, maxNodes: Int = 400) -> String {
        guard AXIsProcessTrusted() else { return "sin permiso de Accesibilidad" }
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID }) else {
            return "no está corriendo: \(bundleID)"
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var lines: [String] = ["\(app.localizedName ?? bundleID) (pid \(app.processIdentifier))"]
        var count = 0
        walk(root, depth: 0, maxDepth: maxDepth, lines: &lines, count: &count, maxNodes: maxNodes)
        return lines.joined(separator: "\n")
    }

    private static func walk(_ element: AXUIElement, depth: Int, maxDepth: Int,
                             lines: inout [String], count: inout Int, maxNodes: Int) {
        guard depth <= maxDepth, count < maxNodes else { return }

        let role = string(element, kAXRoleAttribute) ?? "?"
        let title = string(element, kAXTitleAttribute)
        let desc = string(element, kAXDescriptionAttribute)
        let value = string(element, kAXValueAttribute)
        let identifier = string(element, kAXIdentifierAttribute)

        // Sólo nos interesan los nodos que dicen algo.
        let bits = [title, desc, identifier, value.map { String($0.prefix(40)) }]
            .compactMap { $0 }.filter { !$0.isEmpty }
        if !bits.isEmpty || role.contains("Button") {
            lines.append(String(repeating: "  ", count: depth) + "\(role): \(bits.joined(separator: " | "))")
            count += 1
        }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let kids = children as? [AXUIElement] else { return }
        for kid in kids {
            walk(kid, depth: depth + 1, maxDepth: maxDepth, lines: &lines, count: &count, maxNodes: maxNodes)
        }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
