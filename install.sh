#!/bin/sh
# audiobookshelf-binary installer.
# Usage:
#   curl -sS https://abhinandval.github.io/audiobookshelf-binary/install.sh | sh
#   curl -sS .../install.sh | sh -s -- --yes --version v2.35.0
set -eu

REPO="abhinandval/audiobookshelf-binary"
INSTALL_DIR="${HOME}/.local/share/audiobookshelf"
BIN_DIR="${HOME}/.local/bin"
ABS_HOME="${ABS_HOME:-${HOME}/.audiobookshelf}"
FFMPEG_MIN_MAJOR=5
FFMPEG_MIN_MINOR=1

ASSUME_YES=0
SKIP_FFMPEG=0
VERSION=""

WORKDIR=""
cleanup() { [ -n "$WORKDIR" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT INT TERM

info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
err() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        -y | --yes) ASSUME_YES=1 ;;
        --skip-ffmpeg-check) SKIP_FFMPEG=1 ;;
        --version)
            VERSION="${2:-}"
            shift
            ;;
        --version=*) VERSION="${1#*=}" ;;
        -h | --help)
            info "Usage: install.sh [--yes] [--skip-ffmpeg-check] [--version <tag>]"
            exit 0
            ;;
        *) err "unknown option: $1" ;;
    esac
    shift
done

have() { command -v "$1" > /dev/null 2>&1; }

require_tools() {
    have tar || err "tar is required"
    have uname || err "uname is required"
    if ! have curl && ! have wget; then err "curl or wget is required"; fi
    if ! have sha256sum && ! have shasum; then err "sha256sum or shasum is required"; fi
}

# Echoes the release target (e.g. "linux-arm64") for this host, or empty.
detect_target() {
    os="$(uname -s)"
    arch="$(uname -m)"
    case "$os" in
        Linux) os="linux" ;;
        Darwin) os="macos" ;;
        *) os="" ;;
    esac
    case "$arch" in
        x86_64 | amd64) arch="amd64" ;;
        aarch64 | arm64) arch="arm64" ;;
        *) arch="" ;;
    esac
    [ -n "$os" ] && [ -n "$arch" ] && printf '%s-%s' "$os" "$arch"
}

# Targets we currently publish assets for.
target_supported() {
    case "$1" in
        linux-arm64) return 0 ;;
        *) return 1 ;;
    esac
}

sha256_check() {
    # $1 = file, $2 = expected hex
    if have sha256sum; then
        printf '%s  %s\n' "$2" "$1" | sha256sum -c - > /dev/null 2>&1
    else
        printf '%s  %s\n' "$2" "$1" | shasum -a 256 -c - > /dev/null 2>&1
    fi
}

# Exits non-zero (via err) when ffmpeg is unsuitable. Mirrors scripts/start.sh.
check_ffmpeg() {
    [ "$SKIP_FFMPEG" -eq 1 ] && return 0
    [ -n "${FFMPEG_PATH:-}" ] && return 0 # user-provided ffmpeg, trusted

    if ! have ffmpeg; then
        err "ffmpeg (>= ${FFMPEG_MIN_MAJOR}.${FFMPEG_MIN_MINOR}) is required and was not found on PATH.
  Debian/Ubuntu/Raspberry Pi OS: sudo apt install ffmpeg
  Fedora: sudo dnf install ffmpeg   macOS: brew install ffmpeg   Termux: pkg install ffmpeg
  Re-run with --skip-ffmpeg-check to bypass if you will supply ffmpeg later."
    fi

    ver="$(ffmpeg -version 2> /dev/null | head -n1 | awk '{print $3}')"
    ver="${ver#n}"
    ver="${ver#N}"
    major="$(printf '%s' "$ver" | sed -n 's/^\([0-9][0-9]*\)\..*/\1/p')"
    minor="$(printf '%s' "$ver" | sed -n 's/^[0-9][0-9]*\.\([0-9][0-9]*\).*/\1/p')"

    if [ -z "$major" ] || [ -z "$minor" ]; then
        warn "could not parse ffmpeg version ('${ver}'); assuming it is recent enough."
        return 0
    fi
    if [ "$major" -lt "$FFMPEG_MIN_MAJOR" ] ||
        { [ "$major" -eq "$FFMPEG_MIN_MAJOR" ] && [ "$minor" -lt "$FFMPEG_MIN_MINOR" ]; }; then
        err "ffmpeg ${major}.${minor} is too old; audiobookshelf needs >= ${FFMPEG_MIN_MAJOR}.${FFMPEG_MIN_MINOR}.
  Upgrade ffmpeg, or re-run with FFMPEG_PATH set to a newer build, or --skip-ffmpeg-check."
    fi
    info "Found ffmpeg ${major}.${minor}"
}

