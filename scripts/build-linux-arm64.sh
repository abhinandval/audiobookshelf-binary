#!/usr/bin/env bash
#
# Build the audiobookshelf standalone binary for linux-arm64 (glibc).
#
# Required env vars:
#   ABS_VERSION       - upstream tag to build, e.g. "v2.35.0"
#
# Optional env vars:
#   WORK_DIR          - scratch directory (default: ./build-cache)
#   OUT_DIR           - where the packaged tarball is written (default: ./dist)
#   NODE_VERSION      - Node major used for pkg target (default: 20)
#   NUSQLITE3_VERSION - mikiher/nunicode-sqlite tag (default: v1.2)
#   YAO_PKG_VERSION   - @yao-pkg/pkg npm version (default: 6.19.0)
#
# Designed to run inside `debian:bullseye-slim` on a native arm64 host so the
# resulting binary links against glibc 2.31 (Debian Bullseye / RPi OS Bullseye
# / Ubuntu 20.04+).
#
set -euo pipefail

: "${ABS_VERSION:?ABS_VERSION must be set, e.g. v2.35.0}"
WORK_DIR="${WORK_DIR:-$(pwd)/build-cache}"
OUT_DIR="${OUT_DIR:-$(pwd)/dist}"
NODE_VERSION="${NODE_VERSION:-20}"
NUSQLITE3_VERSION="${NUSQLITE3_VERSION:-v1.2}"
YAO_PKG_VERSION="${YAO_PKG_VERSION:-6.19.0}"

TARGET_TRIPLE="linux-arm64"
ARCHIVE_NAME="audiobookshelf-${ABS_VERSION}-${TARGET_TRIPLE}"
STAGE_DIR="${WORK_DIR}/${ARCHIVE_NAME}"

log() { printf '\n>>> %s\n' "$*"; }

log "Installing build prerequisites"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    ca-certificates curl unzip git jq xz-utils \
    build-essential python3 \
    > /dev/null

log "Installing Node.js ${NODE_VERSION} (arm64)"
NODE_DIST="node-v${NODE_VERSION}.20.0-linux-arm64"
curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}.20.0/${NODE_DIST}.tar.xz" |
    tar -xJ -C /usr/local --strip-components=1
node --version
npm --version

log "Cloning audiobookshelf @ ${ABS_VERSION}"
mkdir -p "${WORK_DIR}"
ABS_SRC="${WORK_DIR}/audiobookshelf"
rm -rf "${ABS_SRC}"
git clone --depth 1 --branch "${ABS_VERSION}" \
    https://github.com/advplyr/audiobookshelf.git "${ABS_SRC}"

log "Building client (Nuxt static)"
cd "${ABS_SRC}/client"
npm ci --no-audit --no-fund
npm run generate

log "Installing server deps (compiles sqlite3 for arm64 if no prebuild)"
cd "${ABS_SRC}"
npm ci --no-audit --no-fund --omit=dev

log "Downloading libnusqlite3 ${NUSQLITE3_VERSION} for ${TARGET_TRIPLE}"
NUSQLITE3_ZIP="${WORK_DIR}/libnusqlite3-${TARGET_TRIPLE}.zip"
NUSQLITE3_DIR="${WORK_DIR}/nusqlite3"
curl -fsSL -o "${NUSQLITE3_ZIP}" \
    "https://github.com/mikiher/nunicode-sqlite/releases/download/${NUSQLITE3_VERSION}/libnusqlite3-${TARGET_TRIPLE}.zip"
rm -rf "${NUSQLITE3_DIR}"
mkdir -p "${NUSQLITE3_DIR}"
unzip -q "${NUSQLITE3_ZIP}" -d "${NUSQLITE3_DIR}"
ls -la "${NUSQLITE3_DIR}"

log "Installing @yao-pkg/pkg ${YAO_PKG_VERSION}"
npm install -g "@yao-pkg/pkg@${YAO_PKG_VERSION}"

log "Packaging binary with pkg (node${NODE_VERSION}-linux-arm64)"
cd "${ABS_SRC}"
mkdir -p dist
pkg \
    --target "node${NODE_VERSION}-linux-arm64" \
    --output dist/audiobookshelf \
    .

log "Staging release archive"
rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}/lib"
cp "${ABS_SRC}/dist/audiobookshelf" "${STAGE_DIR}/audiobookshelf"
cp "${NUSQLITE3_DIR}"/*.so "${STAGE_DIR}/lib/"
cp "${ABS_SRC}/LICENSE" "${STAGE_DIR}/LICENSE.audiobookshelf"
cp "$(dirname "$0")/../README.md" "${STAGE_DIR}/README.md" 2> /dev/null || true
cp "$(dirname "$0")/start.sh" "${STAGE_DIR}/start.sh"
chmod +x "${STAGE_DIR}/audiobookshelf" "${STAGE_DIR}/start.sh"

cat > "${STAGE_DIR}/BUILD_INFO.txt" << EOF
audiobookshelf binary build
---------------------------
Upstream version: ${ABS_VERSION}
Upstream commit:  $(cd "${ABS_SRC}" && git rev-parse HEAD)
Target:           ${TARGET_TRIPLE}
libnusqlite3:     ${NUSQLITE3_VERSION}
Node target:      node${NODE_VERSION}-linux-arm64
Built:            $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

log "Creating tarball + checksum"
mkdir -p "${OUT_DIR}"
TARBALL="${OUT_DIR}/${ARCHIVE_NAME}.tar.gz"
tar -C "${WORK_DIR}" -czf "${TARBALL}" "${ARCHIVE_NAME}"
(cd "${OUT_DIR}" && sha256sum "${ARCHIVE_NAME}.tar.gz" > "${ARCHIVE_NAME}.tar.gz.sha256")

log "Done."
ls -lh "${OUT_DIR}"
