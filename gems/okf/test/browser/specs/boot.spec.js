import { test, expect, view, sideState, nodeCount } from "../helpers.js";

// What the page owes on arrival, before anyone touches it. Every other spec
// starts from this state, so if these fail the rest of the suite's failures
// are noise.
test.describe("boot", () => {
  test("lands on the graph with every concept drawn and nothing filtered", async ({ app }) => {
    expect(await view(app)).toBe("graph");
    expect(await nodeCount(app)).toBe(8);
    await expect(app.locator("#btn-filters .fbadge")).toHaveText("0");
  });

  test("the inspector starts hidden, at zero width", async ({ app }) => {
    expect(await sideState(app)).toBe("hidden");
    await expect(app.locator("#btn-panel")).toHaveAttribute("aria-pressed", "false");
    // The panel collapses by width, not by `display` — a hidden panel that
    // still occupies its 380px is the bug this pins.
    await expect(app.locator("#side")).toHaveCSS("width", "0px");
  });

  test("the third-party libraries the page hard-depends on are present", async ({ app }) => {
    // Cytoscape, marked and DOMPurify load from the CDN at boot (constraint 5).
    // DOMPurify missing is the dangerous one: renderMarkdown would throw rather
    // than silently skip sanitizing, but only when a body is first rendered.
    expect(await app.evaluate(() => [
      typeof cytoscape, typeof marked, typeof DOMPurify,
    ])).toEqual([ "function", "object", "function" ]);
  });

  test("the header counts match the bundle", async ({ app }) => {
    await expect(app.locator(".ident .muted")).toHaveText("8 concepts · 23 links");
  });

  test("the type legend carries one chip per type, with counts", async ({ app }) => {
    const chips = app.locator("#ftypes .chip");
    await expect(chips).toHaveCount(5);
    await expect(chips.filter({ hasText: "Service" })).toHaveText("Service 2");
    await expect(chips.filter({ hasText: "Charter" })).toHaveText("Charter 1");
  });

  test("a root-level concept produces the (root) dir chip", async ({ app }) => {
    // Unreachable from a bundle whose concepts all sit in folders — the
    // fixture carries charter.md at the root precisely to reach this branch.
    await expect(app.locator('#fdirs .chip[data-dir="."]')).toHaveText("(root) 1");
    await expect(app.locator("#fdirs .chip")).toHaveCount(5);
  });
});

// prefers-reduced-motion is a page-level contract too: the graph body eases its
// inspector column over .22s, and `*{transition:none!important}` under `reduce`
// must strip that. emulateMedia flips the preference live (matchMedia and the
// CSS both re-evaluate), so one test can read both sides and the pair proves the
// media query, not that some element happens to read 0s.
test.describe("reduced motion", () => {
  const graphBodyDur = (app) =>
    app.locator(".graph-body").evaluate((el) => getComputedStyle(el).transitionDuration);

  test("prefers-reduced-motion:reduce strips the graph body's transition", async ({ app }) => {
    await app.emulateMedia({ reducedMotion: "no-preference" });
    expect(await graphBodyDur(app)).not.toBe("0s");

    await app.emulateMedia({ reducedMotion: "reduce" });
    expect(await graphBodyDur(app)).toBe("0s");
  });
});
