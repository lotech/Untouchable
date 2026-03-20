# Changelog

All notable changes to Untouchable will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security
- Fixed use-after-free risk: `Unmanaged.passRetained` replaces `passUnretained` for IOHIDManager callback context
- Replaced all `print()` logging with `os.Logger` and `privacy: .private` annotations to prevent device info leaking to system log
- Removed empty `SUFeedURL` from Info.plist to prevent future update hijack surface
- Narrowed `.gitignore` `*.xml` to `appcast.xml` only
- Added `eddsa_priv.pem` to `.gitignore` for future Sparkle EdDSA signing
- Documented sandbox-off as accepted risk in CLAUDE.md

### Added
- Installed vibe-security skill for automated security auditing (`.claude/skills/vibe-security/`)
- AccentColor asset to fix Xcode warning

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
