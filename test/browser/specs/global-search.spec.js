import { test as base, expect, test, bootGraph } from "../helpers.js";
import { HUB_PORT } from "../paths.js";

// The palette's third group: concepts, from every bundle the hub hosts, over
// the hub's own GET /search. This is the one group that costs a request, so it
// is also the one that can be stale, empty, or capped — and each of those is a
// state the reader has to be able to read off the list.
//
// palette-hub.spec.js owns the bundle-switch half of the same overlay; this
// file stays out of it. The hub the config boots serves `bundle` and `hostile`
// together, which is what makes a cross-bundle hit possible at all: "sanitizer"
// appears only in hostile, "rollback" only in bundle.
const HUB = `http://127.0.0.1:${HUB_PORT}/b/bundle/`;

const hubTest = base.extend({
  hub: async ({ page }, use) => {
    const errors = [];
    let resources = true;
    page.on("pageerror", (e) => errors.push(String(e)));
    page.on("console", (m) => {
      if (m.type() !== "error") return;
      // The hostile fixture's body carries <img src="x" onerror=…> on purpose,
      // so any test that lands on its Payload concept gets one 404 from a
      // deliberately broken image. That is the fixture working, not the page
      // failing — but it is a resource error, not a thrown one, so a test that
      // goes there opts out of that half of the watch and keeps the rest.
      if (!resources && /Failed to load resource/.test(m.text())) return;
      errors.push(m.text());
    });
    await page.addInitScript(() => {
      try { localStorage.setItem("okf-hello", "1"); localStorage.setItem("okf-swseen", "1"); } catch (e) {}
    });
    await page.goto(HUB);
    await bootGraph(page);
    page.allowBrokenResources = () => { resources = false; };
    await use(page);
    if (errors.length) throw new Error(`page reported ${errors.length} console/page error(s):\n  ${errors.join("\n  ")}`);
  },
});

// Open the palette and type, then wait for the group to settle — the fetch is
// debounced, so asserting straight after the keystroke reads the empty list the
// page is about to replace.
const search = async (page, q) => {
  await page.keyboard.press("Control+k");
  await expect(page.locator("#sw")).toBeVisible();
  await page.locator("#sw-input").fill(q);
};

const hits = (page) => page.locator("#sw-list a[data-hit]");

hubTest.describe("global search — hub", () => {
  hubTest("the palette bills itself as a search once the hub answers one", async ({ hub }) => {
    await hub.keyboard.press("Control+k");
    await expect(hub.locator("#sw-input")).toHaveAttribute("placeholder", /search concepts/);
    // an empty box asks nothing: no query, no group, no request
    await expect(hub.locator("#sw-list a[data-hit]")).toHaveCount(0);
    await expect(hub.locator("#sw-list")).not.toContainText("Concepts");
  });

  hubTest("a term only the sibling bundle carries comes back slugged to it", async ({ hub }) => {
    await search(hub, "sanitizer");

    await expect(hits(hub)).toHaveCount(1);
    const row = hits(hub).first();
    await expect(row).toHaveAttribute("data-slug", "hostile");
    await expect(row.locator(".hit-t")).toContainText("Payload");
    await expect(row.locator(".slug")).toHaveText("hostile");
    // the snippet is the evidence, and the term is marked where it landed
    await expect(row.locator(".hit-s mark")).toHaveText("sanitizer");
  });

  hubTest("choosing a sibling's concept opens that bundle with the node selected", async ({ hub }) => {
    hub.allowBrokenResources();
    await search(hub, "sanitizer");
    await expect(hits(hub)).toHaveCount(1);

    await hits(hub).first().click();

    // ?select= is the whole deep link — the view and layout a bundle switch
    // carries across are exactly what naming a node has to override. The #hash
    // arrives after, from the page's own selection handler.
    await expect(hub).toHaveURL(/\/b\/hostile\/\?select=payload/);
    await bootGraph(hub);
    await expect.poll(() => hub.evaluate(() => cy.getElementById("payload").hasClass("hl"))).toBe(true);
  });

  hubTest("a concept in this bundle is selected in place, not reloaded", async ({ hub }) => {
    // The search covers every hosted bundle, including the one being read. A
    // page load to arrive where you already are would throw away the camera,
    // the filters and the layout for nothing — so the claim under test is that
    // this document survives the click, which a sentinel on window can prove
    // and a URL assertion cannot.
    await hub.evaluate(() => { window.__sameDocument = true; });
    await search(hub, "rollback");
    await expect(hits(hub).first()).toHaveAttribute("data-slug", "bundle");

    await hits(hub).first().click();

    await expect(hub.locator("#sw")).toBeHidden();
    await expect.poll(() => hub.evaluate(() => cy.getElementById("runbooks/rollback").hasClass("hl"))).toBe(true);
    expect(await hub.evaluate(() => window.__sameDocument)).toBe(true);
  });

  hubTest("Enter opens the first hit when nothing above it matched", async ({ hub }) => {
    hub.allowBrokenResources();
    await search(hub, "sanitizer");
    await expect(hits(hub)).toHaveCount(1);
    // no bundle and no view is called "sanitizer", so the concept is row zero
    await expect(hits(hub).first()).toHaveClass(/active/);

    await hub.locator("#sw-input").press("Enter");
    await expect(hub).toHaveURL(/\/b\/hostile\/\?select=payload/);
  });

  hubTest("a term nothing carries says so instead of showing an empty group", async ({ hub }) => {
    await search(hub, "zzzznothinghere");

    await expect(hits(hub)).toHaveCount(0);
    await expect(hub.locator("#sw-list")).toContainText("no concepts match");
  });

  hubTest("a hit's title is escaped, not executed", async ({ hub }) => {
    // The hostile bundle's Attributes concept carries `</script><script>…` in
    // its title. It reaches the palette as JSON and goes into the DOM through
    // esc() — including the highlighter, which splits the raw text and escapes
    // each piece rather than wrapping tags around escaped text.
    await search(hub, "attributes");

    const row = hits(hub).filter({ hasText: "__xssTitle" }).first();
    await expect(row).toBeVisible();
    await expect(row.locator(".hit-t")).toContainText("</script>");
    expect(await hub.evaluate(() => window.__xssTitle)).toBeUndefined();
    // and the mark is a real <mark>, so the highlighter did run on this row
    await expect(row.locator("mark").first()).toBeVisible();
  });
});

// The other half of the contract, and the reason this spec is not hub-only:
// where there is no hub there is no cross-bundle search, and the group must not
// merely be empty — it must not exist. Runs in both projects, so it covers the
// standalone `okf server` and the static `okf render` file.
test.describe("global search — no hub, no group", () => {
  test("the page carries no search endpoint", async ({ app }) => {
    expect(await app.evaluate(() => SEARCH_ENDPOINT)).toBeNull();
  });

  test("typing never produces a concept row", async ({ app }) => {
    await app.keyboard.press("Control+k");
    await expect(app.locator("#sw")).toBeVisible();
    await expect(app.locator("#sw-input")).toHaveAttribute("placeholder", "jump to a view…");

    await app.locator("#sw-input").fill("rollback");
    await app.waitForTimeout(400); // longer than the debounce a hub would have used
    await expect(app.locator("#sw-list a[data-hit]")).toHaveCount(0);
    await expect(app.locator("#sw-list")).not.toContainText("Concepts");
  });
});
