import Foundation

/// Stub for Sparkle-based software update support.
///
/// Sparkle is included as a package dependency but is not wired up yet.
/// This manager provides the interface that the UI binds to so that the
/// "Check for Updates…" menu item exists from day one.
///
/// ## Wiring Up Later
/// 1. Import `Sparkle`.
/// 2. Create an `SPUStandardUpdaterController` in `init()`.
/// 3. Forward `checkForUpdates()` to the controller's `checkForUpdates(_:)`.
/// 4. Enable the menu item in ``MenuBarView``.
final class UpdaterManager {

    static let shared = UpdaterManager()

    private init() {
        // TODO: Initialize SPUStandardUpdaterController once Sparkle is wired.
    }

    /// Whether the updater can currently check for updates.
    /// Always returns `false` until Sparkle is wired up.
    var canCheckForUpdates: Bool {
        false
    }

    /// Triggers a manual update check.
    /// No-op until Sparkle is wired up.
    func checkForUpdates() {
        // TODO: Forward to SPUStandardUpdaterController.checkForUpdates(_:)
    }
}
