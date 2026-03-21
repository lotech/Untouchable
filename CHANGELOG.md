# Changelog

All notable changes to Untouchable will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-03-21

### Added
- Built-in trackpad suppression: Apple Internal Keyboard / Trackpad interfaces (which lack vendor/product IDs) are now enumerated and can be blocked like any external device
- TCC denial detection: menu bar shows warning with device names when Input Monitoring permission is missing or stale, with button to open System Settings
- About window showing app icon, version, build number, copyright, and GitHub link
- Build script: `--reset-tcc` flag and menu option to reset Input Monitoring permission via `tccutil`
- Automatic retry for failed device seizures (up to 3 attempts with escalating delay) for multi-interface touchscreens

### Fixed
- Blocked devices not suppressed on launch: IOKit reports success for seizure during initial enumeration but does not enforce it; seizure is now deferred until IOKit settles, with explicit run loop scheduling
- Touchscreen input leaking through when blocked: HID matching only covered 3 specific digitizer usages, missing interfaces like Pen, MultiplePointDigitizer, and DeviceConfiguration; now matches the entire Digitizer usage page
- Ghost touches caused by multiple Untouchable instances competing for exclusive HID seizure: new instance now terminates any existing instances on launch
- Seizures silently lost after system sleep/wake: now re-seizes all blocked devices on wake notification
- Blocked devices not re-seized on launch until user opens the menu (AppSettings was nil during initial enumeration)
- Apple Internal Keyboard / Trackpad interfaces skipped when they lack the `BuiltIn` IOKit property; now also detects built-in devices by name prefix
- Release script: version sync, signing identity, DMG codesigning, notarization status checking, and entitlements verification

### Changed
- HIDDeviceManager receives AppSettings at init for immediate seizure of persisted blocked devices
- Built-in trackpad displays as "Built-in Trackpad" instead of "Apple Internal Keyboard / Trackpad"
- HID log levels upgraded to notice (persisted) with public privacy for device IDs
- Balanced Unmanaged.passRetained reference with explicit release in deinit

### Removed
- Dead DeviceRowView.swift (replaced by inline toggles in MenuBarView since v1.0.0)
- Redundant LSBackgroundOnly key from Info.plist

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
