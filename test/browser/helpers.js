import { test as playwright, expect } from "@playwright/test";
import { installVendorCache } from "./vendor-cache.js";

export { expect };

// The layer under every spec in the suite, `app` fixture or not: the CDN
// libraries the page boots with are served from a local read-through cache
// instead of being re-downloaded per test. See vendor-cache.js for why that is
// where the suite's time went.
//
// Specs that build their own page fixture import this as `base` — that is the
// only reason it is exported. Importing `test as base` from "@playwright/test"
// directly would skip the cache, so nothing in specs/ does.
export const base = playwright.extend({
  context: async ({ context }, use) => {
    await installVendorCache(context);
    await use(context);
  },
});

// Every spec gets `app`: a booted page with the first-visit note already
// dismissed, plus a console watch that fails the test on a page error.
//
// The console watch is the point of the whole suite. The bugs this file keeps
// producing are not "the button looks wrong" — they are "a change over here
// threw in a listener over there, and the page half-works". A thrown error in
// a handler is invisible to a screenshot and fatal to the feature, so it fails
// the test by default and a spec opts out with `app.allowErrors()`.
export const test = base.extend({
  app: async ({ page, baseURL }, use) => {
    const errors = [];
    let watching = true;

    page.on("pageerror", (err) => watching && errors.push(String(err)));
    page.on("console", (msg) => {
      if (watching && msg.type() === "error") errors.push(msg.text());
    });

    // Seed the "already visited" flag before any script runs, so the one-time
    // note never covers the graph. Wrapped because a file:// page has no
    // writable localStorage — there the note stays down on its own.
    await page.addInitScript(() => {
      try { localStorage.setItem("okf-hello", "1"); } catch (e) {}
    });

    await page.goto(baseURL);
    await bootGraph(page);

    page.allowErrors = () => { watching = false; };
    await use(page);

    if (watching && errors.length) {
      throw new Error(`page reported ${errors.length} console/page error(s):\n  ${errors.join("\n  ")}`);
    }
  },
});

// Boot is done when Cytoscape has laid out the nodes. `cy` is a top-level
// `const` in a classic script, so it is a global binding but not a property of
// `window` — evaluate() sees it through the scope chain, `window.cy` does not.
export async function bootGraph(page) {
  await page.waitForFunction(() => typeof cy !== "undefined" && cy.nodes().length > 0, null, { timeout: 20_000 });
}

// The view the rail is showing. #app[data-view] is the single source of truth
// the CSS keys off, so asserting it is asserting what the user sees.
export const view = (page) => page.locator("#app").getAttribute("data-view");

export const showView = async (page, name) => {
  await page.locator(`.rail-item[data-view="${name}"]`).click();
  await expect(page.locator("#app")).toHaveAttribute("data-view", name);
};

// The inspector's three states live in one attribute: hidden | default | wide.
export const sideState = (page) => page.locator(".graph-body").getAttribute("data-side");

// Node ids as Cytoscape has them — the graph's own truth, not the DOM's.
export const visibleNodeIds = (page) =>
  page.evaluate(() => cy.nodes().filter((n) => n.visible() && !n.isParent()).map((n) => n.id()).sort());

export const nodeCount = (page) => page.evaluate(() => cy.nodes().filter((n) => !n.isParent()).length);

// The graph's rendered extent, read only once it has stopped moving.
//
// Settling matters more than it looks: the canvas animates, and the 240ms
// resize debounce means a collapse after a view switch takes ~200ms to
// appear. A poll that accepts the first good reading passes on the value the
// page was *leaving*, not the one it lands on — which is how a test for this
// bug ends up green while the bug is present.
export async function settledBox(page, { step = 150, tries = 24 } = {}) {
  const read = () => page.evaluate(() => {
    const b = cy.elements().renderedBoundingBox();
    return { w: Math.round(b.x2 - b.x1), h: Math.round(b.y2 - b.y1) };
  });

  let prev = await read();
  for (let i = 0; i < tries; i++) {
    await page.waitForTimeout(step);
    const next = await read();
    if (next.w === prev.w && next.h === prev.h) return next;
    prev = next;
  }
  return prev;
}

// Click a concept through Cytoscape rather than at a screen coordinate: the
// canvas has no DOM node to target, and a synthetic tap is what the page's own
// handlers listen for.
// The braces are not style: emit() returns the Cytoscape collection, and an
// arrow with an expression body hands that back to Playwright to serialize —
// a cyclic object graph with the whole cy instance hanging off it, which cost
// ~5s per call. Returning nothing makes the same tap effectively free.
export const clickNode = async (page, id) => {
  await page.evaluate((nodeId) => { cy.getElementById(nodeId).emit("tap"); }, id);
};
