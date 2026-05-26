#!/usr/bin/env bash
#
# Launcher for the audiobookshelf binary.
# Sets NUSQLITE3_PATH to the bundled native library, then execs the binary.
# Passes through all CLI args and env vars (PORT, CONFIG_PATH, METADATA_PATH, ...).
#
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

export NUSQLITE3_DIR="${NUSQLITE3_DIR:-${HERE}/lib}"
export NUSQLITE3_PATH="${NUSQLITE3_PATH:-${HERE}/lib/libnusqlite3.so}"

if [ ! -f "${NUSQLITE3_PATH}" ]; then
    echo "warning: libnusqlite3 not found at ${NUSQLITE3_PATH}" >&2
fi

if ! command -v ffmpeg > /dev/null 2>&1; then
    echo "error: ffmpeg not found on PATH. Install it before running audiobookshelf." >&2
    echo "  Debian/Ubuntu/Raspberry Pi OS: sudo apt install ffmpeg" >&2
    exit 1
fi

exec "${HERE}/audiobookshelf" "$@"
