import { test, expect, showView, bootGraph, base } from "../helpers.js";
import { HUB_PORT } from "../paths.js";

// The topbar box and the ⌘K palette are two look-alike surfaces with different
// grammars: the box *filters* what is on screen, the palette *finds* across
// every bundle a hub hosts. The box said "search concepts…", emptied the graph
// in silence when nothing matched, and never mentioned the palette — so a
// reader whose word was not in this bundle got a blank canvas and no exit.
//
// Three things close that, and this file owns all three:
//
//   the chip    — the palette, named, inside the box that looks like it
//   the count   — n/total while filtering, so an empty result is a *number*
//                 that went to zero rather than a view that went blank
//   the bridge  — on zero matches, a panel that says so and offers the way out
//
// palette.spec.js and global-search.spec.js own the overlay itself; this file
// stays on the box and the handoff between them.

const HUB = `http://127.0.0.1:${HUB_PORT}/b/bundle/`;

const cnt = (page) => page.locator("#s-cnt");
const chip = (page) => page.locator("#s-cmdk");
const bridge = (page) => page.locator("#s-bridge");

test.describe("search bridge — the chip", () => {
  test("the box carries the palette's chord, inside the box", async ({ app }) => {
    // Inside `label.search`, not beside it: the affordance has to be where the
    // reader already is when the box disappoints them.
    await expect(app.locator("#search-wrap .search #s-cmdk")).toBeVisible();
    await expect(chip(app)).toHaveText(/^(⌘K|Ctrl-K)$/);
  });

  test("the chip opens the palette, and does not steal the box's focus doing it", async ({ app }) => {
    await chip(app).click();

    await expect(app.locator("#sw")).toBeVisible();
    // A chip inside a <label> hands its click to the input by default, which
    // would fight the palette for focus and leave the overlay uncontrollable.
    await expect(app.locator("#sw-input")).toBeFocused();
  });

  test("the chip leaves room for itself, so a long query never runs under it", async ({ app }) => {
    const pad = await app.locator("#search").evaluate((el) => getComputedStyle(el).paddingRight);
    expect(parseFloat(pad)).toBeGreaterThan(40);
  });
});

test.describe("search bridge — the count", () => {
  test("an empty box counts nothing", async ({ app }) => {
    await expect(cnt(app)).toBeHidden();
  });

  test("the graph count is what the filter kept, over what there is", async ({ app }) => {
    await app.locator("#search").fill("orders");
    await expect(cnt(app)).toBeVisible();

    // Both readings taken in one evaluate, at one instant. Sampling the chip
    // and the graph in two round-trips races the lazy MiniSearch index, which
    // lands mid-test and narrows the result under the first reading's feet —
    // and a spec that compares two different moments fails on the page being
    // *right* twice.
    const seen = await app.evaluate(() => {
      const live = cy.nodes().filter((n) => !n.isParent() && !n.hasClass("dir") && !n.hasClass("ix"));
      return {
        chip: document.getElementById("s-cnt").textContent,
        shown: live.filter((n) => n.style("display") !== "none").length,
        total: live.length,
      };
    });
    expect(seen.chip).toBe(`${seen.shown}/${seen.total}`);
    expect(seen.shown).toBeLessThan(seen.total);
  });

  test("clearing the box takes the count away again", async ({ app }) => {
    await app.locator("#search").fill("orders");
    await expect(cnt(app)).toBeVisible();

    await app.locator("#search").fill("");
    await expect(cnt(app)).toBeHidden();
  });

  test("the catalog and the files tree count their own rows", async ({ app }) => {
    await showView(app, "catalog");
    await app.locator("#search").fill("orders");
    await expect(cnt(app)).toHaveText(/^\d+\/\d+$/);
    const catalogShown = await app.locator("#cat-grid .card").count();
    await expect(cnt(app)).toHaveText(new RegExp(`^${catalogShown}/`));

    await showView(app, "files");
    await app.locator("#search").fill("orders");
    await expect(cnt(app)).toHaveText(/^\d+\/\d+$/);
  });

  test("a view with no search box has no count either", async ({ app }) => {
    await showView(app, "stats");
    await expect(cnt(app)).toBeHidden();
  });
});

