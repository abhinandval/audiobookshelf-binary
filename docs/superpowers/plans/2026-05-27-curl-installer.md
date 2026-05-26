# curl | sh Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A one-line `curl | sh` installer that detects the platform, gates on ffmpeg ≥ 5.1 before any download, verifies the release by checksum, and installs the binary to `~/.local/share/audiobookshelf/` with a `~/.local/bin/audiobookshelf` command and config under `~/.audiobookshelf`.

**Architecture:** A single POSIX-`sh` `install.sh` at the repo root, served via GitHub Pages. It is self-contained (no `jq`), does all mutating work in a `mktemp` dir and only moves into place at the end. `start.sh`'s config/metadata defaults move to `~/.audiobookshelf` so the installed layout and manual use agree. The ffmpeg ≥ 5.1 check exists in both `start.sh` (bash, at launch) and `install.sh` (POSIX sh, pre-download) by design.

**Tech Stack:** POSIX `sh`, `curl`/`wget`, `tar`, `sha256sum`/`shasum`, GitHub Releases API, GitHub Pages, shellcheck/shfmt via `mise run lint`.

**Implements:** `docs/superpowers/specs/2026-05-27-curl-installer-design.md`

---

### Task 1: Move start.sh config/metadata defaults to ~/.audiobookshelf

**Files:**

- Modify: `scripts/start.sh`

- [ ] **Step 1: Replace the CONFIG_PATH/METADATA_PATH block**

Find this block (the comment lines and both exports):

```bash
# Runtime configuration. Defaults keep all data next to the binary so the
# install is self-contained and behaves the same regardless of the directory
# you launch it from. Point CONFIG_PATH/METADATA_PATH elsewhere for a
# persistent location that survives replacing the binary on upgrade.
export PORT="${PORT:-3333}"
export CONFIG_PATH="${CONFIG_PATH:-${HERE}/config}"
export METADATA_PATH="${METADATA_PATH:-${HERE}/metadata}"
```

Replace it with:

```bash
# Runtime configuration. Data lives under ~/.audiobookshelf by default so it
# survives replacing the binary on upgrade. Override ABS_HOME, or the
# individual paths, or pass --config/--metadata. Falls back to next-to-binary
# when HOME is unset.
export PORT="${PORT:-3333}"
ABS_HOME="${ABS_HOME:-${HOME:-$HERE}/.audiobookshelf}"
export CONFIG_PATH="${CONFIG_PATH:-${ABS_HOME}/config}"
export METADATA_PATH="${METADATA_PATH:-${ABS_HOME}/metadata}"
```

- [ ] **Step 2: Verify syntax and lint**

Run: `bash -n scripts/start.sh && mise run lint`
Expected: `syntax ok` (if you echo it) and lint passes — shellcheck, shfmt, actionlint, prettier all clean.

- [ ] **Step 3: Verify the default resolves correctly**

Run:

```bash
HOME=/tmp/abshome bash -c '
  HERE=/opt/abs
  ABS_HOME="${ABS_HOME:-${HOME:-$HERE}/.audiobookshelf}"
  echo "CONFIG=${CONFIG_PATH:-${ABS_HOME}/config}"
  echo "META=${METADATA_PATH:-${ABS_HOME}/metadata}"
'
```

Expected:

```
CONFIG=/tmp/abshome/.audiobookshelf/config
META=/tmp/abshome/.audiobookshelf/metadata
```

- [ ] **Step 4: Commit**

```bash
git add scripts/start.sh
git commit -m "feat: default config/metadata under ~/.audiobookshelf"
```

---

### Task 2: Create install.sh skeleton (args, helpers, traps)

**Files:**

- Create: `install.sh`

- [ ] **Step 1: Write the skeleton**

```sh
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

main() {
  info "audiobookshelf-binary installer"
}

main
```

- [ ] **Step 2: Lint**

Run: `shellcheck -s sh install.sh && shfmt -i 4 -ci -sr -d install.sh`
Expected: no output (clean). If `shfmt` reports a diff, run `shfmt -i 4 -ci -sr -w install.sh`.

- [ ] **Step 3: Smoke-run arg parsing**

