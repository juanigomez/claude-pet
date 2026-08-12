import AppKit
import ApplicationServices

/// Ubica la ventana frontal de otra app usando la Accessibility API.
///
/// Devuelve el frame en **coordenadas Cocoa globales** (origen abajo-izquierda de la
/// pantalla principal, `y` hacia arriba), que es lo que usan `NSScreen` y `NSWindow`.
/// La AX API trabaja al revés (origen arriba-izquierda, `y` hacia abajo), así que
/// convertimos.
///
/// > Mejora opcional (no implementada a propósito): para posicionarse exactamente
/// > sobre el **ícono del Dock** de la app haría falta leer los `AXUIElement` del
/// > proceso `com.apple.dock` (`AXList` → hijos → `AXPosition`/`AXSize` de cada ícono).
/// > Funciona, pero es frágil entre versiones de macOS y depende del mismo permiso de
/// > Accesibilidad. Con la ventana frontal alcanza para la v1.
enum AccessibilityLocator {

    static func frontWindowFrame(bundleID: String) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID && !$0.isTerminated }) else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        if let frame = frame(ofAttribute: kAXFocusedWindowAttribute as CFString, in: axApp) {
            return frame
        }
        if let frame = frame(ofAttribute: kAXMainWindowAttribute as CFString, in: axApp) {
            return frame
        }
        // Último recurso: la primera ventana de la lista.
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement],
              let first = windows.first else { return nil }
        return frame(of: first)
    }

    // MARK: - Helpers

    private static func frame(ofAttribute attribute: CFString, in element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let raw = value else { return nil }
        // swiftlint:disable:next force_cast
        let window = raw as! AXUIElement
        return frame(of: window)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let position: CGPoint = axValue(window, kAXPositionAttribute, .cgPoint),
              let size: CGSize = axValue(window, kAXSizeAttribute, .cgSize),
              size.width > 1, size.height > 1 else { return nil }

        let axRect = CGRect(origin: position, size: size)
        return convertFromAX(axRect)
    }

    private static func axValue<T>(_ element: AXUIElement, _ attribute: String, _ type: AXValueType) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let raw = value else { return nil }
        guard CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        let axValue = raw as! AXValue
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AXValueGetValue(axValue, type, result) else { return nil }
        return result.pointee
    }

    /// AX usa el origen arriba-izquierda de la pantalla principal; Cocoa el de abajo-izquierda.
    private static func convertFromAX(_ rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        let flippedY = primary.frame.maxY - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: flippedY, width: rect.width, height: rect.height)
    }
}
