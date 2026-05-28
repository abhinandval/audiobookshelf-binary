# `curl | sh` installer — design

**Date:** 2026-05-27
**Status:** Approved (pending spec review)

## Goal

Let a user install the audiobookshelf binary with one command:

```sh
curl -sS https://abhinandval.github.io/audiobookshelf-binary/install.sh | sh
```

The script detects the platform, verifies a matching release exists, confirms with the user, downloads and checksum-verifies the binary, and lays it out in standard locations with a `PATH` command and a persistent config directory.

## Scope

In scope:

- POSIX `sh` installer that runs piped from `curl`.
- OS/arch detection → release-target mapping; graceful exit for unsupported platforms.
- Latest-release resolution via the GitHub API (no `jq` dependency).
- SHA256 verification of the downloaded tarball.
- Install layout: app files in `~/.local/share/audiobookshelf/`, a `~/.local/bin/audiobookshelf` symlink to `start.sh`, config in `~/.audiobookshelf/{config,metadata}`.
- `start.sh` default change so config/metadata live in `~/.audiobookshelf`.
- ffmpeg `>= 5.1` preflight gate that fails before any download, mirroring `start.sh`'s runtime guard.
- Idempotent re-run (in-place upgrade) and an uninstall note.
- Hosting via GitHub Pages.

Out of scope (YAGNI):

- Windows (`curl | sh` is Unix; a future `install.ps1` is separate).
- macOS install path until a macOS target is built (detected and reported as "not available yet").
- System-wide install / root / package managers (apt, brew). User-local only.
- Auto-installing ffmpeg (needs privileges / package manager).
- Service/daemon setup (systemd unit, etc.).

## Platform support at launch

Only `linux-arm64` has a published release today. The installer must:

- Map `Linux` + `aarch64|arm64` → `linux-arm64` → proceed.
- Any other combination (linux-amd64, Darwin, etc.) → print "no binary available yet for `<os>-<arch>`" and exit non-zero, without partial changes.

The target table is data-driven so new targets light up automatically as releases add assets.

## Install layout

```
~/.local/share/audiobookshelf/      # extracted bundle (binary, lib/, start.sh, LICENSE, BUILD_INFO.txt)
~/.local/bin/audiobookshelf         # symlink -> ~/.local/share/audiobookshelf/start.sh
~/.audiobookshelf/config            # database + server config
~/.audiobookshelf/metadata          # covers, cached metadata
```

Rationale: app files follow the XDG `~/.local/share` convention; the symlink gives a real `audiobookshelf` command on `PATH` without the folder/command name clash that `~/.local/bin/audiobookshelf/` would cause. Config lives outside the app dir so upgrades (which replace `~/.local/share/audiobookshelf/`) never touch user data.

## `start.sh` default change

Current defaults point at `${HERE}/config` and `${HERE}/metadata` (next to the binary). Change to a stable per-user location:

```sh
ABS_HOME="${ABS_HOME:-${HOME:-$HERE}/.audiobookshelf}"
export CONFIG_PATH="${CONFIG_PATH:-${ABS_HOME}/config}"
export METADATA_PATH="${METADATA_PATH:-${ABS_HOME}/metadata}"
```

- Defaulting to `~/.audiobookshelf` is upgrade-safe (data survives replacing the binary) and matches the installer layout.
- `${HOME:-$HERE}` fallback keeps it working in environments where `$HOME` is unset (falls back to next-to-binary, the old behaviour).
- Everything stays overridable by pre-set env vars and CLI flags. This reverses the `${HERE}`-relative default introduced earlier; the change is intentional.

## Installer flow

