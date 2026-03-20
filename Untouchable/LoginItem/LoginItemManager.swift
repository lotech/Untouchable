import Foundation
import ServiceManagement
import os

private let logger = Logger(subsystem: "vision.lotech.Untouchable", category: "LoginItemManager")

/// Manages the "Launch at Login" preference using `SMAppService` (macOS 13+).
final class LoginItemManager {

    static let shared = LoginItemManager()

    private init() {}

    /// The current registration status of the login item.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Failed to \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)")
        }
    }
}
