import Foundation
import SwiftUI

/// Persists user preferences using `UserDefaults`.
///
/// Stores:
/// - Blocked device IDs as a `[String]` (format: `"vendorID:productID"`).
/// - Launch at Login preference.
final class AppSettings: ObservableObject {

    // MARK: - Keys

    private enum Keys {
        static let blockedDeviceIDs = "blockedDeviceIDs"
        static let launchAtLogin = "launchAtLogin"
    }

    // MARK: - Published

    /// Whether the app should launch at login.
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

    /// The set of currently blocked device IDs.
    @Published private(set) var blockedDeviceIDs: Set<String>

    // MARK: - Init

    init() {
        let ids = UserDefaults.standard.stringArray(forKey: Keys.blockedDeviceIDs) ?? []
        self.blockedDeviceIDs = Set(ids)
        self.launchAtLogin = UserDefaults.standard.bool(forKey: Keys.launchAtLogin)
    }

    // MARK: - Public API

    /// Returns whether the given device ID is in the blocked set.
    func isBlocked(_ deviceID: String) -> Bool {
        blockedDeviceIDs.contains(deviceID)
    }

    /// Adds or removes a device ID from the blocked set and persists the change.
    func setBlocked(_ blocked: Bool, forDeviceID deviceID: String) {
        if blocked {
            blockedDeviceIDs.insert(deviceID)
        } else {
            blockedDeviceIDs.remove(deviceID)
        }
        UserDefaults.standard.set(Array(blockedDeviceIDs), forKey: Keys.blockedDeviceIDs)
    }
}
