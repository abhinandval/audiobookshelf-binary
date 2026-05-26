#!/usr/bin/env bash
#
# Launcher for the audiobookshelf binary.
# Sets NUSQLITE3_PATH to the bundled native library and sensible runtime
# defaults, then execs the binary. Every value below can be overridden by
# exporting it before running, or via CLI flags (--port, --config, --metadata).
#
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

export NUSQLITE3_DIR="${NUSQLITE3_DIR:-${HERE}/lib}"
export NUSQLITE3_PATH="${NUSQLITE3_PATH:-${HERE}/lib/libnusqlite3.so}"

# Runtime configuration. Defaults keep all data next to the binary so the
# install is self-contained and behaves the same regardless of the directory
# you launch it from. Point CONFIG_PATH/METADATA_PATH elsewhere for a
# persistent location that survives replacing the binary on upgrade.
export PORT="${PORT:-3333}"
export CONFIG_PATH="${CONFIG_PATH:-${HERE}/config}"
export METADATA_PATH="${METADATA_PATH:-${HERE}/metadata}"

if [ ! -f "${NUSQLITE3_PATH}" ]; then
    echo "warning: libnusqlite3 not found at ${NUSQLITE3_PATH}" >&2
fi

if ! command -v ffmpeg > /dev/null 2>&1; then
    echo "error: ffmpeg not found on PATH. Install it before running audiobookshelf." >&2
    echo "  Debian/Ubuntu/Raspberry Pi OS: sudo apt install ffmpeg" >&2
    exit 1
fi

exec "${HERE}/audiobookshelf" "$@"
