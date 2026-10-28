#!/usr/bin/env bash
# Exercise the real launcher with fake media tools and a captured server env.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "${FIXTURE}/bin" "${FIXTURE}/bundle/lib"
cp "${ROOT}/scripts/start.sh" "${FIXTURE}/bundle/start.sh"
touch "${FIXTURE}/bundle/lib/libnusqlite3.so"
cat > "${FIXTURE}/bundle/audiobookshelf" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "${FFMPEG_PATH:-unset}" "${FFPROBE_PATH:-unset}" "${SKIP_BINARIES_CHECK:-unset}"
EOF
chmod +x "${FIXTURE}/bundle/audiobookshelf"
for tool in ffmpeg ffprobe; do
    printf '#!/usr/bin/env bash\necho "%s version 7.1.3"\n' "$tool" > "${FIXTURE}/bin/${tool}"
    chmod +x "${FIXTURE}/bin/${tool}"
done
run_launcher() (
    unset FFMPEG_PATH FFPROBE_PATH SKIP_BINARIES_CHECK CONFIG_PATH METADATA_PATH
    export PATH="${FIXTURE}/bin:${PATH}" ABS_HOME="${FIXTURE}/data"
    bash "${FIXTURE}/bundle/start.sh"
)
expected="$(printf '%s\n' "${FIXTURE}/bin/ffmpeg" "${FIXTURE}/bin/ffprobe" 1)"
actual="$(run_launcher)"
if [ "$actual" != "$expected" ]; then
    printf 'Launcher must pass validated media paths and disable upstream downloads. Got:\n%s\n' "$actual" >&2
    exit 1
fi
printf '#!/usr/bin/env bash\necho "ffprobe version 4.4.2"\n' > "${FIXTURE}/bin/ffprobe"
if run_launcher > "${FIXTURE}/old-probe.log" 2>&1; then
    echo "Launcher accepted an unsupported ffprobe" >&2
    exit 1
fi
grep -q 'ffprobe.*too old' "${FIXTURE}/old-probe.log"
echo "Launcher tests passed"
