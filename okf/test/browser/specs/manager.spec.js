import { test as base, expect } from "../helpers.js";
import { HUB_PORT } from "../paths.js";

// The hub's /b/ bundles manager. It carries no script at all, so what a
// browser adds over the integration test is the half a string assertion cannot
// reach: that the verdict edge is actually painted, that the columns line up,
// and that the row folds rather than overflows on a phone.
//
// Only the hub has this page — a standalone server redirects nothing to it and
// `okf render` bakes one bundle with no notion of a set — so it is reached by
// URL, like palette-hub.spec.js, rather than through a project's baseURL.
const MANAGER = `http://127.0.0.1:${HUB_PORT}/b/`;

const test = base.extend({
  mgr: async ({ page }, use) => {
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e)));
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    await page.goto(MANAGER);
    await use(page);
    if (errors.length) throw new Error(`page reported ${errors.length} console/page error(s):\n  ${errors.join("\n  ")}`);
  },
});

const edgeColor = (page, index) =>
  page.evaluate((i) => getComputedStyle(document.querySelectorAll(".row")[i], "::before").backgroundColor, index);

test.describe("bundles manager", () => {
  test("one row per hosted bundle, each with its ref, count and verdict", async ({ mgr }) => {
    await expect(mgr.locator(".row")).toHaveCount(2);
    // The ref *is* the name now — one element doing the job the name and a
    // separate `.slug` span were splitting between them.
    await expect(mgr.locator(".row").first().locator(".name")).toHaveText("@bundle");
    await expect(mgr.locator(".row").first().locator(".f-count")).toHaveText("8 concepts");
    await expect(mgr.locator(".row").first().locator(".hv-word")).toHaveText("no problems");
    await expect(mgr.locator(".row").first().locator(".def")).toHaveText("default");
  });

  test("the verdict is painted on the row's edge, not only written on it", async ({ mgr }) => {
    // --ok in light mode. The edge is a ::before with no layout box of its own,
    // so nothing but computed style can say whether it is there.
    expect(await edgeColor(mgr, 0)).toBe("rgb(26, 158, 95)");
  });

  test("the fact columns share one axis down the page", async ({ mgr }) => {
    const lefts = await mgr.locator(".f-health").evaluateAll((els) => els.map((e) => Math.round(e.getBoundingClientRect().left)));
    expect(new Set(lefts).size).toBe(1);
  });

  test("a long folder path is clipped at the front, keeping the end that names it", async ({ mgr }) => {
    const dir = mgr.locator(".row").first().locator(".dir");
    await expect(dir).toContainText("fixtures/bundle");
    // rtl on the box moves the ellipsis to the left; the <bdi> keeps the path
    // itself in reading order, so no leading "/" reorders to the far end.
    expect(await dir.evaluate((e) => getComputedStyle(e).direction)).toBe("rtl");
    expect(await dir.evaluate((e) => getComputedStyle(e.querySelector("bdi")).direction)).toBe("ltr");
  });

  test("on a phone the row stacks instead of overflowing", async ({ mgr }) => {
    await mgr.setViewportSize({ width: 375, height: 800 });
    const row = mgr.locator(".row").first();
    const who = await row.locator(".who").boundingBox();
    const facts = await row.locator(".facts").boundingBox();
    expect(facts.y).toBeGreaterThan(who.y);
    expect(await mgr.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  });
});
