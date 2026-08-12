import AppKit
import ApplicationServices

/// Encuentra el rectángulo real de la tira de íconos del Dock.
///
/// `NSScreen.visibleFrame` da la **altura** del Dock pero no su ancho: el Dock sólo
/// ocupa el ancho de sus íconos, centrado. Sin esto la mascota se pasa de largo y
/// termina caminando sobre el escritorio vacío.
///
/// La única forma de saber el ancho es la Accessibility API sobre `com.apple.dock`
/// (la ventana del Dock en `CGWindowList` mide toda la pantalla, no sirve). Si no hay
/// permiso, devolvemos `nil` y el que llama usa el ancho completo de la pantalla.
enum DockLocator {

    /// Cacheamos: recorrer el AX del Dock en cada frame sería carísimo.
    private static var cached: (frame: CGRect, timestamp: TimeInterval)?
    private static var iconCache: [String: (frame: CGRect, timestamp: TimeInterval)] = [:]
    private static let cacheLifetime: TimeInterval = 2.0

    /// Frame de la tira de íconos, en coordenadas Cocoa globales.
    static func iconStripFrame() -> CGRect? {
        let now = Date.timeIntervalSinceReferenceDate
        if let cached, now - cached.timestamp < cacheLifetime {
            return cached.frame.isEmpty ? nil : cached.frame
        }
        let frame = computeIconStripFrame()
        cached = (frame ?? .zero, now)
        return frame
    }

    static func invalidateCache() {
        cached = nil
        iconCache.removeAll()
    }

    /// El `AXList` con los íconos, que es el hijo del Dock que nos interesa.
    private static func iconList() -> AXUIElement? {
        guard let dock = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.dock" }) else { return nil }
        let axDock = AXUIElementCreateApplication(dock.processIdentifier)
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axDock, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return nil }
        return children.first { role(of: $0) == kAXListRole }
    }

    private static func computeIconStripFrame() -> CGRect? {
        guard AXIsProcessTrusted(), let list = iconList() else { return nil }
        // Usamos la unión de los ÍCONOS, no el frame del AXList: el list incluye el
        // padding del contenedor redondeado, así que quedarse con él deja a la mascota
        // caminando sobre la curva del borde en vez de sobre los íconos.
        if let icons = iconsUnion(of: list), icons.width > 40 { return icons }
        if let frame = frame(of: list), frame.width > 40 { return frame }
        return nil
    }

    /// Frame del ícono de una app concreta dentro del Dock.
    ///
    /// Cada ícono expone `AXURL` con la ruta del `.app`, que es la forma confiable de
    /// identificarlo (el `AXTitle` es el nombre visible y puede repetirse o estar
    /// localizado). Si la app no está en el Dock devuelve `nil`.
    static func iconFrame(bundleID: String) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        guard let bundleURL = bundleURL(for: bundleID) else { return nil }

        let now = Date.timeIntervalSinceReferenceDate
        if let cached = iconCache[bundleID], now - cached.timestamp < cacheLifetime {
            return cached.frame
        }
        guard let list = iconList() else { return nil }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let icons = childrenValue as? [AXUIElement] else { return nil }

        // Comparamos por NOMBRE del bundle y confirmamos con el bundle identifier.
        //
        // Comparar rutas completas NO funciona: si la app tiene el flag de cuarentena,
        // Gatekeeper la corre translocada desde
        // `/var/folders/…/AppTranslocation/…/d/VS Code.app`, mientras que el ícono del
        // Dock apunta a `/Applications/VS Code.app`. El nombre del bundle sí se
        // conserva, y el identifier lo confirma sin ambigüedad.
        let targetName = bundleURL.lastPathComponent
        for icon in icons {
            guard let url = iconURL(icon), url.lastPathComponent == targetName else { continue }
            // Si el Info.plist no se puede leer, nos alcanza con el nombre.
            if let identifier = Bundle(url: url)?.bundleIdentifier, identifier != bundleID { continue }
            guard let frame = frame(of: icon) else { continue }
            iconCache[bundleID] = (frame, now)
            return frame
        }
        return nil
    }

    /// El `AXURL` llega como `CFURL`; según el puenteo, el cast directo a `URL` puede
    /// fallar, así que probamos también vía `NSURL`.
    private static func iconURL(_ icon: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(icon, kAXURLAttribute as CFString, &value) == .success,
              let raw = value else { return nil }
        return (raw as? URL) ?? (raw as? NSURL) as URL?
    }

    private static func bundleURL(for bundleID: String) -> URL? {
        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID })?.bundleURL {
            return running
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Volcado de los ítems del Dock, para diagnosticar por qué no matchea alguno.
    static func debugItems(limit: Int = 6) -> String {
        guard AXIsProcessTrusted(), let list = iconList() else { return "sin permiso o sin lista" }
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let icons = childrenValue as? [AXUIElement] else { return "sin hijos" }

        var lines: [String] = ["\(icons.count) ítems en el Dock"]
        for icon in icons.prefix(limit) {
            let url = iconURL(icon)
            let x = frame(of: icon).map { Int($0.midX) }
            lines.append("· \(url?.lastPathComponent ?? "?") "
                         + "id=\(url.flatMap { Bundle(url: $0)?.bundleIdentifier } ?? "?") "
                         + "x=\(x.map(String.init) ?? "?")")
        }
        return lines.joined(separator: "\n")
    }

    /// Rectángulo que cubre exactamente del primer ícono al último.
    private static func iconsUnion(of list: AXUIElement) -> CGRect? {
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let icons = childrenValue as? [AXUIElement], !icons.isEmpty else { return nil }

        var union: CGRect?
        for icon in icons {
            guard let frame = frame(of: icon) else { continue }
            union = union.map { $0.union(frame) } ?? frame
        }
        return union
    }

    // MARK: - Helpers AX

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position: CGPoint = axValue(element, kAXPositionAttribute, .cgPoint),
              let size: CGSize = axValue(element, kAXSizeAttribute, .cgSize) else { return nil }
        guard let primary = NSScreen.screens.first else { return nil }
        // AX: origen arriba-izquierda. Cocoa: abajo-izquierda.
        return CGRect(x: position.x,
                      y: primary.frame.maxY - position.y - size.height,
                      width: size.width,
                      height: size.height)
    }

    private static func axValue<T>(_ element: AXUIElement, _ attribute: String, _ type: AXValueType) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let raw = value, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        let axValue = raw as! AXValue
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AXValueGetValue(axValue, type, pointer) else { return nil }
        return pointer.pointee
    }
}
