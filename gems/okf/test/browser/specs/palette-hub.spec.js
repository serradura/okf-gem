import { test as base, expect, bootGraph } from "../helpers.js";
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
    // and the current bundle is named as a disabled "you are here" row, wearing
    // the same @slug the rows under it do
    await expect(hub.locator("#sw-list .cur")).toContainText("@bundle");
  });

  // The slug is what addresses a bundle — `@hostile`, /b/hostile/ — so it is the
  // name; the folder is where it happens to live. The row led with the folder,
  // which in a real registry is `…/.okf` on nearly every line: the loudest column
  // saying the one thing that tells no two bundles apart.
  test("a bundle row leads with its slug and trails with where it lives", async ({ hub }) => {
    await hub.keyboard.press("Control+k");
    const row = hub.locator("#sw-list a[data-path]");

    await expect(row.locator("span").first()).toHaveText(/^@hostile/);
    await expect(row.locator(".sw-where")).toHaveText("fixtures/hostile");

    // and the name still outweighs the location, whatever the order
    const [ name, where ] = await row.evaluate((a) => [
      getComputedStyle(a.querySelector("span")).fontSize,
      getComputedStyle(a.querySelector(".sw-where")).fontSize,
    ]);
    expect(parseFloat(name)).toBeGreaterThan(parseFloat(where));
  });

  // The location is a second fact, not a decoration: where it repeats the slug it
  // is not printed. Driven through the real formatter rather than a fixture,
  // because no committed bundle sits in a directory named for its own slug.
  test("the location is omitted where it only repeats the slug", async ({ hub }) => {
    const cases = await hub.evaluate(() => [
      bundleWhere({ slug: "minifts", title: "minifts" }),
      bundleWhere({ slug: "okf-gem", title: "repo" }),
    ]);

    expect(cases).toEqual([ "", "repo" ]);
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

  test("the ⌘⏎ chord opens the sibling in a new tab instead of navigating", async ({ hub }) => {
    // A bundle is a real navigation, so it honours the new-tab chord: Enter with
    // meta/ctrl held calls window.open(t,'_blank') rather than setting
    // location.href. Catch the popup on the browser context, and confirm the
    // current tab did NOT navigate — the whole point of the chord is that this
    // one stays put.
    await hub.keyboard.press("Control+k");
    await expect(hub.locator("#sw-list a[data-path]")).toBeVisible();

    const [ popup ] = await Promise.all([
      hub.context().waitForEvent("page"),
      hub.locator("#sw-input").press("Control+Enter"),
    ]);
    expect(popup.url()).toMatch(/\/b\/hostile\//);
    await popup.close();

    // still on bundle — the chord opened a tab, it did not move this one
    await expect(hub).toHaveURL(/\/b\/bundle\//);
    // and the palette closed itself after firing
    await expect(hub.locator("#sw")).toBeHidden();
  });

  test("the ⇄ switch-bundle button is shown in hub mode", async ({ hub }) => {
    // The counterpart to palette.spec's standalone assertion: with a hub behind
    // it, #btn-switch un-hides (setup: `if(btn&&HUB)btn.hidden=false`).
    await expect(hub.locator("#btn-switch")).toBeVisible();
  });

  test("a sibling link carries the current view and layout, dropping the selection", async ({ hub }) => {
    // target() folds the bundle-agnostic page state into the sibling href so a
    // switch lands on the same view and layout — but the node selection and hash
    // are bundle-specific and deliberately dropped. Pick a non-default layout on
    // the graph, then go to catalog, then open the palette: the sibling row's
    // href carries both. (Set the layout first — its selector lives in the graph
    // controls, hidden on other views.)
    await hub.locator("#layout").selectOption("grid");
    await hub.locator('.rail-item[data-view="catalog"]').click();
    await expect(hub.locator("#app")).toHaveAttribute("data-view", "catalog");

    await hub.keyboard.press("Control+k");
    const href = await hub.locator("#sw-list a[data-path]").getAttribute("href");
    expect(href, "the sibling link carries the view").toContain("view=catalog");
    expect(href, "and the layout").toContain("layout=grid");
    expect(href, "but not the bundle-specific selection").not.toContain("select=");
  });
});
