# Untouchable -- Comprehensive Codebase Audit

**Date:** 2026-03-20
**Scope:** Security, Code Quality, Build/Release Pipeline, Project Hygiene
**Codebase:** 12 Swift files, 3 shell/Python scripts, 1 CI workflow

---

## Severity Legend

| Severity | Description |
|----------|-------------|
| **CRITICAL** | Security risk, data loss, or crash in production |
| **HIGH** | Bug or significant issue that should be fixed before next release |
| **MEDIUM** | Improvement that reduces risk or improves correctness |
| **LOW** | Nitpick, style, or future-proofing concern |

---

## 1. Security Audit

### 1.1 Vibe-Security Scan Results

**No critical security issues found.** This is a local-only macOS menu bar app with:
- No network access, no API keys, no backend, no database
- No authentication, no payments, no user data collection
- No web views, no JavaScript, no user-generated content

The vibe-security categories (secrets exposure, database access, auth, rate limiting, payments, mobile, AI/LLM, deployment config, data access) are **not applicable** to this project. This is a standalone desktop utility that only interacts with local IOKit HID devices and UserDefaults.

### 1.2 IOKit HID Usage

#### MEDIUM -- Unmanaged Reference Leak in Callback Context

**File:** `Untouchable/HID/HIDDeviceManager.swift:98`

```swift
let selfPtr = Unmanaged.passRetained(self).toOpaque()
```

`passRetained()` creates a +1 strong reference that is **never balanced** with a corresponding `takeRetainedValue()` or `release()`. The callbacks at lines 102 and 110 use `takeUnretainedValue()`, which does not decrement the reference count.

**Impact:** This creates a retain cycle: `HIDDeviceManager` -> `IOHIDManager` -> callback context -> `HIDDeviceManager`. The `HIDDeviceManager` instance will never be deallocated through normal ARC. In practice, since `HIDDeviceManager` is created as a `@StateObject` in `UntouchableApp` and lives for the entire app lifetime, this is not a functional bug -- but it is technically a memory leak.

**Recommended fix:** Either:
1. Store the `Unmanaged` reference and release it in `deinit`:
   ```swift
   private var retainedSelf: Unmanaged<HIDDeviceManager>?

   // In setupManager():
   let unmanaged = Unmanaged.passRetained(self)
   let selfPtr = unmanaged.toOpaque()
   retainedSelf = unmanaged

   // In deinit:
   retainedSelf?.release()
   ```
2. Or use `passUnretained()` since the `@StateObject` guarantees the instance outlives the callbacks. The CHANGELOG notes that `passRetained` was chosen to fix a prior use-after-free risk (v1.0.0 security fix), so approach (1) is safer.

#### LOW -- Magic Number for TCC Denial Error Code

**File:** `Untouchable/HID/HIDEventSuppressor.swift:40`

```swift
} else if result == -536870174 {
```

This hardcodes the IOReturn value for TCC (privacy framework) denial. The value `0xE00002C2` corresponds to `kIOReturnNotPermitted` in some IOKit headers, but it's not always available in Swift.

**Recommended fix:** Define a named constant:
```swift
private let kIOReturnNotPermitted: IOReturn = -536870174
```

#### PASS -- Nil Checks on Device References

All IOHIDDevice and IOHIDManager optionals are properly guarded:
- `HIDEventSuppressor.seize()` at line 23: `guard let ioDevice = device.ioHIDDevice`
- `HIDDeviceManager.setupManager()` at line 81: `guard let manager = manager`
- `HIDDeviceManager.refreshDevices()` at line 168-169: both manager and device set checked
- `HIDDevice.init?(from:)` at line 39-41: failable initializer returns nil if properties missing

#### PASS -- Use-After-Free in Disconnect Path

The disconnect callback at `HIDDeviceManager.swift:138-155` correctly matches by device ID (not object reference) and immediately releases the seized device. The IOHIDDevice pointer remains valid between the removal callback and the subsequent `IOHIDDeviceClose()` call because IOKit guarantees the pointer is valid for the duration of the callback dispatch.

#### PASS -- C Callback Bridges

Both the matching callback (line 100-106) and removal callback (line 108-114) correctly:
1. Guard against nil context pointer
2. Dispatch to `DispatchQueue.main.async` before mutating `@Published` state
3. Use `takeUnretainedValue()` (no double-release risk)

### 1.3 Entitlements

**File:** `Untouchable/Untouchable.entitlements`

**PASS** -- Only entitlement is `com.apple.security.device.input-monitoring = YES`, which is the minimum required for IOHIDManager access. No unnecessary permissions.