test.describe("search bridge — the dead end", () => {
  test("zero matches says so, naming the bundle and the query", async ({ app }) => {
    await app.locator("#search").fill("zzzznothing");

    await expect(bridge(app)).toBeVisible();
    await expect(bridge(app)).toContainText("zzzznothing");
    await expect(cnt(app)).toHaveText(/^0\//, "the count is the same fact, said shorter");
  });

  test("a match hides the panel again", async ({ app }) => {
    await app.locator("#search").fill("zzzznothing");
    await expect(bridge(app)).toBeVisible();

    await app.locator("#search").fill("orders");
    await expect(bridge(app)).toBeHidden();
  });

  test("Clear empties the box, restores the view, and returns the cursor", async ({ app }) => {
    await app.locator("#search").fill("zzzznothing");
    await expect(bridge(app)).toBeVisible();

    await app.locator("#sb-clear").click();

    await expect(bridge(app)).toBeHidden();
    await expect(app.locator("#search")).toHaveValue("");
    await expect(app.locator("#search")).toBeFocused();
    const shown = await app.evaluate(() =>
      cy.nodes().filter((n) => !n.isParent() && n.style("display") !== "none").length);
    expect(shown).toBeGreaterThan(0);
  });

  test("esc in the box is the same as Clear", async ({ app }) => {
    await app.locator("#search").fill("zzzznothing");
    await expect(bridge(app)).toBeVisible();

    await app.locator("#search").press("Escape");

    await expect(bridge(app)).toBeHidden();
    await expect(app.locator("#search")).toHaveValue("");
  });

  test("a query of markup is echoed as text, not as markup", async ({ app }) => {
    // The panel is a new render path carrying a string the reader typed, and it
    // reaches innerHTML — so it owes the same probe every other such path has.
    await app.locator("#search").fill('<img src=x onerror="window.__pwned=1">');

    await expect(bridge(app)).toBeVisible();
    expect(await app.evaluate(() => window.__pwned)).toBeUndefined();
    expect(await app.locator(".sb-msg img").count()).toBe(0);
    await expect(app.locator(".sb-msg")).toContainText("<img src=x");
  });

  test("the escalation exists exactly where a finder does", async ({ app }, testInfo) => {
    await app.locator("#search").fill("zzzznothing");
    await expect(bridge(app)).toBeVisible();

    // A served bundle has a /search the in-page box cannot match — it indexes
    // bodies the page never fetched — so escalating is real. A static file has
    // no finder behind it, and the panel names the dead end instead.
    if (testInfo.project.name === "static") {
      await expect(app.locator("#sb-go")).toBeHidden("there is no elsewhere to send anyone to");
    } else {
      await expect(app.locator("#sb-go")).toBeVisible();
    }
  });
});

// The escalation only completes where there is somewhere to escalate *to*, so
// its last leg is a hub spec. The hub the config boots serves `bundle` and
// `hostile` together; "sanitizer" appears only in hostile, which is exactly the
// query the local box cannot answer and the palette can.
const hubTest = base.extend({
  hub: async ({ page }, use) => {
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e)));
    page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
    await page.addInitScript(() => {
      try { localStorage.setItem("okf-hello", "1"); localStorage.setItem("okf-swseen", "1"); } catch (e) {}
    });
    await page.goto(HUB);
    await bootGraph(page);
    await use(page);
    if (errors.length) throw new Error(`page reported ${errors.length} error(s):\n  ${errors.join("\n  ")}`);
  },
});

hubTest.describe("search bridge — the handoff", () => {
  hubTest("a dead-end query hands itself to the palette, prefilled and already searching", async ({ hub }) => {
    await hub.locator("#search").fill("sanitizer");
    await expect(hub.locator("#s-bridge")).toBeVisible();

    await hub.locator("#sb-go").click();

    await expect(hub.locator("#sw")).toBeVisible();
    await expect(hub.locator("#sw-input")).toHaveValue("sanitizer", "the query carries over — nobody retypes it");
    // and it fires on arrival, rather than waiting for a keystroke that would
    // only reproduce what the reader already typed
    await expect(hub.locator("#sw-list a[data-hit]").first()).toBeVisible({ timeout: 10_000 });
  });

  hubTest("Enter in the box is the same handoff", async ({ hub }) => {
    await hub.locator("#search").fill("sanitizer");
    await expect(hub.locator("#s-bridge")).toBeVisible();

    await hub.locator("#search").press("Enter");

    await expect(hub.locator("#sw")).toBeVisible();
    await expect(hub.locator("#sw-input")).toHaveValue("sanitizer");
  });

  hubTest("closing the palette on a still-dead query brings the offer back", async ({ hub }) => {
    await hub.locator("#search").fill("zzzznothing");
    await hub.locator("#sb-go").click();
    await expect(hub.locator("#sw")).toBeVisible();

    await hub.keyboard.press("Escape");

    await expect(hub.locator("#sw")).toBeHidden();
    await expect(hub.locator("#s-bridge")).toBeVisible("the query is still dead, so the way out is still on offer");
  });
});