Run: `sh install.sh --help` then `sh install.sh --yes --version v2.35.0`
Expected: help text for the first; `audiobookshelf-binary installer` for the second; no errors.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: add installer skeleton (args, helpers, cleanup trap)"
```

---

### Task 3: Tool preflight + platform detection and gate

**Files:**

- Modify: `install.sh`

- [ ] **Step 1: Add the helper functions above `main()`**

```sh
have() { command -v "$1" >/dev/null 2>&1; }

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
    printf '%s  %s\n' "$2" "$1" | sha256sum -c - >/dev/null 2>&1
  else
    printf '%s  %s\n' "$2" "$1" | shasum -a 256 -c - >/dev/null 2>&1
  fi
}
```

- [ ] **Step 2: Wire detection into `main()`**

Replace the body of `main()` with:

```sh
main() {
  info "audiobookshelf-binary installer"
  require_tools

  TARGET="$(detect_target || true)"
  [ -n "$TARGET" ] || err "unsupported platform: $(uname -s) $(uname -m)"
  if ! target_supported "$TARGET"; then
    err "no binary available yet for ${TARGET}. See ${REPO} releases for supported platforms."
  fi
  info "Detected platform: ${TARGET}"
}
```

- [ ] **Step 3: Lint**

Run: `shellcheck -s sh install.sh && shfmt -i 4 -ci -sr -d install.sh`
Expected: clean.

- [ ] **Step 4: Verify the unsupported-platform path exits cleanly**

Run: `sh install.sh --yes; echo "exit=$?"`
Expected on a non-linux-arm64 dev machine (e.g. macOS arm64): `error: no binary available yet for macos-arm64 ...` followed by `exit=1` — confirming the gate stops before any download or write.

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat: installer tool preflight and platform gate"
```

---

### Task 4: ffmpeg ≥ 5.1 pre-download gate

**Files:**

- Modify: `install.sh`

- [ ] **Step 1: Add the ffmpeg check helper above `main()`**

```sh
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

  ver="$(ffmpeg -version 2>/dev/null | head -n1 | awk '{print $3}')"
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
```

- [ ] **Step 2: Call it in `main()` right after the platform gate**

Add after the `info "Detected platform: ${TARGET}"` line:

```sh
  check_ffmpeg
```

- [ ] **Step 3: Lint**

Run: `shellcheck -s sh install.sh && shfmt -i 4 -ci -sr -d install.sh`
Expected: clean.

- [ ] **Step 4: Verify parsing with a stubbed ffmpeg**

```bash
mkdir -p /tmp/ffstub
printf '#!/bin/sh\necho "ffmpeg version 4.4.2-0ubuntu Copyright"\n' > /tmp/ffstub/ffmpeg
chmod +x /tmp/ffstub/ffmpeg
PATH="/tmp/ffstub:$PATH" sh install.sh --yes 2>&1 | grep -i "too old" && echo "REJECTED-OLD as expected"
printf '#!/bin/sh\necho "ffmpeg version 6.1.1 Copyright"\n' > /tmp/ffstub/ffmpeg
PATH="/tmp/ffstub:$PATH" sh install.sh --yes 2>&1 | grep -i "Found ffmpeg 6.1" && echo "ACCEPTED-NEW as expected"
```

