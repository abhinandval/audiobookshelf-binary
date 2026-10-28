#!/usr/bin/env bash
# Verify a built bundle using isolated data directories and real HTTP requests.
set -euo pipefail

: "${1:?Usage: smoke-bundle.sh BUNDLE_DIR}"
BUNDLE_DIR="$(cd -- "$1" && pwd)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SMOKE_DIR="$(mktemp -d)"
SERVER_PID=""

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2> /dev/null || true
        wait "$SERVER_PID" 2> /dev/null || true
    fi
    cat "${SMOKE_DIR}/server.log" 2> /dev/null || true
    rm -rf "$SMOKE_DIR"
}
trap cleanup EXIT

cp "${SCRIPT_DIR}/start.sh" "${BUNDLE_DIR}/start.sh"
PORT="${ABS_PORT:-3333}"
ABS_HOME="$SMOKE_DIR" CONFIG_PATH="${SMOKE_DIR}/config" \
    METADATA_PATH="${SMOKE_DIR}/metadata" HOST=127.0.0.1 PORT="$PORT" \
    bash "${BUNDLE_DIR}/start.sh" > "${SMOKE_DIR}/server.log" 2>&1 &
SERVER_PID=$!

ready=0
for ((attempt = 0; attempt < 60; attempt++)); do
    if ! kill -0 "$SERVER_PID" 2> /dev/null; then
        echo "Server exited before becoming ready" >&2
        exit 1
    fi
    if curl --fail --silent --show-error --max-time 2 \
        "http://127.0.0.1:${PORT}/ping" > "${SMOKE_DIR}/ping.json" 2> /dev/null; then
        ready=1
        break
    fi
    sleep 1
done
if [ "$ready" != 1 ]; then
    echo "Server did not become ready within 60 attempts" >&2
    exit 1
fi
grep -qi "Running in production" "${SMOKE_DIR}/server.log"
grep -Fq "Successfully loaded extension ${BUNDLE_DIR}/lib/libnusqlite3.so" "${SMOKE_DIR}/server.log"
if grep -q 'Installing binaries:' "${SMOKE_DIR}/server.log"; then
    echo "Server downloaded dependencies instead of using the bundle and system tools" >&2
    exit 1
fi
curl --fail --silent --show-error --max-time 10 \
    "http://127.0.0.1:${PORT}/" > "${SMOKE_DIR}/index.html"
grep -qi '<html' "${SMOKE_DIR}/index.html"
echo "Smoke test passed: production startup, bundled SQLite, /ping, and HTML page"
