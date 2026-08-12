import Foundation
import ServiceManagement

/// Arranque al iniciar sesión vía `SMAppService` (macOS 13+).
///
/// Ojo: `register()` falla si la app corre desde una ubicación "inestable"
/// (por ejemplo desde DerivedData al correr con ⌘R). Para que funcione de verdad,
/// copiá `ClawdPet.app` a `/Applications` y abrila desde ahí.
enum LoginItemManager {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Result<Void, Error> {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .notRegistered: return "disabled"
        case .requiresApproval: return "waiting for your approval in Settings ▸ General ▸ Login Items"
        case .notFound: return "not found"
        @unknown default: return "unknown"
        }
    }
}
