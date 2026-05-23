#!/usr/bin/env bash
set -euo pipefail

# Untouchable -- Release Script
#
# Builds a signed Release .app, packages it as a .dmg, optionally notarizes
# with Apple, and creates a GitHub Release.
#
# Every destructive/external step is preceded by preflight checks so you can
# fix problems before anything is uploaded.
#
# Usage:
#   ./scripts/release.sh                 # interactive -- asks before each step
#   ./scripts/release.sh --preflight     # run all checks, build nothing
#   ./scripts/release.sh --build-only    # build + package, skip GitHub upload
#   ./scripts/release.sh --full vX.Y.Z   # full pipeline for a given tag

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/Untouchable.xcodeproj"
SCHEME="Untouchable"
BUILD_DIR="$REPO_ROOT/build"
APP_NAME="Untouchable.app"
RELEASE_DIR="$REPO_ROOT/release"
DMG_VOLNAME="Untouchable"
ENTITLEMENTS="$REPO_ROOT/Untouchable/Untouchable.entitlements"

# Identity is read from the environment, never hardcoded (this is a public
# repo). The maintainer sets these in ~/.zshrc; contributors who don't set
# them simply can't run the signed/notarised release path -- building and
# running unsigned from source is unaffected. See RELEASING.md.
#   UNTOUCHABLE_SIGN_IDENTITY      -- Developer ID Application cert SHA-1 hash
#   UNTOUCHABLE_NOTARY_PROFILE     -- notarytool keychain profile name
#   UNTOUCHABLE_ALLOW_ADHOC_RELEASE=1 -- deliberate opt-in to an unsigned build
NOTARY_PROFILE="${UNTOUCHABLE_NOTARY_PROFILE:-}"
ADHOC=false
SIGNING_IDENTITY=""
TEAM_ID=""
RELEASE_VERSION=""
RELEASE_BUILD=""

cd "$REPO_ROOT"

# -- Helpers ---------------------------------------------------------------

log()     { echo "==> $*"; }
success() { echo "  [ok] $*"; }
warn()    { echo "  [..] $*"; }
fail()    { echo "  [!!] $*" >&2; }

ask_yn() {
    local prompt="$1" default="${2:-y}"
    local yn
    if [[ "$default" == "y" ]]; then
        read -rp "$prompt [Y/n]: " yn
        yn="${yn:-y}"
    else
        read -rp "$prompt [y/N]: " yn
        yn="${yn:-n}"
    fi
    case "$yn" in
        [Yy]) return 0 ;;
        *)    return 1 ;;
    esac
}

die() {
    fail "$1"
    echo ""
    echo "  How to fix: $2"
    echo ""
    exit 1
}

# Reset the working tree to the remote source of truth, discarding any local
# drift. The deploy machine only pulls, so local changes are never intentional
# -- a stale version bump from a prior run, an Info.plist/pbxproj rewrite by
# Xcode, or a half-finished merge/rebase (the UU state) -- and would otherwise
# block or corrupt a release. Set UNTOUCHABLE_KEEP_LOCAL=1 to opt out.
sync_to_remote() {
    local branch upstream
    branch="$(git rev-parse --abbrev-ref HEAD)"
    upstream="origin/$branch"

    log "Syncing to remote source of truth ($upstream)..."

    # Clear any in-progress merge/rebase so the reset can proceed cleanly.
    git merge --abort 2>/dev/null || true
    git rebase --abort 2>/dev/null || true

    local attempt delay=2
    for attempt in 1 2 3 4; do
        if git fetch origin "$branch" 2>/dev/null; then
            break
        fi
        if [[ $attempt -eq 4 ]]; then
            die "Could not fetch $upstream after 4 attempts." \
                "Check your network connection and that origin/$branch exists."
        fi
        warn "git fetch failed; retrying in ${delay}s..."
        sleep "$delay"
        delay=$((delay * 2))
    done

    if [[ -n "$(git status --porcelain)" ]] || \
       [[ "$(git rev-parse HEAD)" != "$(git rev-parse "$upstream")" ]]; then
        local drift
        drift="$(git status --short)"
        if [[ -n "$drift" ]]; then
            warn "Discarding local changes (remote is the source of truth):"
            echo "$drift" | sed 's/^/      /'
        fi
        git reset --hard "$upstream" >/dev/null
        success "Reset to $upstream ($(git rev-parse --short HEAD))."
    else
        success "Working tree matches $upstream."
    fi
}

