#!/usr/bin/env bash
set -euo pipefail

# Untouchable -- Build & Deploy Script

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/Untouchable.xcodeproj"
SCHEME="Untouchable"
BUILD_DIR="$REPO_ROOT/build"
APP_NAME="Untouchable.app"
INSTALL_DIR="/Applications"

cd "$REPO_ROOT"

# -- Helpers ---------------------------------------------------------------

log()     { echo "==> $*"; }
success() { echo "  [ok] $*"; }
fail()    { echo "  [!!] $*" >&2; }

# -- Actions ---------------------------------------------------------------

do_pull() {
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD)"
    log "Pulling latest from origin/${branch}..."
    git pull origin "${branch}"
    success "Up to date."
}

do_open() {
    log "Opening project in Xcode..."
    open "$PROJECT"
    success "Opened $PROJECT"
}

do_build() {
    local config="${1:-Release}"

    log "Resolving Swift package dependencies..."
    xcodebuild -resolvePackageDependencies \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -quiet 2>/dev/null || true

    log "Building $SCHEME ($config)..."
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$config" \
        -derivedDataPath "$BUILD_DIR" \
        -quiet \
        ONLY_ACTIVE_ARCH=NO

    APP_PATH="$BUILD_DIR/Build/Products/$config/$APP_NAME"

    if [[ ! -d "$APP_PATH" ]]; then
        fail "Build product not found at $APP_PATH"
        return 1
    fi

    success "Build succeeded: $APP_PATH"
}

do_install() {
    local config="${1:-Release}"
    APP_PATH="$BUILD_DIR/Build/Products/$config/$APP_NAME"

    if [[ ! -d "$APP_PATH" ]]; then
        fail "No build product found. Build first."
        return 1
    fi

    log "Installing to $INSTALL_DIR/$APP_NAME..."

    # Quit the running app if present
    osascript -e 'tell application "Untouchable" to quit' 2>/dev/null || true
    sleep 0.5

    if [[ -w "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR/$APP_NAME"
        cp -R "$APP_PATH" "$INSTALL_DIR/$APP_NAME"
    else
        sudo rm -rf "$INSTALL_DIR/$APP_NAME"
        sudo cp -R "$APP_PATH" "$INSTALL_DIR/$APP_NAME"
    fi

    success "Installed to $INSTALL_DIR/$APP_NAME"
}

do_launch() {
    if [[ -d "$INSTALL_DIR/$APP_NAME" ]]; then
        log "Launching Untouchable..."
        open "$INSTALL_DIR/$APP_NAME"
    else
        fail "App not found in $INSTALL_DIR. Install first."
    fi
}

do_clean() {
    log "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
    success "Build directory removed."
}

# -- Menu ------------------------------------------------------------------

show_menu() {
    echo ""
    echo "+---------------------------------------+"
    echo "|         Untouchable Builder           |"
    echo "+---------------------------------------+"
    echo "|                                       |"
    echo "|  1)  Pull latest from GitHub          |"
    echo "|  2)  Open in Xcode                    |"
    echo "|  3)  Build (Release)                  |"
    echo "|  4)  Build (Debug)                    |"
    echo "|  5)  Install to /Applications         |"
    echo "|  6)  Build + Install (Release)        |"
    echo "|  7)  Pull + Build + Install           |"
    echo "|  8)  Launch Untouchable               |"
    echo "|  9)  Clean build directory            |"
    echo "|  0)  Quit                             |"
    echo "|                                       |"
    echo "+---------------------------------------+"
    echo ""
}

# -- Main loop -------------------------------------------------------------

# If flags are passed, run non-interactively for CI/scripting
if [[ $# -gt 0 ]]; then
    case "$1" in
        --pull)    do_pull ;;
        --open)    do_open ;;
        --build)   do_build "${2:-Release}" ;;
        --install) do_build "${2:-Release}" && do_install "${2:-Release}" ;;
        --clean)   do_clean ;;
        --help|-h)
            echo "Usage: $(basename "$0") [--pull|--open|--build|--install|--clean]"
            echo "       $(basename "$0")          # interactive menu"
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    exit 0
fi

# Interactive menu
while true; do
    show_menu
    read -rp "Choose [0-9]: " choice

    case "$choice" in
        1) do_pull ;;
        2) do_open ;;
        3) do_build "Release" ;;
        4) do_build "Debug" ;;
        5) do_install "Release" ;;
        6) do_build "Release" && do_install "Release" ;;
        7) do_pull && do_build "Release" && do_install "Release" ;;
        8) do_launch ;;
        9) do_clean ;;
        0) echo "Bye."; exit 0 ;;
        *) fail "Invalid choice." ;;
    esac

    echo ""
    read -rp "Press Enter to continue..."
done