Expected: first prints `REJECTED-OLD as expected`; second prints `Found ffmpeg 6.1` then `ACCEPTED-NEW as expected`. (On a non-linux-arm64 host the platform gate fires first; run these steps on a linux-arm64 host, or temporarily add your host's target to `target_supported` for local testing and revert.)

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat: installer ffmpeg >=5.1 pre-download gate (mirrors start.sh)"
```

---

### Task 5: Resolve latest release and asset URLs (no jq)

**Files:**

- Modify: `install.sh`

- [ ] **Step 1: Add download + resolve helpers above `main()`**

```sh
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
```

- [ ] **Step 2: Call it in `main()` after `check_ffmpeg`**

```sh
  resolve_release
  info "Latest release: ${RESOLVED_TAG}"
```

- [ ] **Step 3: Lint**

Run: `shellcheck -s sh install.sh && shfmt -i 4 -ci -sr -d install.sh`
Expected: clean.

- [ ] **Step 4: Verify tag parsing against the live API**

Run: `fetch_via() { curl -fsSL "$1"; }; curl -fsSL https://api.github.com/repos/abhinandval/audiobookshelf-binary/releases/latest | sed -n 's/.*"tag_name"[ ]*:[ ]*"\([^"]*\)".*/\1/p' | head -n1`
Expected: prints `v2.35.0` (or the current latest tag).

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat: installer resolves latest release and asset URLs without jq"
```

---

### Task 6: Confirmation prompt, download, verify, install

**Files:**

- Modify: `install.sh`

- [ ] **Step 1: Add the confirm + install helpers above `main()`**

```sh
confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  if [ -r /dev/tty ]; then
    printf 'Proceed with installation? [y/N] '
    read -r reply </dev/tty
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
  ln -sf "${INSTALL_DIR}/start.sh" "${BIN_DIR}/audiobookshelf"
  info "Installed to ${INSTALL_DIR}"
}
```

- [ ] **Step 2: Extend `main()` to confirm and install**

After `info "Latest release: ${RESOLVED_TAG}"` add:

```sh
  info ""
  info "  Version:   ${RESOLVED_TAG}"
  info "  Target:    ${TARGET}"
  info "  Install:   ${INSTALL_DIR}"
  info "  Command:   ${BIN_DIR}/audiobookshelf"
  info "  Data:      ${ABS_HOME}"
  info ""
  confirm
  do_install
```

- [ ] **Step 3: Lint**

Run: `shellcheck -s sh install.sh && shfmt -i 4 -ci -sr -d install.sh`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: installer confirm prompt, checksum-verified download and install"
```

---

### Task 7: Post-install PATH check and run/uninstall guidance

**Files:**

- Modify: `install.sh`

- [ ] **Step 1: Add the finish helper above `main()`**

```sh
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
```

- [ ] **Step 2: Call `finish` at the end of `main()`**

```sh
  finish
```

- [ ] **Step 3: Lint**

Run: `shellcheck -s sh install.sh && shfmt -i 4 -ci -sr -d install.sh`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: installer PATH check and run/uninstall guidance"
```

---

### Task 8: Wire shellcheck for install.sh into the lint task

**Files:**

- Modify: `.mise.toml`

- [ ] **Step 1: Update the lint task's shell commands**

Find the `[tasks.lint]` `run` array's shell lines:

```toml
  "shellcheck scripts/*.sh",
  "shfmt -i 4 -ci -sr -d scripts/*.sh",
```

Replace with (note `install.sh` is POSIX sh, so it's checked with `-s sh`):

```toml
  "shellcheck scripts/*.sh",
  "shellcheck -s sh install.sh",
  "shfmt -i 4 -ci -sr -d scripts/*.sh install.sh",
