# Compatibility changes

## Upstream v2.37.2 build alignment

- The build and release image moves from Debian 11 Bullseye to Debian 13 Trixie. The Debian 13 bundle is smoke-tested on Debian 12 for compatibility, while Bullseye and Ubuntu 20.04 are no longer supported.
- The build and packaged runtime move from Node 20 to Node 24, matching upstream's current build line. The build runtime is pinned to security release 24.22.1.
- `NODE_VERSION` now accepts a full release (for example, `24.22.1`), rather than a major version.
- Upstream tags must provide `build:server` and its compiled `dist-server/index.js` entrypoint.
- The launcher now checks both ffmpeg and ffprobe, exports their paths, and defaults `SKIP_BINARIES_CHECK=1` to use the installed tools without upstream downloads. Explicit tool paths remain trusted, but must be executable. Set `SKIP_BINARIES_CHECK=0` to restore upstream's binary manager.
- The packager moves to `@yao-pkg/pkg` 6.24.0 so the embedded Node runtime also receives the 24.22.1 security update.
