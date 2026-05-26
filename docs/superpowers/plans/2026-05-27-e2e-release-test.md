# E2E Release Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a headless-Chromium Playwright test that, before a binary is attached to a release, proves the UI loads, a root user can be created, and that user can sign in — saving a screenshot per step.

**Architecture:** A Playwright project at the repo root. `playwright.config.ts` uses a conditional `webServer` block that launches the extracted bundle's `start.sh` (only when `ABS_BUNDLE_DIR` is set), so locally the test reuses an existing server (e.g. Dockerized audiobookshelf) and in CI it boots the freshly built binary. The single spec drives the audiobookshelf first-run flow. The test is wired into `build-linux-arm64.yml` after the smoke test and before the release-attach step, making it a publish gate. Screenshots upload as an artifact on pass and fail.

**Tech Stack:** Playwright (`@playwright/test`), node (from `.mise.toml`), GitHub Actions (`ubuntu-24.04-arm`), Docker (local dev only, to run audiobookshelf for selector validation).

**Verified audiobookshelf facts (from `client/pages/login.vue`):**

- Visiting `/` while unauthenticated lands on `/login`.
- No root user → "Initial Server Setup → Create Root User" form: username `input[autocomplete="username"]`, two `input[autocomplete="new-password"]` (password, then confirm), submit button labelled `Submit` (`Initializing...` while busy).
- After `/init` succeeds the component shows the **login** form (no app auto-login): `input[name="username"]`, `input[name="password"]`, submit button labelled `Submit` (`Checking...` while busy).
- On login success the app redirects away from `/login`.

---

### Task 1: Add Playwright dependency and config

**Files:**

- Modify: `package.json` (add `@playwright/test` devDependency + a `test:e2e` script)
- Create: `playwright.config.ts`
- Modify: `.gitignore` (ignore Playwright outputs)
- Modify: `.prettierignore` (ignore Playwright outputs)

- [ ] **Step 1: Add the devDependency and script to `package.json`**

Edit the `scripts` and `devDependencies` blocks so they read:

```json
  "scripts": {
    "prepare": "husky",
    "lint": "mise run lint",
    "test:e2e": "playwright test"
  },
  "devDependencies": {
    "@playwright/test": "1.49.1",
    "husky": "^9.1.7",
    "prettier": "3.4.2"
  }
```

- [ ] **Step 2: Install to refresh the lockfile**

Run: `mise exec -- npm install`
Expected: `package-lock.json` updated, `@playwright/test` resolved, exit 0.

- [ ] **Step 3: Create `playwright.config.ts`**

```ts
import { defineConfig, devices } from "@playwright/test";

const bundleDir = process.env.ABS_BUNDLE_DIR;
const PORT = process.env.ABS_PORT ?? "3333";
const baseURL = `http://localhost:${PORT}`;