The app sandbox is intentionally disabled (documented in CLAUDE.md as accepted risk) because `kIOHIDOptionsTypeSeizeDevice` is incompatible with the macOS app sandbox.

### 1.4 Info.plist Configuration

**File:** `Untouchable/Info.plist`

#### MEDIUM -- Unnecessary LSBackgroundOnly Key

**Lines 27-28:**
```xml
<key>LSBackgroundOnly</key>
<false/>
```

`LSBackgroundOnly` set to `false` is redundant -- this is the default. More importantly, having both `LSUIElement = true` and `LSBackgroundOnly = false` is slightly confusing. `LSUIElement = true` is the correct key for a menu bar app (no Dock icon, no app menu, but can have UI). `LSBackgroundOnly` should be removed entirely since it adds no value and could cause confusion.

**Recommended fix:** Remove the `LSBackgroundOnly` key entirely.

### 1.5 Hardcoded Secrets

**PASS** -- No hardcoded API keys, tokens, passwords, or credentials found in any source file. The release script references `--password YOUR_APP_SPECIFIC_PASSWORD` only in help text (instructional placeholder), and actual notarization credentials are stored in the macOS Keychain via `notarytool store-credentials`.

### 1.6 Logging & Privacy

**PASS** -- No `print()` statements found in any Swift file. All logging uses `os.Logger` with appropriate privacy annotations:
- Device names: `privacy: .private` (e.g., `HIDEventSuppressor.swift:24,39,43,45,60,68`)
- Device IDs: `privacy: .private` (e.g., `HIDDeviceManager.swift:130,151,153`)
- Error descriptions: not marked private (acceptable -- no PII in IOReturn codes)

### 1.7 Release Script Credential Handling

**File:** `scripts/release.sh`

**PASS** -- Notarization credentials are handled via `xcrun notarytool --keychain-profile "Untouchable"` (lines 368, 393-395, 420-421), which stores credentials securely in the macOS Keychain. No plaintext secrets in the script. The help text at lines 372-376 shows example commands but uses placeholder values.

---

## 2. Code Quality

### 2.1 Thread Safety

**PASS** -- All `@Published` mutations are correctly dispatched to the main queue:
- `devices` array mutations in `deviceConnected()` and `deviceDisconnected()` happen inside `DispatchQueue.main.async` blocks (lines 103, 111)
- `refreshDevices()` is called from `configure()`, which is called from `MenuBarView.onAppear` (main thread)
- `toggleBlocked()` is called from SwiftUI toggle bindings (main thread)
- `HIDEventSuppressor.seizedDevices` is only mutated from methods called on the main thread

### 2.2 Retain Cycles / Leaks

#### MEDIUM -- AboutWindow Controller Never Released

**File:** `Untouchable/UI/AboutView.swift:3-29`

```swift
enum AboutWindow {
    private static var windowController: NSWindowController?

    static func show() {
        // ...
        window.isReleasedWhenClosed = false
        let controller = NSWindowController(window: window)
        windowController = controller
        // ...
    }
}
```

The `windowController` is stored as a static variable and `isReleasedWhenClosed = false`, meaning the window and its hosting view are kept alive for the entire app lifetime once opened. This is intentional (singleton pattern for the About window), but there is no way to release it if desired.

**Impact:** Minimal -- the About window is small and this is a standard pattern for About windows. The `NSHostingView` and `AboutView` remain allocated after the window is closed, but they consume negligible memory.

**Status:** Acceptable as-is. No fix needed.

### 2.3 HIDEventSuppressor.releaseAll() Termination Coverage

**PASS with caveat:**
- **Normal quit** (`NSApplication.shared.terminate`): triggers `HIDDeviceManager.deinit` -> `suppressor.releaseAll()` (line 64). Works correctly.
- **SIGTERM**: Same path -- `NSApplication` handles SIGTERM by calling `terminate`, which leads to `deinit`.
- **SIGKILL / crash**: `releaseAll()` is **not** called. However, macOS automatically releases IOKit device seizures when the owning process exits, so orphaned seizures are not possible. This is an OS guarantee, not something the app needs to handle.

**Note:** `AppDelegate.applicationWillTerminate` (line 11-13) has a comment indicating cleanup is handled by `deinit`. This is correct -- the `@StateObject` `deviceManager` will be deallocated when the app terminates, triggering `deinit`.

### 2.4 AppSettings UserDefaults Edge Cases

**File:** `Untouchable/Settings/AppSettings.swift`

#### LOW -- No Validation of Stored Data Format