# Download URL ($1) to file ($2).
fetch() {
    if have curl; then
        curl -fsSL "$1" -o "$2"
    else
        wget -qO "$2" "$1"
    fi
}

# Print stdout of a URL.
fetch_stdout() {
    if have curl; then
        curl -fsSL "$1"
    else
        wget -qO - "$1"
    fi
}

# Sets RESOLVED_TAG, TARBALL_URL, SHA_URL for $TARGET (honours $VERSION).
resolve_release() {
    if [ -n "$VERSION" ]; then
        RESOLVED_TAG="$VERSION"
    else
        api="https://api.github.com/repos/${REPO}/releases/latest"
        RESOLVED_TAG="$(fetch_stdout "$api" | sed -n 's/.*"tag_name"[ ]*:[ ]*"\([^"]*\)".*/\1/p' | head -n1)"
        [ -n "$RESOLVED_TAG" ] || err "could not determine latest release tag"
    fi
    base="https://github.com/${REPO}/releases/download/${RESOLVED_TAG}"
    asset="audiobookshelf-${RESOLVED_TAG}-${TARGET}.tar.gz"
    TARBALL_URL="${base}/${asset}"
    SHA_URL="${TARBALL_URL}.sha256"
}

confirm() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    if [ -r /dev/tty ]; then
        printf 'Proceed with installation? [y/N] '
        read -r reply < /dev/tty
        case "$reply" in
            [yY] | [yY][eE][sS]) return 0 ;;
            *) err "aborted by user" ;;
        esac
    else
        err "no terminal for confirmation; re-run with --yes to install non-interactively"
    fi
}

do_install() {
    WORKDIR="$(mktemp -d)"
    tarball="${WORKDIR}/abs.tar.gz"
    info "Downloading ${TARBALL_URL}"
    fetch "$TARBALL_URL" "$tarball" || err "download failed"
    expected="$(fetch_stdout "$SHA_URL" | awk '{print $1}')"
    [ -n "$expected" ] || err "could not fetch checksum"
    sha256_check "$tarball" "$expected" || err "checksum verification failed"
    info "Checksum verified"

    # Extract into the workdir; the tarball contains a single top-level dir.
    tar -xzf "$tarball" -C "$WORKDIR"
    extracted="$(find "$WORKDIR" -maxdepth 1 -type d -name 'audiobookshelf-*' | head -n1)"
    [ -n "$extracted" ] || err "unexpected archive layout"

    mkdir -p "$BIN_DIR" "$(dirname "$INSTALL_DIR")" "${ABS_HOME}/config" "${ABS_HOME}/metadata"
    rm -rf "$INSTALL_DIR"
    mv "$extracted" "$INSTALL_DIR"

    # Launcher on PATH. Calls the bundle's start.sh by absolute path (no symlink
    # in the chain, so start.sh resolves its own dir correctly on every release)
    # and pins data to ABS_HOME regardless of the bundled start.sh's defaults.
    cat > "${BIN_DIR}/audiobookshelf" << EOF
#!/bin/sh
: "\${CONFIG_PATH:=${ABS_HOME}/config}"
: "\${METADATA_PATH:=${ABS_HOME}/metadata}"
export CONFIG_PATH METADATA_PATH
exec "${INSTALL_DIR}/start.sh" "\$@"
EOF
    chmod +x "${BIN_DIR}/audiobookshelf"
    info "Installed to ${INSTALL_DIR}"
}

finish() {
    case ":${PATH}:" in
        *":${BIN_DIR}:"*) cmd="audiobookshelf" ;;
        *)
            warn "${BIN_DIR} is not on your PATH. Add it, e.g.:"
            info "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.profile && . ~/.profile"
            cmd="${BIN_DIR}/audiobookshelf"
            ;;
    esac
    info ""
    info "Done. Start audiobookshelf with:"
    info "  ${cmd}"
    info "Then open http://localhost:3333"
    info ""
    info "Uninstall: rm -rf \"${INSTALL_DIR}\" \"${BIN_DIR}/audiobookshelf\"  (data: ${ABS_HOME})"
}

main() {
    info "audiobookshelf-binary installer"
    require_tools

    TARGET="$(detect_target || true)"
    [ -n "$TARGET" ] || err "unsupported platform: $(uname -s) $(uname -m)"
    if ! target_supported "$TARGET"; then
        err "no binary available yet for ${TARGET}. See ${REPO} releases for supported platforms."
    fi
    info "Detected platform: ${TARGET}"

    check_ffmpeg
    resolve_release
    info "Latest release: ${RESOLVED_TAG}"

    info ""
    info "  Version:   ${RESOLVED_TAG}"
    info "  Target:    ${TARGET}"
    info "  Install:   ${INSTALL_DIR}"
    info "  Command:   ${BIN_DIR}/audiobookshelf"
    info "  Data:      ${ABS_HOME}"
    info ""
    confirm
    do_install
    finish
}

main