```

Also update the `[tasks.fmt]` `run` shfmt line from `scripts/*.sh` to `scripts/*.sh install.sh`.

- [ ] **Step 2: Run the full lint task**

Run: `mise run lint`
Expected: all four checks pass (shellcheck on scripts, shellcheck on install.sh, shfmt, actionlint, prettier).

- [ ] **Step 3: Commit**

```bash
git add .mise.toml
git commit -m "ci: lint install.sh (shellcheck -s sh + shfmt) in the lint task"
```

---

### Task 9: Enable GitHub Pages hosting

**Files:**

- Create: `.nojekyll`

- [ ] **Step 1: Add `.nojekyll` so Pages serves files verbatim**

Create an empty file `/.nojekyll` (no content needed).

- [ ] **Step 2: Commit**

```bash
git add .nojekyll
git commit -m "ci: add .nojekyll so Pages serves install.sh verbatim"
```

- [ ] **Step 3: Enable Pages from the main branch root (after this branch merges)**

Run (records intent; run once the PR is merged to `main`):

```bash
gh api -X POST repos/abhinandval/audiobookshelf-binary/pages \
  -f "source[branch]=main" -f "source[path]=/" 2>&1 || \
  gh api -X PUT repos/abhinandval/audiobookshelf-binary/pages \
  -f "source[branch]=main" -f "source[path]=/"
```

Expected: Pages enabled; after the build, `https://abhinandval.github.io/audiobookshelf-binary/install.sh` returns the script. Verify:

```bash
curl -fsSI https://abhinandval.github.io/audiobookshelf-binary/install.sh | head -1
```

Expected: `HTTP/2 200`.

---

### Task 10: Document the installer in the README

**Files:**

- Modify: `README.md`

- [ ] **Step 1: Add a "Quick install" section before "Install (linux-arm64)"**

Insert:

````markdown
## Quick install

```sh
curl -sS https://abhinandval.github.io/audiobookshelf-binary/install.sh | sh
```

This detects your platform, checks ffmpeg (>= 5.1), verifies the download checksum, installs to `~/.local/share/audiobookshelf/`, adds an `audiobookshelf` command in `~/.local/bin`, and stores data in `~/.audiobookshelf`. Re-running upgrades in place; your data is untouched.

Prefer to read before running? Inspect the script first:

```sh
curl -sS https://abhinandval.github.io/audiobookshelf-binary/install.sh | less
```

Non-interactive (e.g. scripts): add `| sh -s -- --yes`.

Uninstall:

```sh
rm -rf ~/.local/share/audiobookshelf ~/.local/bin/audiobookshelf
# data (optional): rm -rf ~/.audiobookshelf
```
````

- [ ] **Step 2: Rename the existing "Install (linux-arm64)" heading to "Manual install (linux-arm64)"**

Change `## Install (linux-arm64)` to `## Manual install (linux-arm64)`.

- [ ] **Step 3: Format and lint**

Run: `mise exec -- npx prettier --write README.md && mise run lint`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document the curl | sh installer and uninstall"
```

---

### Task 11: End-to-end local validation on a linux-arm64 host

This validates the real install path. Run on a linux-arm64 host (or the Dockerized arm64 flow); it cannot fully run on macOS because no macOS asset exists yet.

**Files:** none (validation)

- [ ] **Step 1: Run the installer non-interactively from the branch copy**

```bash
sh ./install.sh --yes
```

Expected: platform detected `linux-arm64`; `Found ffmpeg <ver>`; release resolved; checksum verified; `Installed to ~/.local/share/audiobookshelf`; finish guidance printed.

- [ ] **Step 2: Confirm the command and layout**

```bash
ls -l ~/.local/bin/audiobookshelf
ls ~/.local/share/audiobookshelf
ls -d ~/.audiobookshelf/config ~/.audiobookshelf/metadata
```

Expected: symlink → `…/start.sh`; bundle files present; both data dirs exist.

- [ ] **Step 3: Confirm it boots and writes to ~/.audiobookshelf**

```bash
timeout 15 ~/.local/bin/audiobookshelf >/tmp/abs.log 2>&1 || true
grep -i "Running in production" /tmp/abs.log
ls ~/.audiobookshelf/config
```

Expected: log shows production mode; config dir is now populated (e.g. a database file) — proving the default path change works end to end.

- [ ] **Step 4: Confirm re-run upgrades in place without touching data**

```bash
touch ~/.audiobookshelf/config/_keepme
sh ./install.sh --yes
test -f ~/.audiobookshelf/config/_keepme && echo "DATA PRESERVED"
```

Expected: `DATA PRESERVED`.

- [ ] **Step 5: Record the result (no commit needed)**

Note pass/fail in the PR description.

---

### Task 12: Open the PR

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feat/curl-installer
```

(The `pre-push` hook runs `mise run lint` first.)

- [ ] **Step 2: Open the PR**

```bash
gh pr create --title "feat: curl | sh installer" \
  --body "Implements docs/superpowers/specs/2026-05-27-curl-installer-design.md. POSIX-sh installer with platform + ffmpeg(>=5.1) pre-download gates, checksum-verified download, XDG layout + PATH command, ~/.audiobookshelf data dir. start.sh defaults moved accordingly. Pages hosting + .nojekyll. README documented."
```

Expected: `lint` and `validate` checks pass.
