# audiobookshelf-binary

Community-built standalone binaries of [audiobookshelf](https://github.com/advplyr/audiobookshelf) for bare-metal self-hosting — no Docker required.

> **Unofficial.** Not affiliated with [advplyr/audiobookshelf](https://github.com/advplyr/audiobookshelf). Built from upstream source via GitHub Actions on every release. Source for the build pipeline lives in this repo; binaries are published to the [Releases page](../../releases).

## Why this exists

Audiobookshelf publishes Docker images for `linux/amd64` and `linux/arm64`, but **no standalone binaries** for bare-metal installs. This project fills that gap for users running on Raspberry Pi, low-power ARM boards, or any host where containers add overhead they don't want.

## Supported targets

| OS            | Architecture          | Status  |
| ------------- | --------------------- | ------- |
| Linux (glibc) | arm64                 | Stable  |
| Linux (glibc) | amd64                 | Planned |
| Windows       | amd64                 | Planned |
| Windows       | arm64                 | Planned |
| macOS         | arm64 (Apple Silicon) | Planned |
| macOS         | amd64 (Intel)         | Planned |

Minimum glibc: **2.31** (Debian Bullseye / Raspberry Pi OS Bullseye / Ubuntu 20.04 and newer).

Linux-arm64 binaries are **rebuilt automatically** when a new upstream audiobookshelf release appears — a daily check (`.github/workflows/watch-upstream.yml`) dispatches the build and only publishes if the smoke and E2E gates pass.

## Prerequisites

- **ffmpeg (>= 5.1)** must be installed and on `PATH`. The binary does not bundle it. `start.sh` checks the version and refuses to start on anything older, since audiobookshelf would otherwise try to download its own ffmpeg (which can fail on Android / uncommon arm targets).
  - Debian/Ubuntu/Raspberry Pi OS: `sudo apt install ffmpeg`
  - Fedora: `sudo dnf install ffmpeg`
  - macOS: `brew install ffmpeg`
  - Windows: `winget install Gyan.FFmpeg`
  - If your distro ships an older ffmpeg, install a newer build and run with `FFMPEG_PATH=/path/to/ffmpeg FFPROBE_PATH=/path/to/ffprobe SKIP_BINARIES_CHECK=1 ./start.sh`.

## Quick install

```sh
curl -sS https://abhinandval.github.io/audiobookshelf-binary/install.sh | sh
```

This detects your platform, checks ffmpeg (>= 5.1), verifies the download checksum, installs to `~/.local/share/audiobookshelf/`, adds an `audiobookshelf` command in `~/.local/bin`, and stores data in `~/.audiobookshelf`. Re-running upgrades in place; your data is untouched.

User settings live in **`~/.audiobookshelf/.env`** (created with a commented template on first install). Edit it to override `PORT`, `HOST`, `CONFIG_PATH`, etc. — it survives upgrades.

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

## Manual install (linux-arm64)

```sh
# Replace VERSION with the latest from Releases
VERSION=v2.35.0
curl -LO "https://github.com/abhinandval/audiobookshelf-binary/releases/download/${VERSION}/audiobookshelf-${VERSION}-linux-arm64.tar.gz"
tar -xzf "audiobookshelf-${VERSION}-linux-arm64.tar.gz"
cd "audiobookshelf-${VERSION}-linux-arm64"

# The binary tarball doesn't bundle the launcher (it ships with the installer
# tooling so launcher fixes don't need a binary rebuild). Fetch it once:
curl -LO https://abhinandval.github.io/audiobookshelf-binary/scripts/start.sh
chmod +x start.sh

./start.sh
```

Always launch via `./start.sh` (not the bare `audiobookshelf` binary) — the launcher wires up the bundled SQLite extension, checks for ffmpeg, and applies the defaults below.

### Defaults and overrides

| Variable        | Default                  | Notes                      |
| --------------- | ------------------------ | -------------------------- |
| `PORT`          | `3333`                   | HTTP port                  |
| `CONFIG_PATH`   | `<install dir>/config`   | Database and server config |
| `METADATA_PATH` | `<install dir>/metadata` | Covers, cached metadata    |

`HOST` is left unset so the server binds all interfaces dual-stack (IPv4 + IPv6). Set `HOST=127.0.0.1` to expose only locally (e.g. behind a reverse proxy).

By default all data lives next to the binary, so the install is self-contained. To keep your data when upgrading (replacing the binary), point these at a stable location:

```sh
CONFIG_PATH=~/.audiobookshelf/config METADATA_PATH=~/.audiobookshelf/metadata PORT=8000 ./start.sh
```

CLI flags also work and take precedence: `./start.sh --port 8000 --config ~/abs/config --metadata ~/abs/metadata`.

## Verifying downloads

Each release ships a `SHA256SUMS` file and (planned) cosign signatures.

```sh
sha256sum -c SHA256SUMS
```

## How builds work

A GitHub Actions workflow polls upstream releases, then for each new tag:

1. Checks out audiobookshelf source at the tag
2. Builds the Nuxt client (`client/dist`)
3. Installs server deps and downloads platform-appropriate `libnusqlite3` from [mikiher/nunicode-sqlite](https://github.com/mikiher/nunicode-sqlite)
4. Bundles into a single executable using [`@yao-pkg/pkg`](https://github.com/yao-pkg/pkg) (community fork of vercel/pkg)
5. Archives binary + libs + LICENSE + README, generates checksums, uploads as a release asset

Build logs are public on the [Actions tab](../../actions). Source pinned to upstream tags by SHA.

## License

The build pipeline (this repo) is licensed under **GPL-3.0** to match upstream. Released binaries contain audiobookshelf source code and are likewise GPL-3.0. See [LICENSE](LICENSE) and upstream [audiobookshelf/LICENSE](https://github.com/advplyr/audiobookshelf/blob/master/LICENSE).

## Reporting issues

- **App bugs** (UI, library scanning, metadata, etc.): file upstream at [advplyr/audiobookshelf/issues](https://github.com/advplyr/audiobookshelf/issues)
- **Packaging bugs** (binary won't start, missing files, wrong glibc, etc.): file here