# -- Preflight checks ------------------------------------------------------

preflight_passed=true

check_tool() {
    local tool="$1" fix="$2"
    if ! command -v "$tool" &>/dev/null; then
        fail "Missing: $tool"
        echo "      Fix: $fix"
        preflight_passed=false
    else
        success "Found: $tool ($(command -v "$tool"))"
    fi
}

resolve_signing_identity() {
    log "Resolving signing identity from environment..."

    # Hard-fail safeguard: never silently publish an unsigned build. The only
    # way past an unset identity is the explicit ad-hoc opt-in.
    if [[ -z "${UNTOUCHABLE_SIGN_IDENTITY:-}" ]]; then
        if [[ "${UNTOUCHABLE_ALLOW_ADHOC_RELEASE:-}" == "1" ]]; then
            warn "UNTOUCHABLE_SIGN_IDENTITY is unset and UNTOUCHABLE_ALLOW_ADHOC_RELEASE=1."
            warn "Building AD-HOC (unsigned) -- NOT for public distribution; Gatekeeper will block other users."
            SIGNING_IDENTITY="-"
            ADHOC=true
            return
        fi
        fail "UNTOUCHABLE_SIGN_IDENTITY is not set."
        echo "      Fix: export the Developer ID Application cert's SHA-1 hash, e.g. in ~/.zshrc:"
        echo "             export UNTOUCHABLE_SIGN_IDENTITY=<40-char-hash>"
        echo "           Find it with: security find-identity -v -p codesigning"
        echo "      For a deliberate unsigned/ad-hoc build instead, set:"
        echo "             export UNTOUCHABLE_ALLOW_ADHOC_RELEASE=1"
        preflight_passed=false
        return
    fi

    SIGNING_IDENTITY="$UNTOUCHABLE_SIGN_IDENTITY"
    ADHOC=false

    # Confirm the identity exists in the keychain and derive the Team ID from
    # its certificate name "...(TEAMID)". Match on the hash to stay unambiguous
    # even when two Developer ID certs share a display name.
    local id_line
    id_line="$(security find-identity -v -p codesigning 2>/dev/null | grep -i "$SIGNING_IDENTITY" | head -1 || true)"
    if [[ -z "$id_line" ]]; then
        fail "UNTOUCHABLE_SIGN_IDENTITY ($SIGNING_IDENTITY) not found in the keychain."
        echo "      Available codesigning identities:"
        security find-identity -v -p codesigning 2>/dev/null | sed 's/^/        /'
        preflight_passed=false
        return
    fi
    local id_name
    id_name="$(echo "$id_line" | sed 's/.*"\(.*\)".*/\1/')"
    TEAM_ID="$(echo "$id_name" | sed -n 's/.*(\([A-Z0-9]*\)).*/\1/p')"
    success "Signing identity: $id_name"
    [[ -n "$TEAM_ID" ]] && success "Team ID: $TEAM_ID"
}

check_notary_profile() {
    [[ "$ADHOC" == true ]] && return
    log "Checking notarytool profile..."
    if [[ -z "$NOTARY_PROFILE" ]]; then
        fail "UNTOUCHABLE_NOTARY_PROFILE is not set."
        echo "      Fix: export the shared notarytool keychain profile name, e.g. in ~/.zshrc:"
        echo "             export UNTOUCHABLE_NOTARY_PROFILE=<profile>"
        preflight_passed=false
        return
    fi
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" &>/dev/null; then
        success "Notary profile reachable: $NOTARY_PROFILE"
    else
        warn "Notary profile '$NOTARY_PROFILE' did not authenticate (or no history yet)."
        echo "      If notarisation later fails, re-store it (one-time):"
        echo "        xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id you@example.com --team-id TEAMID"
    fi
}

