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