1. **Tool preflight**: ensure `curl` or `wget`, `tar`, `uname`, and a sha256 tool (`sha256sum` or `shasum -a 256`) exist; abort early with a clear message if not.
2. **Detect**: `os=$(uname -s)`, `arch=$(uname -m)`; normalise (`x86_64`→`amd64`, `aarch64`/`arm64`→`arm64`, `Linux`→`linux`, `Darwin`→`macos`).
3. **Map + gate**: look up `<os>-<arch>` in the supported-target list. If absent → message + exit 1.
4. **ffmpeg gate** (fail before any download — see below): unless `--skip-ffmpeg-check` is passed or `FFMPEG_PATH` is set, require ffmpeg `>= 5.1` on `PATH`. Missing or too old → clear message + install guidance + exit 1, with nothing fetched or written.
5. **Resolve release**: GET `https://api.github.com/repos/abhinandval/audiobookshelf-binary/releases/latest`; extract the `browser_download_url` for `audiobookshelf-<tag>-<target>.tar.gz` and its `.sha256` using `grep`/`sed` (no `jq`). A `--version <tag>` flag overrides.
6. **Confirm**: print a summary (version, target, install dir, config dir) and prompt `y/N` read from `/dev/tty`. If no TTY and `--yes` not passed → abort with instructions. `--yes`/`-y` skips the prompt.
7. **Download + verify**: into a `mktemp -d` workspace; fetch tarball + `.sha256`; verify; abort on mismatch.
8. **Install**: create dirs; extract bundle into a temp dir then move into place atomically (replace existing on upgrade); create the `~/.local/bin/audiobookshelf` symlink; `mkdir -p ~/.audiobookshelf/{config,metadata}`.
9. **PATH check**: if `~/.local/bin` is not on `PATH`, print how to add it.
10. **Done**: print the run command (`audiobookshelf` or the absolute path) and an uninstall hint.

### ffmpeg gate (step 4) — mirrors `start.sh`

The same ffmpeg `>= 5.1` requirement that `start.sh` enforces at launch is also checked here in the installer, **before any network fetch or filesystem change**. This is an intentional re-implementation, not accidental duplication, because the two run in different contexts:

- A user who installs **manually** (downloads the tarball) never runs the installer, so `start.sh` must keep its own guard.
- A user who uses the **installer** benefits from failing fast — nothing is downloaded or written if ffmpeg is unsuitable.

Behaviour matches `start.sh`: trust a user-set `FFMPEG_PATH` (skip the check); else parse `ffmpeg -version` and abort on a parseable version `< 5.1`; warn-but-continue on unparseable git-build version strings. Implemented in POSIX `sh` (no `[[ ]]`/`BASH_REMATCH`) using `awk`/`sed` parsing and integer `[ ]` comparisons. A `--skip-ffmpeg-check` flag bypasses the gate for users who will supply ffmpeg afterward.

## Error handling

- Any failed precondition (missing tool, unsupported platform, checksum mismatch, download failure) exits non-zero with a specific message and leaves the system unchanged (work happens in a temp dir; final move is the only mutation).
- `set -eu` at the top; cleanup of the temp dir via `trap` on exit.
- Re-running on an existing install replaces the app dir and refreshes the symlink; config is left intact.

## Security considerations

- HTTPS-only download; SHA256 verification of the tarball is the primary integrity control for pipe-to-shell.
- The script is short and inspectable; README documents downloading and reading it before running, and a checksummed/pinned-version invocation.
- No `sudo`; strictly user-local writes under `$HOME`.

## Hosting

GitHub Pages serves the repository so `install.sh` at the repo root is reachable at `https://abhinandval.github.io/audiobookshelf-binary/install.sh`. A `.nojekyll` file disables Jekyll processing so the script is served verbatim. `install.sh` at the repo root is the single source of truth.

## Testing

- `shellcheck` (POSIX/sh dialect) + `shfmt` clean; wired into the existing `mise run lint`.
- Local dry-run on linux-arm64 via the Dockerized flow or a real arm64 host: pipe the script, confirm it installs, `audiobookshelf` resolves on `PATH`, config lands in `~/.audiobookshelf`, and re-run upgrades in place.
- Unsupported-platform path: run on macOS/amd64 and confirm a clean "not available yet" exit with no filesystem changes.
- `--yes` non-interactive path exercised in a pipe with no TTY.

## Documentation

README gains a "Quick install" section with the one-liner, the manual-download alternative (kept), an uninstall section (`rm -rf ~/.local/share/audiobookshelf ~/.local/bin/audiobookshelf`; optionally `~/.audiobookshelf`), and the inspect-before-run note.
