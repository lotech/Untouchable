#!/usr/bin/env bash
set -euo pipefail

# Untouchable — Build & Install Script
#
# Usage:
#   ./scripts/build.sh              # Build release and install to /Applications
#   ./scripts/build.sh --open       # Just open in Xcode
#   ./scripts/build.sh --pull       # Pull latest from GitHub, then build & install

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/Untouchable.xcodeproj"
SCHEME="Untouchable"
CONFIG="Release"
BUILD_DIR="$REPO_ROOT/build"
APP_NAME="Untouchable.app"
INSTALL_DIR="/Applications"

cd "$REPO_ROOT"

# ── Helpers ──────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --pull      Pull latest changes from GitHub before building
  --open      Open the project in Xcode (no build)
  --debug     Build in Debug configuration
  --no-install  Build only, don't copy to /Applications
  -h, --help  Show this help message

Default (no flags): build Release and install to /Applications.
EOF
    exit 0
}

log() { echo "==> $*"; }

# ── Parse flags ──────────────────────────────────────────────────────

DO_PULL=false
DO_OPEN=false
DO_INSTALL=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pull)       DO_PULL=true;  shift ;;
        --open)       DO_OPEN=true;  shift ;;
        --debug)      CONFIG="Debug"; shift ;;
        --no-install) DO_INSTALL=false; shift ;;
        -h|--help)    usage ;;
        *)            echo "Unknown option: $1"; usage ;;
    esac
done

# ── Open in Xcode ───────────────────────────────────────────────────

if $DO_OPEN; then
    log "Opening $PROJECT in Xcode…"
    open "$PROJECT"
    exit 0
fi

# ── Pull ─────────────────────────────────────────────────────────────

if $DO_PULL; then
    log "Pulling latest from origin…"
    git pull origin "$(git rev-parse --abbrev-ref HEAD)"
fi

# ── Resolve packages ────────────────────────────────────────────────

log "Resolving Swift package dependencies…"
xcodebuild -resolvePackageDependencies \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -quiet 2>/dev/null || true

# ── Build ────────────────────────────────────────────────────────────

log "Building $SCHEME ($CONFIG)…"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" \
    -quiet \
    ONLY_ACTIVE_ARCH=NO

APP_PATH="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME"

if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: Build product not found at $APP_PATH"
    exit 1
fi

log "Build succeeded: $APP_PATH"

# ── Install ──────────────────────────────────────────────────────────

if $DO_INSTALL; then
    log "Installing to $INSTALL_DIR/$APP_NAME…"

    # Quit the running app if present
    osascript -e 'tell application "Untouchable" to quit' 2>/dev/null || true
    sleep 0.5

    # Copy to /Applications (may need sudo)
    if [[ -w "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR/$APP_NAME"
        cp -R "$APP_PATH" "$INSTALL_DIR/$APP_NAME"
    else
        sudo rm -rf "$INSTALL_DIR/$APP_NAME"
        sudo cp -R "$APP_PATH" "$INSTALL_DIR/$APP_NAME"
    fi

    log "Installed to $INSTALL_DIR/$APP_NAME"
    log "Launching Untouchable…"
    open "$INSTALL_DIR/$APP_NAME"
fi

log "Done."
