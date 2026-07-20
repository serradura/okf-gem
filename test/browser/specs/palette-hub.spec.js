import { test as base, expect } from "@playwright/test";
import { bootGraph } from "../helpers.js";
import { HUB_PORT } from "../paths.js";

// The command palette's other half: switching bundles, which only exists when a
// hub is serving siblings. palette.spec.js covers the standalone view-jump path
// (both projects are standalone); this one points at the hub the config boots
// from two bundles, so /b/bundle/ carries a sibling and HUB_PATH is set. Reached
// by URL directly, so it does not depend on the project's baseURL.
const HUB = `http://127.0.0.1:${HUB_PORT}/b/bundle/`;

const test = base.extend({
  hub: async ({ page }, use) => {
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e)));
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    // seed okf-hello (skip the welcome note) but not okf-swseen — the discovery
    // badge is the thing under test
    await page.addInitScript(() => { try { localStorage.setItem("okf-hello", "1"); } catch (e) {} });
    await page.goto(HUB);
    await bootGraph(page);
    await use(page);
    if (errors.length) throw new Error(`page reported ${errors.length} console/page error(s):\n  ${errors.join("\n  ")}`);
  },
});

test.describe("command palette — hub (bundle switch)", () => {
  test("opens in bundle-switch mode and lists the sibling bundle", async ({ hub }) => {
    await hub.keyboard.press("Control+k");
    await expect(hub.locator("#sw")).toBeVisible();
    await expect(hub.locator("#sw-input")).toHaveAttribute("placeholder", /switch bundle/);
    // bundles lead on an empty query — the sibling is a data-path row
    await expect(hub.locator("#sw-list a[data-path]")).toHaveCount(1);
    await expect(hub.locator("#sw-list a[data-path]")).toContainText("hostile");
    // and the current bundle is named as a disabled "you are here" row
    await expect(hub.locator("#sw-list .cur")).toContainText("bundle");
  });

  test("the discovery badge shows the bundle count until the palette is opened", async ({ hub }) => {
    // SIBLINGS.length + 1 = 2; the pulse retires once the palette has been seen
    await expect(hub.locator("#sw-count")).toBeVisible();
    await expect(hub.locator("#sw-count")).toHaveText("2");

    await hub.keyboard.press("Control+k");
    await expect(hub.locator("#sw-count")).toBeHidden();
  });

  test("choosing the sibling navigates to it", async ({ hub }) => {
    await hub.keyboard.press("Control+k");
    await hub.locator("#sw-list a[data-path]").click();
    await expect(hub).toHaveURL(/\/b\/hostile\//);
  });
});
