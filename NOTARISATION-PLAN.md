# Untouchable — Developer ID Notarisation Plan

Status: **complete and verified.** v1.0.5 built, signed, notarised, stapled, and
published; confirmed on a fresh Mac (no Gatekeeper prompt, Input Monitoring
permission requested, About shows v1.0.5). Tracks the repeatable, env-var-driven
Developer ID signing + Apple notarisation + notarised DMG pipeline, following the
SpinCycle `macos-notarisation-playbook.md`.

## Inventory (per-app adaptation — §4 of the playbook)

- **Uses Sparkle?** **No.** `Untouchable/Updater/UpdaterManager.swift` is an
  explicit stub (`canCheckForUpdates` always `false`); `Package.swift` declares
  zero dependencies; `Info.plist` only has commented-out `SUFeedURL` /
  `SUPublicEDKey` placeholders. The notary history (DMGs, no `-update.zip`)
  confirms this. **Implication: DMG-only — no zip enclosure, no appcast, no
  EdDSA `sign_update`.** If/when Sparkle is wired up later, revisit and add the
  `…-update.zip` + appcast path from playbook §3.
- **Bundled executables in `Resources/`:** **None.** All Swift sources compile
  into the single main Mach-O (`Contents/MacOS/Untouchable`) which Xcode signs.
  No helper CLIs copied into `Resources/`. → no per-binary signing loop needed.
- **Embedded frameworks + nested code:** **None.** No `Contents/Frameworks`
  payload (no Sparkle.framework, no XPC services, no helper apps). → inside-out
  signing collapses to just the `.app` bundle itself.
- **Entitlements / hardened-runtime exceptions needed:**
  `Untouchable/Untouchable.entitlements` declares only
  `com.apple.security.device.input-monitoring = YES`. App sandbox is **off**
  (required: `kIOHIDOptionsTypeSeizeDevice` is sandbox-incompatible). Hardened
  runtime is required for notarisation. → the outer `.app` sign **must** pass
  `--options runtime` **and** `--entitlements Untouchable/Untouchable.entitlements`.
  No JIT / `DYLD_*` / unsigned-plugin exceptions needed.
- **How releases are built today:** `scripts/release.sh` (a thorough
  interactive script: preflight → `xcodebuild` Release → verify → DMG →
  notarise → GitHub release). It already signs and notarises, but:
  - it **auto-detects** the identity (greps the first `Developer ID Application`
    from `security find-identity`) — not env-var-driven, and ambiguous if two
    Developer ID certs share a name;
  - it hardcodes the notary profile name `"Untouchable"` — should be the shared
    `<profile>` via env var;
  - it has **no hard-fail** when no Developer ID identity is set (it falls back
    to Apple Development or prompts to skip notarisation — i.e. it can silently
    publish an unsigned/un-notarised build);
  - it has **no explicit inside-out re-sign step** (relies solely on
    `xcodebuild` signing).
  → slot the env-var identity + hard-fail + explicit `codesign` step into this
  script; no new release entrypoint needed.
- **Bundle id / app name / DMG volume name:**
  - Bundle id: `vision.lotech.Untouchable`
  - App: `Untouchable.app` (scheme `Untouchable`)
  - DMG volname: `Untouchable`; asset name: `Untouchable-<tag>.dmg`

## Config

- **`UNTOUCHABLE_SIGN_IDENTITY`** — the Developer ID Application cert's 40-char
  SHA-1 hash (use the hash, not the name, to avoid `ambiguous` errors when two
  certs share a name). Set in maintainer's `~/.zshrc` (not committed).
