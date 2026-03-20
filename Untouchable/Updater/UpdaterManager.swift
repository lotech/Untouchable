import Foundation

/// Stub for Sparkle-based software update support.
///
/// Sparkle is not yet added as a dependency. This manager provides the
/// interface that the UI binds to so that the "Check for Updates" menu
/// item exists from day one.
///
/// ## Wiring Up Later
/// 1. Add Sparkle 2.x as an SPM dependency.
/// 2. Import `Sparkle`.
/// 3. Create an `SPUStandardUpdaterController` in `init()`.
/// 4. Forward `checkForUpdates()` to the controller's `checkForUpdates(_:)`.
/// 5. Enable the menu item in ``MenuBarView``.
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
