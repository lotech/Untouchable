import Foundation
import ServiceManagement

/// Manages the "Launch at Login" preference using `SMAppService` (macOS 13+).
///
/// This replaces the legacy `SMLoginItemSetEnabled` API with the modern
/// `SMAppService.mainApp` approach that works with sandboxed and
/// non-sandboxed apps alike.
final class LoginItemManager {

    static let shared = LoginItemManager()

    private init() {}

    /// The current registration status of the login item.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item.
    ///
    /// - Parameter enabled: `true` to register, `false` to unregister.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // TODO: Surface this error to the user or log it.
            print("LoginItemManager: Failed to \(enabled ? "register" : "unregister") login item: \(error)")
        }
    }
}