export default defineConfig({
  testDir: "./tests/e2e",
  outputDir: "./test-results",
  timeout: 90_000,
  expect: { timeout: 20_000 },
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: 0,
  workers: 1,
  reporter: [["list"], ["html", { outputFolder: "playwright-report", open: "never" }]],
  use: {
    baseURL,
    headless: true,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  // Only manage the server when pointed at a built bundle (CI). Locally, leave
  // this off and run audiobookshelf yourself (e.g. Docker) on the same port.
  ...(bundleDir
    ? {
        webServer: {
          command: `bash "${bundleDir}/start.sh"`,
          cwd: bundleDir,
          url: baseURL,
          timeout: 120_000,
          reuseExistingServer: !process.env.CI,
          env: {
            PORT,
            CONFIG_PATH: `${bundleDir}/e2e-config`,
            METADATA_PATH: `${bundleDir}/e2e-metadata`,
          },
        },
      }
    : {}),
});
```

- [ ] **Step 4: Add Playwright outputs to `.gitignore`**

Append:

```
# Playwright
/test-results/
/playwright-report/
/screenshots/
```

- [ ] **Step 5: Add the same outputs to `.prettierignore`**

Append:

```
test-results/
playwright-report/
screenshots/
```

- [ ] **Step 6: Commit**

```bash
git add package.json package-lock.json playwright.config.ts .gitignore .prettierignore
git commit -m "test: add Playwright config for E2E release test"
```

---

### Task 2: Write the E2E spec

**Files:**

- Create: `tests/e2e/account.spec.ts`

- [ ] **Step 1: Write the spec**

```ts
import { test, expect } from "@playwright/test";
import fs from "node:fs";

const SCREENSHOT_DIR = "screenshots";
const CREDS = { username: "e2e-admin", password: "e2e-Passw0rd!" };

test.beforeAll(() => {
  fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
});

test("loads, creates the root user, and signs in", async ({ page }) => {
  // --- Step 1: the UI loads on the first-run init screen ---
  await page.goto("/");
  await expect(page.getByText("Initial Server Setup", { exact: false })).toBeVisible();
  await page.screenshot({
    path: `${SCREENSHOT_DIR}/01-init.png`,
    fullPage: true,
  });

  // --- Step 2: create the root user ---
  await page.locator('input[autocomplete="username"]').fill(CREDS.username);
  const newPw = page.locator('input[autocomplete="new-password"]');
  await newPw.nth(0).fill(CREDS.password); // Password
  await newPw.nth(1).fill(CREDS.password); // Confirm Password
  await page.getByRole("button", { name: /submit|initializing/i }).click();

  // After /init succeeds, audiobookshelf shows the LOGIN form.
  await expect(page.locator('input[name="username"]')).toBeVisible({
    timeout: 30_000,
  });
  await page.screenshot({
    path: `${SCREENSHOT_DIR}/02-created.png`,
    fullPage: true,
  });

  // --- Step 3: sign in with the new credentials ---
  await page.locator('input[name="username"]').fill(CREDS.username);
  await page.locator('input[name="password"]').fill(CREDS.password);
  await page.getByRole("button", { name: /submit|checking/i }).click();

  // Signed in: redirected away from /login and the password field is gone.
  await expect(page).not.toHaveURL(/\/login/, { timeout: 30_000 });
  await expect(page.locator('input[name="password"]')).toBeHidden();
  await page.screenshot({
    path: `${SCREENSHOT_DIR}/03-logged-in.png`,
    fullPage: true,
  });
});
```

- [ ] **Step 2: Format**

Run: `mise exec -- npx prettier --write playwright.config.ts tests/e2e/account.spec.ts`
Expected: both files reported, exit 0.

- [ ] **Step 3: Commit**

```bash
git add tests/e2e/account.spec.ts
git commit -m "test: add account-flow E2E spec"
```

---

### Task 3: Validate locally against a Dockerized audiobookshelf and finalise selectors

This is the TDD loop for an E2E test: run it against a real instance, watch it pass, and fix any selector that doesn't match.

**Files:**

- Modify (if needed): `tests/e2e/account.spec.ts`

- [ ] **Step 1: Start a fresh audiobookshelf locally**

```bash
docker rm -f abs-e2e 2>/dev/null || true
docker run -d --name abs-e2e -p 3333:80 ghcr.io/advplyr/audiobookshelf:latest
```

Wait until `curl -fsS http://localhost:3333 >/dev/null` succeeds (a few seconds).

- [ ] **Step 2: Install the browser**

Run: `mise exec -- npx playwright install chromium`
Expected: Chromium downloaded, exit 0.

- [ ] **Step 3: Run the spec (no `ABS_BUNDLE_DIR`, so it reuses the Docker server)**

Run: `mise exec -- npx playwright test`
Expected: 1 passed. Three files exist: `screenshots/01-init.png`, `02-created.png`, `03-logged-in.png`.

- [ ] **Step 4: If a step fails, inspect and fix the selector**

Open the report: `mise exec -- npx playwright show-report`
Adjust the failing locator in `tests/e2e/account.spec.ts` (e.g. swap `getByRole("button", …)` for a form-scoped locator, or target by label). Re-run Step 3 until green. Reset the instance between full runs:

```bash
docker rm -f abs-e2e && docker run -d --name abs-e2e -p 3333:80 ghcr.io/advplyr/audiobookshelf:latest
```

- [ ] **Step 5: Confirm the assertion really fails on bad input (guards against a no-op test)**

Temporarily change `CREDS.password` in step 3 of the spec to a wrong value for the login fill only, run `npx playwright test`, confirm it FAILS at the "redirected away from /login" assertion, then revert.

- [ ] **Step 6: Tear down and commit any selector fixes**

```bash
docker rm -f abs-e2e
git add tests/e2e/account.spec.ts
git commit -m "test: finalise E2E selectors against live audiobookshelf"
```

(If no changes were needed, skip the commit.)

---

### Task 4: Wire the E2E test into the build workflow as a publish gate

**Files:**

- Modify: `.github/workflows/build-linux-arm64.yml` (add steps after "Smoke test", before "Attach to GitHub Release")

- [ ] **Step 1: Add the E2E steps**

Insert these steps immediately after the existing `Smoke test …` step and before `Generate SLSA build provenance`:

```yaml
- name: Set up node tooling
  uses: jdx/mise-action@v2

- name: Install E2E deps
  run: |
    npm ci
    npx playwright install --with-deps chromium

- name: E2E test (loads, create root, sign in)
  env:
    ABS_VERSION: ${{ steps.resolve.outputs.abs_version }}
  run: |
    set -euo pipefail
    export ABS_BUNDLE_DIR="$GITHUB_WORKSPACE/smoke/audiobookshelf-${ABS_VERSION}-linux-arm64"
    test -x "$ABS_BUNDLE_DIR/start.sh" || { echo "bundle not found at $ABS_BUNDLE_DIR"; exit 1; }
    npx playwright test

- name: Upload E2E screenshots and report
  if: always()
  uses: actions/upload-artifact@v7
  with:
    name: e2e-screenshots-${{ steps.resolve.outputs.abs_version }}-linux-arm64
    path: |
      screenshots/
      playwright-report/
    if-no-files-found: warn
```

- [ ] **Step 2: Lint the workflow**

Run: `mise run lint`
Expected: shellcheck, shfmt, actionlint, prettier all pass.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build-linux-arm64.yml
git commit -m "ci: gate release on E2E test and upload screenshots"
```

---

### Task 5: Validate in CI

**Files:** none (dispatch + observe)

- [ ] **Step 1: Push the branch**

```bash
git push -u origin test/e2e-release-validation
```

The `pre-push` hook runs `mise run lint` first; the push proceeds only if it passes.

- [ ] **Step 2: Open the PR**

```bash
gh pr create --title "test: add pre-publish E2E release test (linux-arm64)" \
  --body "Implements docs/superpowers/specs/2026-05-27-e2e-release-test-design.md. Loads UI, creates root user, signs in; screenshots uploaded as artifact; gates release-attach."
```

Expected: `lint` and `validate` checks pass on the PR.

- [ ] **Step 3: Dispatch the build workflow against this branch (no publish)**

```bash
gh workflow run build-linux-arm64.yml --ref test/e2e-release-validation -f abs_version=v2.35.0
```

- [ ] **Step 4: Watch the run and confirm the E2E step passes**

```bash
gh run watch "$(gh run list --workflow=build-linux-arm64.yml --branch test/e2e-release-validation --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```

Expected: job green; "E2E test" step passes; `e2e-screenshots-v2.35.0-linux-arm64` artifact present.

- [ ] **Step 5: Download and eyeball the screenshots**

```bash
gh run download "$(gh run list --workflow=build-linux-arm64.yml --branch test/e2e-release-validation --limit 1 --json databaseId --jq '.[0].databaseId')" -n e2e-screenshots-v2.35.0-linux-arm64 -D /tmp/e2e-shots
ls /tmp/e2e-shots/screenshots
```

Expected: `01-init.png`, `02-created.png`, `03-logged-in.png` show the init screen, login form, and a logged-in page respectively.

---

### Task 6: Merge

- [ ] **Step 1: Confirm PR checks are green, then merge (admin)**

```bash
gh pr checks --watch
gh pr merge --squash --delete-branch
```

(Admin bypass allows the squash merge without a second reviewer.)
