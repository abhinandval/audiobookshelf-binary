# Contributing

Thanks for your interest. This project packages [audiobookshelf](https://github.com/advplyr/audiobookshelf) into standalone binaries for bare-metal self-hosting. We don't modify the application itself.

## What kinds of changes are in scope

- New build targets (e.g. `freebsd-amd64`, new OS releases)
- Build-script fixes (glibc compat, packaging bugs, dependency resolution)
- CI improvements (faster runs, better caching, more reliable smoke tests)
- Security improvements (signing, provenance, SBOM, pinning)
- Documentation

## What's out of scope

- Patches to the audiobookshelf application — file those at [advplyr/audiobookshelf](https://github.com/advplyr/audiobookshelf).

## Development setup

You need:

- `git`, a recent Bash (4+)
- [`mise`](https://mise.jdx.dev) — provides node + shellcheck + shfmt + actionlint at pinned versions
- Docker if you want to run a build locally (the build runs in a `debian:bullseye-slim` arm64 container).

One-time setup:

```sh
mise trust            # trust .mise.toml in this repo
mise install          # install pinned node, shellcheck, shfmt, actionlint
npm install           # installs prettier + activates the husky git hooks
```

`npm install` runs husky's `prepare` script, which installs a **`pre-push`** hook. From then on, the lint task runs automatically before every push and blocks the push if anything fails.

## Running checks locally

```sh
mise run lint         # everything CI runs: shellcheck, shfmt, actionlint, prettier
mise run fmt          # auto-fix formatting (shfmt -w + prettier --write)
```

CI installs the **same tool versions** (via `.mise.toml`) and runs the same `mise run lint`, so "passes locally" means "passes in CI" — no version drift.

### If the pre-push hook doesn't run

Hooks need `mise` on `PATH`. GUI git clients (VS Code, Tower, GitHub Desktop) often don't load your shell `PATH`. The hook adds `~/.local/bin` and `~/.local/share/mise/shims` itself, but if `mise` lives elsewhere, ensure it's on `PATH` for your git client. Verify the hook is active with `git config --get core.hooksPath` (should print `.husky/_`).

## Testing a build locally (linux-arm64)

On an arm64 host (Apple Silicon Mac with Docker works):

```sh
docker run --rm \
  --platform linux/arm64 \
  -e ABS_VERSION=v2.35.0 \
  -e WORK_DIR=/work/build-cache \
  -e OUT_DIR=/work/dist \
  -v "$PWD:/work" -w /work \
  debian:bullseye-slim \
  bash /work/scripts/build-linux-arm64.sh
```

The resulting tarball lands in `dist/`.

## Commit messages and PR titles

PR titles must follow [Conventional Commits](https://www.conventionalcommits.org/). We squash-merge, so the PR title becomes the commit message on `main`. The `pr-title` CI check enforces this.

Allowed types: `feat`, `fix`, `chore`, `ci`, `docs`, `refactor`, `test`, `build`, `perf`, `revert`.

Examples:

- `feat: add windows-amd64 target`
- `fix: handle missing libnusqlite3 with clear error`
- `ci: cache npm install between runs`

## Pull request flow

1. Fork the repo and create a feature branch.
2. Make your change. Run `pre-commit run --all-files`.
3. Open a PR. Fill in the template.
4. CI runs: `lint`, `pr-title`, and (for build changes) `build-linux-arm64`.
5. A maintainer reviews. Solo-maintainer mode means approvals are gated — please be patient.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).
