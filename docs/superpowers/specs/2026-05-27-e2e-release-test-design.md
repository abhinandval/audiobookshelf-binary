# E2E release test — design

**Date:** 2026-05-27
**Status:** Approved (pending spec review)

## Goal

Before a built binary is attached to a GitHub Release, prove it actually works for a real user: the web UI loads, a new account can be created, and that account can sign in. Keep screenshots of each step for validation.

Deliberately minimal — this is a "does the binary boot and serve a working app" gate, not a full app test suite (audiobookshelf's own suite covers app behaviour).

## Scope

In scope:

- Headless Chromium, arm64, driven by Playwright
- Three steps: page loads → create root user (audiobookshelf first-run init) → sign in with those credentials
- A screenshot saved at each step, uploaded as a workflow artifact (on pass and fail)
- Runs as a **pre-publish gate** inside the existing `build-linux-arm64.yml` job

Out of scope (YAGNI):

- Multi-user / admin "add user" flows
- Library scanning, upload, playback, metadata
- Cross-browser (Firefox/WebKit)
- Visual regression / pixel diffing
- Other target platforms (this PoC is linux-arm64 only)

## Background: audiobookshelf first-run flow

The login page (`client/pages/login.vue`) drives both first-run and login:

- On load it queries server status. With no root user it sets `showInitScreen = true` and renders **"Initial Server Setup → Create Root User"**: a form with Username (prefilled `root`), Password, Confirm Password, and disabled Config/Metadata path fields. Submit issues `POST /init`.
- Once a root user exists it renders the normal login form: `input[name="username"]`, `input[name="password"]`, submit button. On success the app redirects into the library/config shell.

Implication: "create a new user account" = create the root user via the init screen; "sign in" = authenticate via the login form.

## Architecture

The test runs in the existing build job on the `ubuntu-24.04-arm` runner, so Chromium and the binary both execute natively on arm64 — a true end-to-end check on the target architecture.

```
build job (build-linux-arm64.yml)
  build (bullseye container)
    -> smoke test (existing: boots binary 15s, greps "Running in production")
    -> E2E test (NEW)
    -> upload screenshots + report  (if: always())
    -> attach to release            (skipped if E2E failed)
```

Step ordering makes E2E a gate: a failing test fails the job, and the release-attach step (which has no `always()`) is skipped, so a broken binary never ships.

### How Playwright launches the binary

Playwright's `webServer` config owns the server lifecycle: it runs the extracted `start.sh`, waits for `http://localhost:3333` to answer, runs the test, and tears the server down afterwards. This avoids manual background-process + poll + kill logic in the workflow YAML.

A fresh, empty `CONFIG_PATH` and `METADATA_PATH` (temp dirs) are passed so every run is a clean first-run that shows the init screen.

## Components

| File                                      | Responsibility                                                                                                                                                                              | Depends on                                                 |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| `playwright.config.ts`                    | Chromium headless project; `webServer` launches `$ABS_BUNDLE_DIR/start.sh` with fresh `CONFIG_PATH`/`METADATA_PATH` on port 3333; screenshot + trace on failure; output dir for screenshots | `ABS_BUNDLE_DIR` env, extracted bundle                     |
| `tests/e2e/account.spec.ts`               | The three-step flow + assertions + named screenshots                                                                                                                                        | `playwright.config.ts`, running server                     |
| `package.json`                            | adds `@playwright/test` devDependency                                                                                                                                                       | npm / node (from mise)                                     |
| `.github/workflows/build-linux-arm64.yml` | new E2E step + screenshot-upload step                                                                                                                                                       | mise-action, the extracted bundle from the smoke-test step |

## Test flow (`account.spec.ts`)

1. `goto /` → assert "Initial Server Setup" heading visible → screenshot `01-init.png`.
2. Fill Username `e2e-admin`, Password (a fixed test value), Confirm Password (same) → submit → wait for init to succeed (login form appears or app shell loads) → screenshot `02-created.png`.
3. Clear cookies and reload `/` to force an unauthenticated state → fill `input[name="username"]` + `input[name="password"]` with the same credentials → submit → assert the app is logged in (URL leaves `/login` and an authenticated-shell element is visible) → screenshot `03-logged-in.png`.

Clearing cookies before step 3 guarantees the sign-in path is exercised even if `/init` establishes a session.

### Selector strategy

Prefer stable hooks: `input[name="username"]` / `input[name="password"]` for login; heading text and `autocomplete` attributes (`autocomplete="username"`, `autocomplete="new-password"`) plus label proximity for the init form. Exact selectors are finalised against a live instance during implementation. Reasonable auto-waiting (Playwright default) rather than fixed sleeps.

## Workflow additions

After the smoke-test step, before release-attach:

1. `jdx/mise-action@v2` — provides node from `.mise.toml`.
2. `npm ci` — installs `@playwright/test`.
3. `npx playwright install --with-deps chromium` — Chromium + system libs (arm64).
4. Run `npx playwright test` with `ABS_BUNDLE_DIR` pointing at the extracted `smoke/audiobookshelf-<version>-linux-arm64/` dir (created by the existing smoke step). ffmpeg is already installed by the smoke step.
5. Upload step (`if: always()`): screenshots dir + Playwright HTML report as an artifact named `e2e-screenshots-<version>-linux-arm64`.

The release-attach step keeps its `if: inputs.publish_release != ''` condition (implicitly also requires prior steps to succeed), so it is skipped when E2E fails.

## Error handling

- Server fails to start → Playwright `webServer` times out waiting for the URL → test run fails → job fails → no publish.
- Any assertion/selector failure → Playwright captures screenshot + trace → uploaded via the `always()` step for diagnosis.
- The screenshot-upload step runs regardless of test outcome so failures are always inspectable.

## Testing the test

Validated by dispatching `build-linux-arm64.yml` (without `publish_release`) and confirming: the E2E step passes, three screenshots upload as an artifact, and the run is green. A deliberately-wrong credential locally confirms the sign-in assertion actually fails when it should.

## Cost

Adds roughly 1–2 minutes per build (Chromium download/install + browser run). Acceptable for a release gate.
