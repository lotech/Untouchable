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

check_signing_identity() {
    log "Checking code-signing identities..."
    local identities
    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

    if echo "$identities" | grep -q "Developer ID Application"; then
        local id_line
        id_line="$(echo "$identities" | grep "Developer ID Application" | head -1)"
        SIGNING_IDENTITY="$(echo "$id_line" | sed 's/.*"\(.*\)"/\1/')"
        success "Signing identity: $SIGNING_IDENTITY"
    elif echo "$identities" | grep -q "Apple Development"; then
        warn "No 'Developer ID Application' certificate found."
        echo "      You have an Apple Development cert, which works for local use"
        echo "      but Gatekeeper will block it for other users."
        echo ""
        echo "      To distribute publicly, you need a Developer ID Application"
        echo "      certificate from https://developer.apple.com/account"
        echo ""
        if ask_yn "Continue with Apple Development signing anyway?" "n"; then
            local id_line
            id_line="$(echo "$identities" | grep "Apple Development" | head -1)"
            SIGNING_IDENTITY="$(echo "$id_line" | sed 's/.*"\(.*\)"/\1/')"
            warn "Using: $SIGNING_IDENTITY"
        else
            preflight_passed=false
        fi
    else
        fail "No valid signing identity found."
        echo "      Available identities:"
        echo "$identities" | sed 's/^/        /'
        echo ""
        echo "      Fix: Install a Developer ID Application certificate from"
        echo "           https://developer.apple.com/account"
        echo "           Or run: open /Applications/Utilities/Keychain\\ Access.app"
        preflight_passed=false
    fi
}

check_git_clean() {
    log "Checking working tree..."
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        warn "Working tree has uncommitted changes:"
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

    if ! [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        fail "Tag '$tag' does not match vX.Y.Z format."
        echo "      Fix: Use semantic versioning, e.g. v1.0.0, v0.2.1"
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
        warn "CHANGELOG.md has [Unreleased] but no [$version] section."
        echo "      Fix: Move [Unreleased] entries to [$version] - $(date +%Y-%m-%d)"
        echo "           before creating the release."
        if ! ask_yn "Continue anyway?" "n"; then
            preflight_passed=false
        fi
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

    check_signing_identity
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

# -- Build -----------------------------------------------------------------

do_release_build() {
    log "Resolving Swift package dependencies..."
    xcodebuild -resolvePackageDependencies \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -quiet 2>/dev/null || true

    log "Building $SCHEME (Release)..."
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR" \
        -quiet \
        ONLY_ACTIVE_ARCH=NO

    APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME"

    if [[ ! -d "$APP_PATH" ]]; then
        die "Build product not found at $APP_PATH" \
            "Check xcodebuild output above for errors."
    fi

    success "Build succeeded: $APP_PATH"
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
    cp -R "$app_path" "$staging/$APP_NAME"

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

    local size
    size="$(du -h "$dmg_path" | cut -f1)"
    success "DMG created: $dmg_path ($size)"
    DMG_PATH="$dmg_path"
}

# -- Notarization ----------------------------------------------------------

notarize_dmg() {
    local dmg_path="$1"

    log "Checking notarization prerequisites..."

    # Check for stored credentials
    if ! xcrun notarytool history --keychain-profile "Untouchable" &>/dev/null 2>&1; then
        warn "No stored notarization profile found."
        echo ""
        echo "  To set up notarization (one-time):"
        echo ""
        echo "    xcrun notarytool store-credentials \"Untouchable\" \\"
        echo "      --apple-id YOUR_APPLE_ID@example.com \\"
        echo "      --team-id YOUR_TEAM_ID \\"
        echo "      --password YOUR_APP_SPECIFIC_PASSWORD"
        echo ""
        echo "  Get an app-specific password at: https://appleid.apple.com/account/manage"
        echo "  Find your Team ID at: https://developer.apple.com/account -> Membership"
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

    if xcrun notarytool submit "$dmg_path" \
        --keychain-profile "Untouchable" \
        --wait; then
        success "Notarization succeeded."

        log "Stapling notarization ticket..."
        if xcrun stapler staple "$dmg_path"; then
            success "Stapled."
        else
            warn "Stapling failed. Users can still run the app (macOS checks online)."
        fi
    else
        fail "Notarization failed."
        echo ""
        echo "  Common causes:"
        echo "    - Missing hardened runtime"
        echo "    - Unsigned nested frameworks"
        echo "    - Invalid entitlements"
        echo ""
        echo "  View details:"
        echo "    xcrun notarytool log <submission-id> --keychain-profile Untouchable"
        echo ""
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
            do_release_build
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
            do_release_build
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

    log "Step 2/5: Verify signature"
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
