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
