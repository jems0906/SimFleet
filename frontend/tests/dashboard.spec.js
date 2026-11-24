import { expect, test } from "@playwright/test";

test("renders metrics through the same-origin proxy", async ({ page, baseURL }) => {
  const errors = [];
  const apiOrigins = [];
  const apiPaths = new Set();
  page.on("pageerror", error => errors.push(error.message));
  await page.route("**/api/**", async route => {
    const url = new URL(route.request().url());
    apiOrigins.push(url.origin);
    apiPaths.add(url.pathname);
    const payload = { run_count: 10, window: { start: "2026-11-24", end: "2026-11-25" }, results: [] };
    if (url.pathname.endsWith("/pass-rates")) {
      payload.results = [{ driver_version: "v1", category: "merge", pass_rate: 0.9 }];
    }
    if (url.pathname.endsWith("/regressions")) {
      payload.results = [{ scenario_id: 1, name: "merge-regression", pass_rate_drop: 0.2, z_score: 3 }];
    }
    if (url.pathname.endsWith("/distributions")) {
      payload.results = [{ median: 1.5, p95: 2.5 }];
    }
    await route.fulfill({ json: url.pathname.endsWith("/batches") ? [] : payload });
  });
  await page.goto("/");
  await expect(page.getByText("90.0%", { exact: true })).toBeVisible();
  await expect(page.getByText("merge-regression", { exact: true })).toBeVisible();
  await expect(page.getByText("1.50", { exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Run health" })).toBeVisible();
  expect(apiPaths.size).toBe(7);
  expect(apiOrigins.every(origin => origin === baseURL)).toBe(true);
  expect(errors).toEqual([]);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});

test("keeps the dashboard visible when authentication fails", async ({ page }) => {
  const errors = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.route("**/api/**", route => route.fulfill({ status: 401, json: { detail: "invalid API key" } }));
  await page.goto("/");
  await expect(page.getByRole("alert")).toHaveText("Dashboard data is unavailable. Please try again later.");
  await expect(page.getByRole("heading", { name: "SimFleet", exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Run health" })).toBeVisible();
  expect(errors).toEqual([]);
});