**Lines 32-36:**
```swift
init() {
    let ids = UserDefaults.standard.stringArray(forKey: Keys.blockedDeviceIDs) ?? []
    self.blockedDeviceIDs = Set(ids)
    self.launchAtLogin = UserDefaults.standard.bool(forKey: Keys.launchAtLogin)
}
```

If UserDefaults data is corrupted or the key exists but contains a non-array type, `stringArray(forKey:)` returns `nil` (handled by `?? []`). `bool(forKey:)` returns `false` for missing or non-boolean values (handled by Swift's default). Both cases degrade gracefully.

**Potential edge case:** If a user manually edits UserDefaults and stores a string like `"not:a:valid:id"` in the blocked list, it would be stored but never match any device (since persistence IDs are `"vendorID:productID"` format). This is harmless.

**Status:** Acceptable as-is. UserDefaults handling is defensive.

### 2.5 SwiftUI View Hierarchy

**File:** `Untouchable/UI/MenuBarView.swift`

#### LOW -- Computed Properties Recomputed on Every Render

**Lines 26-33 in `HIDDeviceManager.swift`:**
```swift
var physicalDeviceGroups: [DeviceGroup] {
    groupedDevices(from: devices.filter { !$0.isVirtual })
}
var virtualDeviceGroups: [DeviceGroup] {
    groupedDevices(from: devices.filter { $0.isVirtual })
}
```

These computed properties re-filter and re-group the device list every time the menu is rendered. With the small number of HID devices on any Mac (typically 2-10), this is negligible.

**Status:** Acceptable. Caching would add complexity for no practical benefit.

#### LOW -- Toggle Binding Reads Devices Twice

**File:** `Untouchable/UI/MenuBarView.swift:58-67`

The toggle binding's `set:` closure calls `toggleBlocked()` and then immediately reads the new state from `devices.first(where:)`. This is a double lookup but is functionally correct and the list is tiny.

---

## 3. Build & Release Pipeline

### 3.1 Release Script (`scripts/release.sh`)

**PASS** -- The release script is well-structured with:
- Preflight checks for tools, signing identity, clean git state, tag format, changelog
- Version sync to Info.plist before build
- Signature verification including hardened runtime check
- Notarization with proper status checking (correctly handles `notarytool` returning exit 0 on rejection)
- Stapling after successful notarization
- Interactive confirmation before each destructive step

#### MEDIUM -- Missing Entitlements Verification in Release Build

The release build at lines 244-256 correctly sets `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` to prevent `get-task-allow` from being injected. However, the `verify_signing()` function does not verify that the final `.app` contains only the expected entitlements. A check like `codesign -d --entitlements - "$app"` would catch unexpected entitlements before submission to notarization.

**Recommended fix:** Add entitlements verification to `verify_signing()`:
```bash
local entitlements
entitlements="$(codesign -d --entitlements - "$app" 2>&1 || true)"
if echo "$entitlements" | grep -q "get-task-allow"; then
    fail "get-task-allow entitlement found -- notarization will be rejected."
    return 1
fi
```

### 3.2 Build Script (`scripts/build.sh`)

**PASS** -- Handles quarantine removal (line 93), Launch Services re-registration (lines 96-97), and process cleanup (lines 77-82).

#### LOW -- Sleep-Based Process Wait

**Lines 77-82:**
```bash
osascript -e 'tell application "Untouchable" to quit' 2>/dev/null || true
sleep 1
pkill -x Untouchable 2>/dev/null || true
sleep 0.5
```

Uses fixed-duration `sleep` to wait for process exit. A more robust approach would poll with `pgrep`, but given this is an interactive developer tool, the current approach is acceptable.

### 3.3 CI Workflow (`.github/workflows/build.yml`)

#### MEDIUM -- No Test Step in CI

**File:** `.github/workflows/build.yml`

The CI workflow only builds and verifies the build product exists. There are no test targets in the project currently, but as the project grows, the workflow should be extended with:
- `xcodebuild test` when test targets are added
- SwiftLint or similar static analysis
- Perhaps a check that the app binary has the correct entitlements

#### LOW -- Missing Xcode Version Pin

The workflow uses `macos-15` but does not pin a specific Xcode version. This could cause build breakage if GitHub updates the default Xcode on the runner.

**Recommended fix:**
```yaml
- uses: maxim-lobanov/setup-xcode@v1
  with:
    xcode-version: '16.2'
```

### 3.4 .gitignore

**PASS** -- Covers:
- Build artifacts: `build/`, `DerivedData/`, `release/`
- Xcode user data: `xcuserdata/`, `*.xcuserstate`
- Signing files: `*.p12`, `*.mobileprovision`, `*.provisionprofile`
- Sparkle keys: `dsa_priv.pem`, `eddsa_priv.pem`
- macOS junk: `.DS_Store`, `._*`
- Archives: `*.dSYM`, `*.ipa`

No gaps found.

---

## 4. Project Hygiene

### 4.1 Dead Code

#### LOW -- DeviceRowView.swift is Dead Code

**File:** `Untouchable/UI/DeviceRowView.swift`

```swift
// DeviceRowView is no longer used -- device toggles are rendered inline
// in MenuBarView using native Toggle for proper checkmark display.
// This file is kept as a placeholder for future custom row UI.
```

The file contains only comments. It is still referenced in `project.pbxproj` (4 references). It should either be removed or repurposed.

**Recommended fix:** Remove the file and its references from the Xcode project, or keep it if custom row UI is planned for a near-future release.

### 4.2 Unused Imports

**PASS** -- All imports are used:
- `IOKit.hid` in HID files
- `Cocoa` in AppDelegate (for `NSApplicationDelegate`)
- `ServiceManagement` in LoginItemManager (for `SMAppService`)
- `SwiftUI` in views and settings
- `Foundation` + `Combine` in HIDDeviceManager
- `os` in files with logging

### 4.3 CHANGELOG.md

**PASS** -- Up to date. The `[Unreleased]` section documents the About window addition and release script fixes. Version history covers 0.1.0, 1.0.0, and 1.0.1.

### 4.4 README.md

#### LOW -- DeviceRowView Listed in Architecture Section

**File:** `README.md:98`

```
    DeviceRowView.swift           # Per-device toggle row
```

This is inaccurate -- `DeviceRowView.swift` is dead code and device toggles are rendered inline in `MenuBarView`. The architecture section should be updated.

**Recommended fix:** Either remove DeviceRowView from the architecture listing, or update the description to reflect that it is a placeholder.

### 4.5 TODO/FIXME Comments

Two TODOs found in `Untouchable/Updater/UpdaterManager.swift`:
- **Line 20:** `// TODO: Initialize SPUStandardUpdaterController once Sparkle is wired.`
- **Line 32:** `// TODO: Forward to SPUStandardUpdaterController.checkForUpdates(_:)`

**Status:** These are intentional placeholders for a known future feature (Sparkle integration). The "Check for Updates" menu item is already disabled (`.disabled(true)` at `MenuBarView.swift:46`). No action needed before next release.

---

## Summary

### Issues by Severity

| # | Severity | Area | Issue | File |
|---|----------|------|-------|------|
| 1 | **MEDIUM** | Security | Unmanaged reference leak in callback context | `HIDDeviceManager.swift:98` |
| 2 | **MEDIUM** | Config | Unnecessary `LSBackgroundOnly` key in Info.plist | `Info.plist:27-28` |
| 3 | **MEDIUM** | Build | Missing entitlements verification in release build | `scripts/release.sh` |
| 4 | **MEDIUM** | CI | No test step in CI workflow | `.github/workflows/build.yml` |
| 5 | **LOW** | Security | Magic number for TCC denial error code | `HIDEventSuppressor.swift:40` |
| 6 | **LOW** | Quality | DeviceRowView.swift is dead code | `UI/DeviceRowView.swift` |
| 7 | **LOW** | Docs | README architecture lists dead DeviceRowView | `README.md:98` |
| 8 | **LOW** | CI | Missing Xcode version pin in CI | `.github/workflows/build.yml` |
| 9 | **LOW** | Build | Sleep-based process wait in build script | `scripts/build.sh:77-82` |
| 10 | **LOW** | Quality | Toggle binding double lookup | `MenuBarView.swift:58-67` |

### What Passed

- No hardcoded secrets or credentials
- No `print()` statements -- all logging via `os.Logger` with privacy annotations
- Thread safety: all `@Published` mutations on main queue
- Entitlements minimal: only `input-monitoring`
- IOKit nil checks and failable initializers throughout
- Proper device seizure/release lifecycle
- OS guarantees cleanup on crash/SIGKILL
- UserDefaults handling degrades gracefully
- Release script uses Keychain for credentials
- .gitignore coverage is comprehensive
- CHANGELOG is up to date
- No unused imports

### Overall Assessment

The codebase is in good shape for a small, focused utility. **No critical or high-severity issues found.** The four medium-severity items are improvements that would strengthen the project but are not blockers. The codebase demonstrates careful attention to IOKit memory management, thread safety, and privacy -- areas where macOS HID apps frequently have bugs.
