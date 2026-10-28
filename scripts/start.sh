#!/usr/bin/env bash
#
# Launcher for the audiobookshelf binary.
# Sets NUSQLITE3_PATH to the bundled native library and sensible runtime
# defaults, then execs the binary. Every value below can be overridden by
# exporting it before running, or via CLI flags (--port, --config, --metadata).
#
set -euo pipefail

# audiobookshelf requires ffmpeg/ffprobe at this version or newer.
FFMPEG_MIN_MAJOR=5
FFMPEG_MIN_MINOR=1

# Resolve this script's real location, following symlinks. The installer
# symlinks ~/.local/bin/audiobookshelf -> this file, so HERE must point at the
# extracted bundle (not the symlink's dir) or we'd re-exec ourselves.
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    dir="$(cd -P -- "$(dirname -- "$SOURCE")" &> /dev/null && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    case "$SOURCE" in
        /*) ;;
        *) SOURCE="$dir/$SOURCE" ;;
    esac
done
HERE="$(cd -P -- "$(dirname -- "$SOURCE")" &> /dev/null && pwd)"

export NUSQLITE3_DIR="${NUSQLITE3_DIR:-${HERE}/lib}"
export NUSQLITE3_PATH="${NUSQLITE3_PATH:-${HERE}/lib/libnusqlite3.so}"

# Runtime configuration. Data lives under ~/.audiobookshelf by default so it
# survives replacing the binary on upgrade. Override ABS_HOME, or the
# individual paths, or pass --config/--metadata. Falls back to next-to-binary
# when HOME is unset.
ABS_HOME="${ABS_HOME:-${HOME:-$HERE}/.audiobookshelf}"

# Optional user settings file (KEY=value lines: PORT, HOST, CONFIG_PATH, ...).
# Sourced before the defaults below so it wins; lives in the data dir so it
# survives upgrades. set -a exports every assignment to the binary.
if [ -f "${ABS_HOME}/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    . "${ABS_HOME}/.env"
    set +a
fi

export PORT="${PORT:-3333}"
export CONFIG_PATH="${CONFIG_PATH:-${ABS_HOME}/config}"
export METADATA_PATH="${METADATA_PATH:-${ABS_HOME}/metadata}"
# HOST is intentionally not defaulted: leaving it unset lets audiobookshelf
# bind all interfaces dual-stack (IPv4 + IPv6). Export HOST=127.0.0.1 yourself
# to expose only locally (e.g. behind a reverse proxy).

if [ ! -f "${NUSQLITE3_PATH}" ]; then
    echo "warning: libnusqlite3 not found at ${NUSQLITE3_PATH}" >&2
fi

# Upstream's binary manager only accepts its pinned ffmpeg 5.1 series.
# Validate our system tools, then use upstream's external-binaries mode so
# newer distro versions are used without downloading replacements.
configure_media_tool() {
    local tool="$1" env_name="$2" tool_path version major minor
    tool_path="${!env_name:-}"
    if [ -n "$tool_path" ]; then
        # Explicit user-provided paths are trusted, as with FFMPEG_PATH before.
        if [ ! -x "$tool_path" ]; then
            echo "error: ${env_name} is not executable: ${tool_path}" >&2
            exit 1
        fi
    else
        if ! tool_path="$(command -v "$tool")"; then
            echo "error: ${tool} not found on PATH. Install ffmpeg before running audiobookshelf." >&2
            exit 1
        fi
        version="$("$tool_path" -version 2> /dev/null | awk 'NR == 1 { print $3 }')"
        version="${version#[nN]}"
        if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+) ]]; then
            echo "error: cannot parse ${tool} version '${version}'; set ${env_name} explicitly to trust this build." >&2
            exit 1
        fi
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        if ((major < FFMPEG_MIN_MAJOR || (major == FFMPEG_MIN_MAJOR && minor < FFMPEG_MIN_MINOR))); then
            echo "error: ${tool} ${major}.${minor} is too old; audiobookshelf needs >= ${FFMPEG_MIN_MAJOR}.${FFMPEG_MIN_MINOR}." >&2
            exit 1
        fi
    fi
    export "${env_name}=${tool_path}"
}
configure_media_tool ffmpeg FFMPEG_PATH
configure_media_tool ffprobe FFPROBE_PATH
export SKIP_BINARIES_CHECK="${SKIP_BINARIES_CHECK:-1}"

exec "${HERE}/audiobookshelf" "$@"