- **`UNTOUCHABLE_NOTARY_PROFILE`** — notarytool keychain profile name; value
  `<profile>` (shared across the maintainer's apps).
- **`UNTOUCHABLE_ALLOW_ADHOC_RELEASE`** — explicit opt-in override (`=1`) for a
  deliberate ad-hoc / unsigned build; otherwise the release path hard-fails
  when `UNTOUCHABLE_SIGN_IDENTITY` is unset.
- These are **identifiers, not secrets** (§8). The private key (`.p12`) and the
  app-specific password (inside the `<profile>` profile) stay in the
  Keychain and are never committed.

## Tasks

- [x] **Confirm account setup reusable** — maintainer confirmed the env vars
      are set in the shell. Final reuse check (`security find-identity -v -p
      codesigning` shows a `Developer ID Application` line; `xcrun notarytool
      history --keychain-profile "$UNTOUCHABLE_NOTARY_PROFILE"` returns without
      auth error) runs as part of `./scripts/release.sh --preflight` on the Mac.
- [x] Add env-var-driven signing identity (`UNTOUCHABLE_SIGN_IDENTITY`) +
      `UNTOUCHABLE_NOTARY_PROFILE`, replacing the auto-detect/hardcoded-profile
      logic. (`resolve_signing_identity` + `check_notary_profile` in
      `scripts/release.sh`.)
- [x] Add the **preflight hard-fail**: abort the release if
      `UNTOUCHABLE_SIGN_IDENTITY` is unset, unless
      `UNTOUCHABLE_ALLOW_ADHOC_RELEASE=1`.
- [x] Implement explicit **inside-out signing** step (`codesign_developer_id`):
      just the `.app` bundle, signed `--force --timestamp --options runtime
      --entitlements Untouchable/Untouchable.entitlements`, then `codesign
      --verify --deep --strict --verbose=2` and a hardened-runtime flag
      assertion. (No bundled-binary loop, no framework block — none exist.)
- [x] Wire **DMG-only** release flow: build → `codesign_developer_id` →
      `create_dmg` (ditto into staging + `/Applications` symlink, `hdiutil …
      UDZO`, DMG signed `--force --timestamp`, **no** `--options runtime`) →
      `notarytool submit … --keychain-profile "$NOTARY_PROFILE" --wait` →
      `stapler staple` → `stapler validate`. Staging copy switched `cp -R` →
      `ditto`.
- [x] **(Sparkle only)** — N/A for this app (no zip/appcast). Documented above.
- [x] **Local verify** (maintainer, macOS): `codesign_developer_id` runs
      `codesign --verify --deep --strict --verbose=2` + a hardened-runtime
      assertion during every release; v1.0.5 passed.
- [x] **Fresh-Mac verify** (maintainer): v1.0.5 DMG mounted on a Mac that had
      never run the app — launched with no Gatekeeper prompt, requested Input
      Monitoring, and About reported v1.0.5.
- [x] Write `RELEASING.md` (placeholders only: `you@example.com`, `TEAMID`,
      `<profile>` — no real Apple ID / Team ID / profile name / cert hash) +
      a one-line note in README that release builds are maintainer-signed and
      contributors can build/run unsigned.
- [x] Update `CHANGELOG.md` under `[Unreleased]`.
- [x] Fold any new lessons back into the shared playbook. Two new lessons from
      this app (paste into `macos-notarisation-playbook.md` §5):
      1. **Don't pipe `codesign -dvvv` straight into `grep -q` under
         `set -o pipefail`.** `grep -q` matches and closes the pipe early;
         `codesign` then dies with SIGPIPE (141) and `pipefail` propagates it,
         so the hardened-runtime assertion fails on a correctly signed build.
         Capture the output into a variable first, then grep it.
      2. **Single-source the app version through build settings.** If
         `CFBundleShortVersionString` is a hardcoded literal in `Info.plist`,
         dev/Xcode builds show a stale version no matter the release tag. Make
         `Info.plist` reference `$(MARKETING_VERSION)` /
         `$(CURRENT_PROJECT_VERSION)` and have the release script inject them at
         build time (`MARKETING_VERSION=<tag>
         CURRENT_PROJECT_VERSION=<git count>`) so dev and release agree.

## Open-source handling (§8)

- Public repo: **no identity values committed.** All read from env vars set in
  the maintainer's `~/.zshrc`; committed docs use placeholders only.
- **Building ≠ releasing:** contributors clone and build/run with Xcode
  dev/ad-hoc signing — unaffected. Only the *publish/release* path is gated on
  `UNTOUCHABLE_SIGN_IDENTITY`, so only the maintainer ships notarised binaries;
  a forker can plug in their own identity via the same env vars.

## Issues / notes

- This environment is **not macOS** — I cannot build, codesign, or notarise.
  Changes are made to the scripts/docs carefully; the maintainer runs and
  verifies on the Mac (local `spctl` + fresh-Mac DMG install).
- The existing `release.sh` already does a DMG + notarise; this work tightens
  it to the playbook (env-var identity, hard-fail, explicit inside-out sign,
  shared `<profile>` profile, `ditto` for the staging copy).
- DMG-only decision: for a no-Sparkle app the playbook skips the zip entirely;
  the app inside the DMG is covered by the DMG notarisation submission, and the
  stapled DMG gives offline Gatekeeper validation.