check_git_clean() {
    log "Checking working tree..."

    # Default: the remote is the source of truth; discard any local drift so a
    # stale Info.plist/CHANGELOG or an unmerged (UU) state never blocks release.
    if [[ "${UNTOUCHABLE_KEEP_LOCAL:-}" != "1" ]]; then
        sync_to_remote
        return
    fi

    # UNTOUCHABLE_KEEP_LOCAL=1: preserve local changes, just warn/confirm.
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        warn "Working tree has uncommitted changes (UNTOUCHABLE_KEEP_LOCAL=1):"
        git status --short | sed 's/^/      /'
        echo ""
        echo "      Fix: Commit or stash changes before releasing."
        if ! ask_yn "Continue anyway?" "n"; then
            preflight_passed=false
        fi
    else
        success "Working tree is clean."
    fi
}

check_tag() {
    local tag="$1"
    log "Checking tag $tag..."

    if ! [[ "$tag" =~ ^v[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        fail "Tag '$tag' does not match vX.Y.Z or vX.Y format."
        echo "      Fix: Use semantic versioning, e.g. v1.0.0, v1.0, v0.2.1"
        preflight_passed=false
        return
    fi

    if git rev-parse "$tag" &>/dev/null; then
        fail "Tag '$tag' already exists."
        echo "      Fix: Choose a new version number, or delete the old tag:"
        echo "           git tag -d $tag && git push origin :refs/tags/$tag"
        preflight_passed=false
        return
    fi

    success "Tag $tag is available."
}

check_changelog() {
    local version="${1#v}"
    log "Checking CHANGELOG.md for version $version..."
    if grep -q "## \[$version\]" "$REPO_ROOT/CHANGELOG.md" 2>/dev/null; then
        success "CHANGELOG.md has entry for [$version]."
    elif grep -q "## \[Unreleased\]" "$REPO_ROOT/CHANGELOG.md" 2>/dev/null; then
        log "Moving [Unreleased] entries to [$version] - $(date +%Y-%m-%d)..."
        local changelog="$REPO_ROOT/CHANGELOG.md"
        local today
        today="$(date +%Y-%m-%d)"
        # Rename [Unreleased] to [version] - date
        sed -i '' "s/## \[Unreleased\]/## [$version] - $today/" "$changelog"
        # Insert a fresh [Unreleased] section above the new versioned section
        sed -i '' "/## \[$version\] - $today/i\\
## [Unreleased]\\
" "$changelog"
        success "CHANGELOG.md updated: [Unreleased] -> [$version] - $today"
    else
        warn "No changelog entry found for $version."
    fi
}

run_preflight() {
    local tag="${1:-}"
    echo ""
    echo "+---------------------------------------+"
    echo "|       Release Preflight Checks        |"
    echo "+---------------------------------------+"
    echo ""

    log "Checking required tools..."
    check_tool "xcodebuild" "Install Xcode from the App Store"
    check_tool "hdiutil"    "Built into macOS -- reinstall macOS if missing"
    check_tool "codesign"   "Built into macOS -- install Xcode Command Line Tools"
    check_tool "gh"         "brew install gh && gh auth login"
    check_tool "git"        "xcode-select --install"
    echo ""

    resolve_signing_identity
    echo ""

    check_notary_profile
    echo ""

    check_git_clean
    echo ""

    if [[ -n "$tag" ]]; then
        check_tag "$tag"
        echo ""
        check_changelog "$tag"
        echo ""
    fi

    if [[ "$preflight_passed" == false ]]; then
        echo ""
        fail "Preflight failed. Fix the issues above before continuing."
        exit 1
    fi

    echo ""
    success "All preflight checks passed."
    echo ""
}

# -- Version sync ----------------------------------------------------------

set_version() {
    local tag="$1"
    RELEASE_VERSION="${tag#v}"

    # CFBundleVersion (build number) from git commit count.
    RELEASE_BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

    # The version is single-sourced through the MARKETING_VERSION /
    # CURRENT_PROJECT_VERSION build settings (Info.plist references them via
    # $(...)), so we inject them at build time rather than rewriting Info.plist
    # literals. This keeps dev/Xcode builds and release builds consistent.
    log "Release version: $RELEASE_VERSION ($RELEASE_BUILD)"
    success "Will inject MARKETING_VERSION=$RELEASE_VERSION CURRENT_PROJECT_VERSION=$RELEASE_BUILD."
}

# -- Build -----------------------------------------------------------------

do_release_build() {
    log "Resolving Swift package dependencies..."
    xcodebuild -resolvePackageDependencies \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -quiet 2>/dev/null || true

    log "Building $SCHEME (Release) with identity: $SIGNING_IDENTITY..."
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR" \
        -quiet \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        OTHER_CODE_SIGN_FLAGS="--timestamp" \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
        ${RELEASE_VERSION:+MARKETING_VERSION="$RELEASE_VERSION"} \
        ${RELEASE_BUILD:+CURRENT_PROJECT_VERSION="$RELEASE_BUILD"}

    APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME"

    if [[ ! -d "$APP_PATH" ]]; then
        die "Build product not found at $APP_PATH" \
            "Check xcodebuild output above for errors."
    fi

    success "Build succeeded: $APP_PATH"
}

# -- Sign (inside-out) -----------------------------------------------------

# Re-sign the built app with Developer ID, hardened runtime, a secure
# timestamp, and the project entitlements. For Untouchable this is just the
# .app bundle: there are no standalone binaries in Resources/ and no embedded
# frameworks with nested code (no Sparkle), so inside-out signing collapses to
# the outer bundle. If either of those is ever added, sign the deepest items
# first (see macos-notarisation-playbook.md inside-out ordering).
codesign_developer_id() {
    local app="$1"

    if [[ "$ADHOC" == true ]]; then
        warn "Ad-hoc build: skipping Developer ID re-sign."
        return
    fi

    log "Signing $APP_NAME (Developer ID, hardened runtime)..."
    local cs=(codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY")

    if [[ -f "$ENTITLEMENTS" ]]; then
        "${cs[@]}" --entitlements "$ENTITLEMENTS" "$app"
    else
        die "Entitlements file missing: $ENTITLEMENTS" \
            "Untouchable requires com.apple.security.device.input-monitoring; restore the file."
    fi

    codesign --verify --deep --strict --verbose=2 "$app"

    # Notarisation requires the hardened runtime, but codesign --verify won't
    # flag its absence -- confirm the flag is set before wasting a submit.
    # Capture first (don't pipe codesign directly into grep -q): under
    # `set -o pipefail`, grep -q closing the pipe early makes codesign exit
    # via SIGPIPE, which would fail this check even when the flag is present.
    local sig_flags
    sig_flags="$(codesign -dvvv "$app" 2>&1 || true)"
    if ! grep -q "flags=.*runtime" <<<"$sig_flags"; then
        die "Hardened runtime not enabled on $app" \
            "Ensure the --options runtime flag was applied during signing."
    fi
    success "Signed and verified (hardened runtime enabled)."
}

# -- Verify signing --------------------------------------------------------

verify_signing() {
    local app="$1"
    log "Verifying code signature..."

    if ! codesign --verify --deep --strict "$app" 2>/dev/null; then
        fail "Code signature verification failed."
        echo ""
        echo "  Details:"
        codesign --verify --deep --strict --verbose=4 "$app" 2>&1 | sed 's/^/    /'
        echo ""
        echo "  Fix: Ensure your signing identity is valid and the keychain is unlocked."
        echo "       Run: security unlock-keychain ~/Library/Keychains/login.keychain-db"
        return 1
    fi

    local sig_info
    sig_info="$(codesign -dvv "$app" 2>&1 || true)"
    local authority
    authority="$(echo "$sig_info" | grep "Authority=" | head -1 || true)"
    success "Signature valid: $authority"

    if echo "$sig_info" | grep -q "flags=0x10000(runtime)"; then
        success "Hardened runtime is enabled."
    else
        warn "Hardened runtime not detected. Notarization will fail without it."
        echo "      Fix: Enable 'Hardened Runtime' in Xcode signing settings."
    fi

    # Verify no unexpected entitlements (e.g. get-task-allow blocks notarization)
    local entitlements
    entitlements="$(codesign -d --entitlements - "$app" 2>&1 || true)"
    if echo "$entitlements" | grep -q "get-task-allow"; then
        fail "com.apple.security.get-task-allow entitlement found in release build."
        echo "      This entitlement is auto-injected for debug builds and will cause"
        echo "      notarization rejection."
        echo "      Fix: Ensure CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO in build settings."
        return 1
    fi
    success "No unexpected entitlements found."

    # Verify embedded version matches release tag
    if [[ -n "${RELEASE_VERSION:-}" ]]; then
        local embedded_ver
        embedded_ver="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
            "$app/Contents/Info.plist" 2>/dev/null || echo "?")"
        if [[ "$embedded_ver" == "$RELEASE_VERSION" ]]; then
            success "Embedded version: $embedded_ver"
        else
            fail "Version mismatch: binary has $embedded_ver, expected $RELEASE_VERSION"
            return 1
        fi
    fi
}

# -- Package DMG -----------------------------------------------------------

create_dmg() {
    local app_path="$1" tag="$2"
    local dmg_name="Untouchable-${tag}.dmg"
    local dmg_path="$RELEASE_DIR/$dmg_name"

    mkdir -p "$RELEASE_DIR"

    # Clean up previous DMG if present
    rm -f "$dmg_path"

    log "Creating DMG: $dmg_name..."

    # Create a temporary directory with a nice layout
    local staging="$RELEASE_DIR/.staging"
    rm -rf "$staging"
    mkdir -p "$staging"
    # ditto (not cp -R) preserves the stapled ticket, symlinks, and xattrs.
    ditto "$app_path" "$staging/$APP_NAME"

    # Symlink to /Applications for drag-install
    ln -s /Applications "$staging/Applications"

    hdiutil create \
        -volname "$DMG_VOLNAME" \
        -srcfolder "$staging" \
        -ov \
        -format UDZO \
        "$dmg_path" \
        -quiet

    rm -rf "$staging"

    if [[ ! -f "$dmg_path" ]]; then
        die "DMG creation failed." \
            "Check disk space and permissions in $RELEASE_DIR"
    fi

    if [[ "$ADHOC" == true ]]; then
        warn "Ad-hoc build: leaving DMG unsigned."
    else
        log "Signing DMG..."
        # No --options runtime: a DMG is a container, not code.
        codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$dmg_path"
        success "DMG signed."
    fi

    local size
    size="$(du -h "$dmg_path" | cut -f1)"
    success "DMG created: $dmg_path ($size)"
    DMG_PATH="$dmg_path"
}

# -- Notarization ----------------------------------------------------------

notarize_dmg() {
    local dmg_path="$1"

    if [[ "$ADHOC" == true ]]; then
        warn "Ad-hoc build: skipping notarization. Users will see a Gatekeeper warning."
        return 0
    fi

    log "Checking notarization prerequisites..."

    # Check for stored credentials under the configured profile.
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" &>/dev/null 2>&1; then
        warn "Notary profile '$NOTARY_PROFILE' not found / not authenticating."
        echo ""
        echo "  To set up notarization (one-time):"
        echo ""
        echo "    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
        echo "      --apple-id you@example.com \\"
        echo "      --team-id TEAMID"
        echo ""
        echo "  notarytool prompts for the app-specific password interactively"
        echo "  (keeps it out of shell history). Get one at:"
        echo "    https://account.apple.com -> Sign-In and Security -> App-Specific Passwords"
        echo ""
        if ! ask_yn "Skip notarization and continue?" "y"; then
            exit 1
        fi
        warn "Skipping notarization. Users will see a Gatekeeper warning."
        return 0
    fi

    log "Submitting $dmg_path for notarization..."
    echo "  (This usually takes 2-10 minutes)"
    echo ""

    local notary_output
    notary_output="$(xcrun notarytool submit "$dmg_path" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait 2>&1)" || true

    echo "$notary_output"
    echo ""

    # Extract the submission ID for log retrieval
    local submission_id
    submission_id="$(echo "$notary_output" | grep '  id:' | head -1 | awk '{print $2}')"

    # notarytool returns exit 0 even on Invalid status, so check the actual output
    if echo "$notary_output" | grep -q "status: Accepted"; then
        success "Notarization succeeded."

        log "Stapling notarization ticket to the DMG..."
        if xcrun stapler staple "$dmg_path"; then
            success "Stapled."
            if xcrun stapler validate "$dmg_path" &>/dev/null; then
                success "Staple validated."
            else
                warn "stapler validate did not confirm the ticket; re-check before publishing."
            fi
        else
            warn "Stapling failed. Users can still run the app (macOS checks online)."
        fi
    else
        fail "Notarization failed or was rejected by Apple."
        echo ""
        if [[ -n "$submission_id" ]]; then
            echo "  Fetching notarization log..."
            echo ""
            xcrun notarytool log "$submission_id" \
                --keychain-profile "$NOTARY_PROFILE" 2>&1 || true
            echo ""
        fi
        echo "  Common causes:"
        echo "    - Missing hardened runtime"
        echo "    - Unsigned nested frameworks"
        echo "    - Invalid entitlements"
        echo ""
        if [[ -n "$submission_id" ]]; then
            echo "  View full details:"
            echo "    xcrun notarytool log $submission_id --keychain-profile \"$NOTARY_PROFILE\""
            echo ""
        fi
        if ! ask_yn "Continue without notarization?" "n"; then
            exit 1
        fi
        warn "Continuing without notarization."
    fi
}

# -- GitHub Release --------------------------------------------------------

create_github_release() {
    local tag="$1" dmg_path="$2"

    log "Checking GitHub CLI auth..."
    if ! gh auth status &>/dev/null 2>&1; then
        die "Not authenticated with GitHub CLI." \
            "Run: gh auth login"
    fi
    success "GitHub CLI authenticated."

    log "Checking remote repository..."
    local remote_url
    remote_url="$(git remote get-url origin 2>/dev/null || true)"
    if [[ -z "$remote_url" ]]; then
        die "No 'origin' remote configured." \
            "Run: git remote add origin https://github.com/YOUR/REPO.git"
    fi
    success "Remote: $remote_url"

    # Extract release notes from CHANGELOG
    local version="${tag#v}"
    local notes=""

    if grep -q "## \[$version\]" "$REPO_ROOT/CHANGELOG.md" 2>/dev/null; then
        log "Extracting release notes from CHANGELOG.md..."
        # Extract everything between this version header and the next version header
        notes="$(awk "/^## \[$version\]/{found=1; next} /^## \[/{if(found) exit} found" \
            "$REPO_ROOT/CHANGELOG.md")"
        if [[ -n "$notes" ]]; then
            success "Release notes extracted from CHANGELOG.md"
        fi
    fi

    if [[ -z "$notes" ]]; then
        warn "No release notes found in CHANGELOG.md for $version."
        notes="Release $tag"
    fi

    # Show summary before creating
    echo ""
    echo "+---------------------------------------+"
    echo "|        GitHub Release Summary         |"
    echo "+---------------------------------------+"
    echo ""
    echo "  Tag:      $tag"
    echo "  Asset:    $(basename "$dmg_path")"
    echo "  Size:     $(du -h "$dmg_path" | cut -f1)"
    echo "  Remote:   $remote_url"
    echo ""
    echo "  Release notes:"
    echo "$notes" | sed 's/^/    /'
    echo ""

    if ! ask_yn "Create this GitHub Release?" "y"; then
        log "Aborted. Your DMG is still at: $dmg_path"
        return 0
    fi

    # Commit version bump and changelog so the tagged commit is complete
    local release_files=()
    [[ -n "$(git diff --name-only Untouchable/Info.plist 2>/dev/null)" ]] && release_files+=("Untouchable/Info.plist")
    [[ -n "$(git diff --name-only CHANGELOG.md 2>/dev/null)" ]] && release_files+=("CHANGELOG.md")
    if [[ ${#release_files[@]} -gt 0 ]]; then
        log "Committing release changes..."
        git add "${release_files[@]}"
        git commit -m "Prepare release ${tag#v}"
        success "Release changes committed."
    fi

    log "Creating git tag $tag..."
    git tag -a "$tag" -m "Release $tag"
    success "Tag created."

    log "Pushing tag to origin..."
    git push origin "$tag"
    success "Tag pushed."

    log "Creating GitHub Release..."
    gh release create "$tag" \
        "$dmg_path" \
        --title "$tag" \
        --notes "$notes"

    success "GitHub Release created."

    local release_url
    release_url="$(gh release view "$tag" --json url -q '.url' 2>/dev/null || true)"
    if [[ -n "$release_url" ]]; then
        echo ""
        echo "  Release URL: $release_url"
        echo ""
    fi
}

# -- Main ------------------------------------------------------------------

main() {
    echo ""
    echo "+---------------------------------------+"
    echo "|       Untouchable Release Tool        |"
    echo "+---------------------------------------+"
    echo ""

    local mode="${1:-}"
    local tag="${2:-}"

    case "$mode" in
        --preflight)
            run_preflight "${tag:-}"
            exit 0
            ;;
        --build-only)
            tag="${tag:-v0.0.0-local}"
            run_preflight ""
            RELEASE_VERSION="${tag#v}"
            set_version "$tag"
            do_release_build
            codesign_developer_id "$BUILD_DIR/Build/Products/Release/$APP_NAME"
            verify_signing "$BUILD_DIR/Build/Products/Release/$APP_NAME"
            create_dmg "$BUILD_DIR/Build/Products/Release/$APP_NAME" "$tag"
            echo ""
            success "Done. DMG at: $DMG_PATH"
            exit 0
            ;;
        --full)
            if [[ -z "$tag" ]]; then
                die "Tag required for --full mode." \
                    "Usage: ./scripts/release.sh --full v1.0.0"
            fi
            run_preflight "$tag"
            RELEASE_VERSION="${tag#v}"
            set_version "$tag"
            do_release_build
            codesign_developer_id "$BUILD_DIR/Build/Products/Release/$APP_NAME"
            verify_signing "$BUILD_DIR/Build/Products/Release/$APP_NAME"
            create_dmg "$BUILD_DIR/Build/Products/Release/$APP_NAME" "$tag"
            notarize_dmg "$DMG_PATH"
            create_github_release "$tag" "$DMG_PATH"
            echo ""
            success "Release $tag complete."
            exit 0
            ;;
        "")
            # Interactive mode
            ;;
        *)
            echo "Usage: $(basename "$0") [--preflight|--build-only|--full vX.Y.Z]"
            echo ""
            echo "  --preflight        Run all checks, build nothing"
            echo "  --build-only       Build + sign + package DMG (no upload)"
            echo "  --full vX.Y.Z     Full pipeline: build, sign, notarize, release"
            echo "  (no args)          Interactive mode"
            exit 1
            ;;
    esac

    # -- Interactive mode --------------------------------------------------

    echo "What version are you releasing?"
    read -rp "Tag (e.g. v1.0.0): " tag

    if [[ -z "$tag" ]]; then
        die "No tag provided." "Enter a version like v1.0.0"
    fi

    run_preflight "$tag"

    RELEASE_VERSION="${tag#v}"
    set_version "$tag"

    log "Step 1/5: Build"
    if ask_yn "Build Release configuration?"; then
        do_release_build
    else
        # Check for existing build
        APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME"
        if [[ -d "$APP_PATH" ]]; then
            warn "Using existing build at $APP_PATH"
        else
            die "No existing build found." "Build first, or answer yes above."
        fi
    fi
    APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME"
    echo ""

    log "Step 2/5: Sign + verify"
    codesign_developer_id "$APP_PATH"
    verify_signing "$APP_PATH"
    echo ""

    log "Step 3/5: Package DMG"
    create_dmg "$APP_PATH" "$tag"
    echo ""

    log "Step 4/5: Notarize"
    if ask_yn "Submit to Apple for notarization?" "y"; then
        notarize_dmg "$DMG_PATH"
    else
        warn "Skipping notarization."
    fi
    echo ""

    log "Step 5/5: GitHub Release"
    if ask_yn "Create GitHub Release for $tag?" "y"; then
        create_github_release "$tag" "$DMG_PATH"
    else
        log "Skipped. Your DMG is at: $DMG_PATH"
    fi

    echo ""
    success "All done."
}

main "$@"
