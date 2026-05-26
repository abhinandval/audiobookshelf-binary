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

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

export NUSQLITE3_DIR="${NUSQLITE3_DIR:-${HERE}/lib}"
export NUSQLITE3_PATH="${NUSQLITE3_PATH:-${HERE}/lib/libnusqlite3.so}"

# Runtime configuration. Data lives under ~/.audiobookshelf by default so it
# survives replacing the binary on upgrade. Override ABS_HOME, or the
# individual paths, or pass --config/--metadata. Falls back to next-to-binary
# when HOME is unset.
export PORT="${PORT:-3333}"
ABS_HOME="${ABS_HOME:-${HOME:-$HERE}/.audiobookshelf}"
export CONFIG_PATH="${CONFIG_PATH:-${ABS_HOME}/config}"
export METADATA_PATH="${METADATA_PATH:-${ABS_HOME}/metadata}"
# HOST is intentionally not defaulted: leaving it unset lets audiobookshelf
# bind all interfaces dual-stack (IPv4 + IPv6). Export HOST=127.0.0.1 yourself
# to expose only locally (e.g. behind a reverse proxy).

if [ ! -f "${NUSQLITE3_PATH}" ]; then
    echo "warning: libnusqlite3 not found at ${NUSQLITE3_PATH}" >&2
fi

# ffmpeg gate. If the user pinned FFMPEG_PATH we trust it; otherwise require a
# recent enough ffmpeg on PATH so audiobookshelf doesn't silently try to
# download its own (which can fail on Android / uncommon arm targets).
if [ -n "${FFMPEG_PATH:-}" ]; then
    : # user-provided ffmpeg, trusted
elif ! command -v ffmpeg > /dev/null 2>&1; then
    echo "error: ffmpeg not found on PATH. Install it before running audiobookshelf." >&2
    echo "  Debian/Ubuntu/Raspberry Pi OS: sudo apt install ffmpeg" >&2
    exit 1
else
    # First line looks like: "ffmpeg version 6.1.1 Copyright ..." (or n6.0, 4.4.2-..., N-12345-g...)
    ffver="$(ffmpeg -version 2> /dev/null | head -n1 | awk '{print $3}')"
    ffver="${ffver#[nN]}"
    if [[ "$ffver" =~ ^([0-9]+)\.([0-9]+) ]]; then
        ffmajor="${BASH_REMATCH[1]}"
        ffminor="${BASH_REMATCH[2]}"
        if ((ffmajor < FFMPEG_MIN_MAJOR || (ffmajor == FFMPEG_MIN_MAJOR && ffminor < FFMPEG_MIN_MINOR))); then
            echo "error: ffmpeg ${ffmajor}.${ffminor} is too old; audiobookshelf needs >= ${FFMPEG_MIN_MAJOR}.${FFMPEG_MIN_MINOR}." >&2
            echo "  Upgrade ffmpeg, or point FFMPEG_PATH and FFPROBE_PATH at a newer build and set SKIP_BINARIES_CHECK=1." >&2
            exit 1
        fi
    else
        echo "warning: could not parse ffmpeg version ('${ffver}'); assuming it is recent enough." >&2
    fi
fi

exec "${HERE}/audiobookshelf" "$@"
