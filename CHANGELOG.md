# Changelog

All notable changes to Untouchable will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Release script not passing Developer ID signing identity to xcodebuild (fell back to Apple Development, causing Gatekeeper rejection)
- Release DMG not codesigned (notarization requires both the app and DMG to be signed)
- Release script reporting notarization success on "Invalid" status (notarytool returns exit 0 even on rejection; now checks actual status output and auto-fetches rejection log)
- Notarization rejection: Sparkle framework binaries bundled unsigned (removed unused Sparkle SPM dependency; will re-add when wiring up updates)
- Notarization rejection: com.apple.security.get-task-allow entitlement auto-injected into release builds (disabled CODE_SIGN_INJECT_BASE_ENTITLEMENTS for release)

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
