# Changelog

All notable changes to Untouchable will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- TCC denial detection: menu bar shows warning with device names when Input Monitoring permission is stale or denied, with button to open System Settings
- Built-in trackpad suppression: Apple Internal Keyboard / Trackpad HID interfaces (which lack vendor/product IDs) are now enumerated and can be toggled like any other device
- About window showing app icon, version, build number, copyright, and GitHub link

### Changed
- Upgraded HID log levels from info to notice so messages persist in log store (info is not persisted by default)
- Changed HID log privacy annotations from .private to .public so device IDs are visible in log output
- Added usage page/usage fields to HIDDevice for diagnosing which HID interface types are enumerated
- Added error logging when HIDDevice.init fails (skipped interfaces with no vendor/product ID)
- Built-in trackpad displays as "Built-in Trackpad" instead of "Apple Internal Keyboard / Trackpad"

### Fixed
- Build script pull failing on divergent branches (now uses --rebase)
- Entitlements verification step in release script (rejects get-task-allow before notarization)
- Mach-O binary verification step in CI workflow
- Xcode version pin (16.2) in CI workflow for reproducible builds
- System wake observer: re-seizes all blocked devices after sleep/wake (IOKit can silently lose seizures when hardware powers down)
- Automatic retry for failed device seizures (up to 3 attempts with escalating delay) -- catches multi-interface touchscreens where some HID interfaces are not immediately ready for exclusive access

### Changed
- HIDDeviceManager now receives AppSettings at init, ensuring blocked devices are seized immediately on launch instead of waiting for the menu to be opened
- Balanced Unmanaged.passRetained reference with explicit release in deinit (fixes potential memory leak)
- TCC denial error code replaced with named constant `kIOReturnNotPermitted`
- Build script install uses poll-based process wait instead of fixed sleep
- Toggle binding in MenuBarView uses the new value directly instead of re-reading from device list

### Removed
- Dead DeviceRowView.swift file and its Xcode project references (replaced by inline toggles in MenuBarView since v1.0.0)
- Redundant LSBackgroundOnly key from Info.plist (LSUIElement is sufficient for menu bar apps)

### Fixed
- Ghost touches leaking through on multi-interface touchscreens: some HID interfaces failed to seize immediately after enumeration (IOReturn not-permitted); now retries up to 3 times with escalating delay
- Seizures silently lost after system sleep/wake: IOKit releases exclusive device access when hardware powers down but fires no callbacks; now re-seizes all blocked devices on NSWorkspace.didWakeNotification
- Blocked devices not re-seized on launch until user opens the menu (AppSettings was nil during initial IOHIDManager matching callbacks)
- Release script leaving Info.plist version bump uncommitted, causing dirty working tree after release (now commits the version bump before tagging)
- Release script requiring manual CHANGELOG.md update before release (now automatically moves [Unreleased] to versioned section)
- Release script not passing Developer ID signing identity to xcodebuild (fell back to Apple Development, causing Gatekeeper rejection)
- Release DMG not codesigned (notarization requires both the app and DMG to be signed)
- Release script reporting notarization success on "Invalid" status (notarytool returns exit 0 even on rejection; now checks actual status output and auto-fetches rejection log)
- Notarization rejection: Sparkle framework binaries bundled unsigned (removed unused Sparkle SPM dependency; will re-add when wiring up updates)
- Notarization rejection: com.apple.security.get-task-allow entitlement auto-injected into release builds (disabled CODE_SIGN_INJECT_BASE_ENTITLEMENTS for release)
- Version numbers out of sync between Info.plist and release tag (release script now updates CFBundleShortVersionString, CFBundleVersion, and MARKETING_VERSION from the tag)

## [1.0.1] - 2026-03-20

### Fixed
- Device disconnect not updating menu when unplugging a monitor/USB device (removal callback matched by object reference instead of device ID)
- App not launching after install via build script (quarantine xattr, Launch Services cache, LSUIElement quit handling)

## [1.0.0] - 2026-03-20

### Added
- App icon: touch-ripple with prohibition slash on indigo-blue gradient, all macOS sizes (16-1024px)
- Installed vibe-security skill for automated security auditing (`.claude/skills/vibe-security/`)
- AccentColor asset to fix Xcode warning
- GitHub Actions CI workflow for build validation on push/PR to main
- Release script (`scripts/release.sh`) with preflight checks, signing verification, DMG packaging, notarization, and GitHub Release creation

### Changed
- Physical devices now shown at top level; virtual/software devices (VirtualHID, Karabiner, etc.) moved to "Other Devices" submenu
- Device toggles use native macOS checkmarks instead of custom circle icons -- blocked state now visually clear
- Blocking a device now blocks ALL its HID interfaces (same vendor:product), not just one
- Each HID interface gets a unique ID (IOKit registry entry) so duplicates display correctly

### Fixed
- Toggle checkmark not showing when blocking a device (was using custom view instead of native Toggle)
- Duplicate devices with same vendor:product pair collapsing into one entry

### Security
- Fixed use-after-free risk: `Unmanaged.passRetained` replaces `passUnretained` for IOHIDManager callback context
- Replaced all `print()` logging with `os.Logger` and `privacy: .private` annotations to prevent device info leaking to system log
- Removed empty `SUFeedURL` from Info.plist to prevent future update hijack surface
- Narrowed `.gitignore` `*.xml` to `appcast.xml` only
- Added `eddsa_priv.pem` to `.gitignore` for future Sparkle EdDSA signing
- Documented sandbox-off as accepted risk in CLAUDE.md

## [0.1.0] - 2026-03-20

### Added
- macOS menu bar app (MenuBarExtra) -- no Dock icon, no main window
- HID device enumeration via IOHIDManager (mice, trackpads, touchscreens, digitizers)
- Per-device suppression toggle using `kIOHIDOptionsTypeSeizeDevice` exclusive grab
- Automatic device connect/disconnect detection with live UI updates
- Persisted blocked device list in UserDefaults (survives app restarts)
- Auto-reapply seizures on launch for previously blocked devices
- Launch at Login via SMAppService (macOS 13+)
- Sparkle update framework dependency (stub -- not yet wired)
- Interactive build/deploy script (`scripts/build.sh`)
- Open source scaffolding: MIT license, contributing guide, issue/PR templates
