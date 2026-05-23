# Releasing Untouchable

Release builds of Untouchable are **Developer ID-signed and notarised by Apple
by the maintainer**. Contributors do **not** need any of this to build or run
the app: clone, open in Xcode, and build -- Xcode dev/ad-hoc signs locally.
Only the *publish* path below is signed and notarised, and it is gated on
environment variables that only the maintainer sets.

This repo is public, so **no identity values are committed**. The release
script reads them from the environment; the placeholders below
(`you@example.com`, `TEAMID`, `<profile>`, `<40-char-hash>`) are illustrative.

## `build.sh` vs `release.sh`

Two scripts, two jobs. You almost never need to remember a flag -- run either
with **no arguments** for an interactive menu/prompt.

| | `scripts/build.sh` | `scripts/release.sh` |
|---|---|---|
| Purpose | Local development | Publish a version to users |
| Builds | Debug or Release, unsigned/local | Release, Developer ID-signed |
| Output | `Untouchable.app` in `/Applications` | Signed, notarised `.dmg` + GitHub Release |
| Touches the network | only `git pull` | uploads to Apple + GitHub |
| Run it as | `./scripts/build.sh` (menu) | `./scripts/release.sh` (prompts for version) |

Rule of thumb: **`build.sh` = "test my code on this Mac"**, **`release.sh` =
"ship a new version to the world."**

The flags (`--build`, `--full`, `--preflight`, ...) are **optional** shortcuts
for CI/scripting. Running with no flags is fully supported and is the easy path.

## Common tasks

```sh
# I changed some code and want to run it locally:
./scripts/build.sh            # pick "Build + Install", then "Launch"

# I want to cut a new public release:
./scripts/release.sh          # it prompts: "What version are you releasing?"
                              # enter e.g. v1.2.0 and follow the steps
```

The version you enter at the release prompt flows straight into the app: the
About box shows exactly that version (see [Versioning](#versioning) below). You
do not edit any version numbers by hand.

## What you need (maintainer, one-time)

These are tied to your Apple **account** and **machine**, shared across all
your apps -- not specific to Untouchable:

1. Apple Developer Program membership (paid).
2. A **Developer ID Application** certificate + private key in your login
   Keychain (and a `.p12` backup of both -- a `.cer` is not a backup).
3. A **notarytool keychain profile** storing your Apple ID + Team ID +
   app-specific password:
   ```sh
   xcrun notarytool store-credentials "<profile>" \
       --apple-id you@example.com --team-id TEAMID
   # notarytool prompts for the app-specific password interactively.
   ```

Confirm both are reusable (no need to recreate if another app already
notarises on this machine):
```sh
security find-identity -v -p codesigning          # expect a "Developer ID Application" line
xcrun notarytool history --keychain-profile "<profile>"   # returns without an auth error
```

## Environment variables (maintainer, in ~/.zshrc -- not committed)

```sh
export UNTOUCHABLE_SIGN_IDENTITY=<40-char-hash>   # SHA-1 hash of the Developer ID Application cert
export UNTOUCHABLE_NOTARY_PROFILE=<profile>       # the notarytool keychain profile name
```

Use the cert's **SHA-1 hash** (left column of `security find-identity -v -p
codesigning`), not its name -- if two Developer ID certs share a name,
`codesign` errors with `ambiguous (matches more than one identity)`.

These are **identifiers, not secrets**: the Team ID and cert name are already
public on any notarised app you ship (`codesign -dvv App.app` prints them).
The actual secrets -- the private key and the app-specific password -- stay in
the Keychain and are never committed. The env-var indirection just keeps
personal identifiers out of public history and makes the script fork-friendly.

## Releasing

The pipeline lives in `scripts/release.sh`:

```sh
./scripts/release.sh --preflight        # checks only: tools, identity, profile
./scripts/release.sh --build-only vX.Y.Z   # build + sign + DMG (no notarise/upload)
./scripts/release.sh --full vX.Y.Z      # build -> sign -> DMG -> notarise -> staple -> GitHub release
./scripts/release.sh                    # interactive (asks before each step)
```

What `--full` does, in order:

1. **Preflight** -- hard-fails if `UNTOUCHABLE_SIGN_IDENTITY` is unset (see
   below), confirms the identity is in the keychain, checks the notary profile,
   verifies a clean tree and an available tag.
2. **Build** the Release configuration (`xcodebuild`).
3. **Sign** (inside-out): for Untouchable this is just the `.app`, signed with
   `--options runtime` (hardened runtime, required for notarisation) and the
   project entitlements (`Untouchable/Untouchable.entitlements`). There are no
   bundled binaries in `Resources/` and no embedded frameworks, so there is
   nothing nested to sign first.
4. **DMG** -- stage the app (via `ditto`, preserving symlinks/xattrs) plus an
   `/Applications` symlink, `hdiutil create ... -format UDZO`, then sign the
   DMG (no `--options runtime` -- a DMG is a container, not code).
5. **Notarise** the DMG: `xcrun notarytool submit ... --wait`, expecting
   `status: Accepted`.
6. **Staple** the ticket to the DMG and `stapler validate` it (so Gatekeeper
   validates offline).
7. **Publish** the DMG to a GitHub Release.

Untouchable does **not** use Sparkle, so there is no `-update.zip` enclosure
or appcast -- the DMG is the only distributed artifact. (If Sparkle is ever
wired up, add the zip + appcast path; see the notarisation playbook.)

## The hard-fail safeguard

The release path **refuses to publish an unsigned build**. If
`UNTOUCHABLE_SIGN_IDENTITY` is unset, preflight fails with instructions. For a
deliberate unsigned/ad-hoc build (local testing only -- Gatekeeper will block
other users), opt in explicitly:

```sh
UNTOUCHABLE_ALLOW_ADHOC_RELEASE=1 ./scripts/release.sh --build-only vX.Y.Z
```

## Verifying a release

On the build machine:
```sh
codesign --verify --deep --strict --verbose=2 build/Build/Products/Release/Untouchable.app
spctl -a -vvv build/Build/Products/Release/Untouchable.app   # -> accepted / source=Notarized Developer ID
```

On a **fresh** Mac (one that has never run the app): mount the DMG, drag
Untouchable to Applications, launch -- there should be no Gatekeeper warning.

If notarisation comes back `Invalid`, the exact offending file is named by:
```sh
xcrun notarytool log <submission-id> --keychain-profile "<profile>"
```

## Versioning

The app version is single-sourced through Xcode build settings:
`Untouchable/Info.plist` sets `CFBundleShortVersionString` to
`$(MARKETING_VERSION)` and `CFBundleVersion` to `$(CURRENT_PROJECT_VERSION)`.

- **Release builds:** `release.sh` injects `MARKETING_VERSION=<tag>` and
  `CURRENT_PROJECT_VERSION=<git commit count>` at build time, so the DMG always
  matches the tag. No file edits, nothing to commit.
- **Dev / `build.sh` / Xcode builds:** use the committed `MARKETING_VERSION` in
  `Untouchable.xcodeproj/project.pbxproj`. Bump it when you start a new
  development cycle so local builds don't show a stale version.

## Forking

A forker who wants their own notarised build just sets the same two env vars to
*their* Developer ID identity and notarytool profile. No code changes needed.
