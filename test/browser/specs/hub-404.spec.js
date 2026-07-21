import { test as base, expect } from "../helpers.js";
import { HUB_PORT } from "../paths.js";

// The hub's 404, driven. hub_404_test.rb proves what the page is *rendered*
// with — the path, the near miss, the rows — and that half is deliberately all
// server-side, because this is where a reader lands when something has already
// gone wrong and a page that needs JavaScript to say what happened has picked
// the worst possible moment to need it.
//
// What is left for script is the filter, the count and the keyboard, and none
// of that is checkable from a string. It is also the half a reader reaches for
// *first*: the box is autofocused, so the very next thing that happens on this
// page is a keystroke.
//
// Only a hub has this page (a standalone server has no set to be wrong about),
// so it is reached by URL like manager.spec.js rather than through a baseURL.
const NOT_FOUND = `http://127.0.0.1:${HUB_PORT}/b/bundel/`;

const test = base.extend({
  lost: async ({ page }, use) => {
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e)));
    // The one page in the suite whose *correct* answer is a 404, so Chromium
    // logs the document's own status as a console error. Dropping it is safe
    // here and nowhere else: this page loads no subresource at all — no CDN, no
    // font, not even a favicon (hub_404_test.rb pins that) — so a 404 logged
    // here can only ever be the document itself.
    page.on("console", (m) => {
      if (m.type() === "error" && !/status of 404/.test(m.text())) errors.push(m.text());
    });
    await page.goto(NOT_FOUND);
    await use(page);
    if (errors.length) throw new Error(`page reported ${errors.length} error(s):\n  ${errors.join("\n  ")}`);
  },
});

test.describe("hub 404 — the way out", () => {
  test("the box has the cursor on arrival, so the next keystroke filters", async ({ lost }) => {
    await expect(lost.locator("#q")).toBeFocused();
  });

  test("typing narrows the rows and the chip counts what survived", async ({ lost }) => {
    const total = await lost.locator("#blist li").count();
    await expect(lost.locator("#bar-count")).toHaveText(String(total));

    await lost.locator("#q").fill("hostile");

    const shown = lost.locator("#blist li:not([hidden])");
    await expect(shown).toHaveCount(1);
    await expect(lost.locator("#bar-count")).toHaveText(`1/${total}`);
  });

  test("the filter reaches the folder, not only the name", async ({ lost }) => {
    // The folder is on the row because it is often the only thing telling two
    // bundles apart, so it has to be searchable for the same reason.
    await lost.locator("#q").fill("fixtures/hostile");
    await expect(lost.locator("#blist li:not([hidden])")).toHaveCount(1);
  });

  test("a query nothing matches raises the graph page's own bridge, under the box", async ({ lost }) => {
    // Same component, same place, same two buttons as the topbar box on the
    // graph page — because it is the same event: the box came up empty and
    // there is somewhere else to look.
    await lost.locator("#q").fill("zzzznothing");

    await expect(lost.locator("#blist li:not([hidden])")).toHaveCount(0);
    await expect(lost.locator("#s-bridge")).toBeVisible();
    await expect(lost.locator(".sb-msg")).toContainText("No bundle matches");
    await expect(lost.locator(".sb-msg b")).toHaveText("zzzznothing");
    await expect(lost.locator("#sb-go")).toBeVisible();
    await expect(lost.locator("#sb-clear")).toBeVisible();
  });

  test("Clear empties the box, restores the rows, and returns the cursor", async ({ lost }) => {
    const total = await lost.locator("#blist li").count();
    await lost.locator("#q").fill("zzzznothing");
    await expect(lost.locator("#s-bridge")).toBeVisible();

    await lost.locator("#sb-clear").click();

    await expect(lost.locator("#s-bridge")).toBeHidden();
    await expect(lost.locator("#q")).toHaveValue("");
    await expect(lost.locator("#q")).toBeFocused();
    await expect(lost.locator("#blist li:not([hidden])")).toHaveCount(total);
  });

  test("/ reaches the box from anywhere on the page", async ({ lost }) => {
    // A reader who tabbed into the list and changed their mind should not have
    // to tab back out of it — the same key the graph page binds.
    await lost.keyboard.press("Tab");
    await lost.keyboard.press("Tab");
    await expect(lost.locator("#q")).not.toBeFocused();

    await lost.keyboard.press("/");

    await expect(lost.locator("#q")).toBeFocused();
    await expect(lost.locator("#q")).toHaveValue("", "and the slash is not typed into it");
  });

  test("esc clears the box and brings every row back", async ({ lost }) => {
    const total = await lost.locator("#blist li").count();
    await lost.locator("#q").fill("hostile");
    await expect(lost.locator("#blist li:not([hidden])")).toHaveCount(1);

    await lost.locator("#q").press("Escape");

    await expect(lost.locator("#q")).toHaveValue("");
    await expect(lost.locator("#blist li:not([hidden])")).toHaveCount(total);
    await expect(lost.locator("#s-bridge")).toBeHidden();
  });

  test("Tab walks the rows and Shift+Tab comes back, with no cursor of our own", async ({ lost }) => {
    // Moving through the list is Tab's job and Tab already does it: every row is
    // an <a href>. The page used to hand-roll ↑↓ instead, which meant a second
    // focus model living beside the real one — rows lit that the browser did not
    // consider focused, invisible to a screen reader, and two of them lit at
    // once whenever the two models fell out of step.
    const href = (n) => lost.locator("#blist li:not([hidden]) a").nth(n);

    await lost.keyboard.press("Tab");
    await expect(lost.locator(".miss a")).toBeFocused();

    await lost.keyboard.press("Tab");
    await expect(href(0)).toBeFocused();

    await lost.keyboard.press("Tab");
    await expect(href(1)).toBeFocused();

    await lost.keyboard.press("Shift+Tab");
    await expect(href(0)).toBeFocused();
  });

  test("a filtered-out row drops out of the tab order, without being told to", async ({ lost }) => {
    // display:none does this for free, which is the other half of why the
    // hand-rolled cursor was worth deleting: it had to be taught.
    await lost.locator("#q").fill("hostile");
    await expect(lost.locator("#blist li:not([hidden])")).toHaveCount(1);

    await lost.keyboard.press("Tab");
    await expect(lost.locator('#blist li:not([hidden]) a')).toBeFocused();
  });

  test("exactly one row is marked, and it is the one ⏎ would open", async ({ lost }) => {
    // The mark is not a cursor — it never moves on its own. It says what Enter
    // does from here, which is the near miss on arrival and the first match once
    // there is a query.
    await expect(lost.locator("a.active")).toHaveCount(1);
    await expect(lost.locator(".miss a.active")).toHaveCount(1);

    await lost.locator("#q").fill("hostile");
    await expect(lost.locator("a.active")).toHaveCount(1);
    await expect(lost.locator("#blist a.active")).toHaveAttribute("href", "/b/hostile/");
  });

  test("the mark stands down once the caret leaves the box", async ({ lost }) => {
    // Past that point ⏎ belongs to whatever Tab focused, so a row still claiming
    // "Enter opens me" would be claiming something untrue.
    await expect(lost.locator("a.active")).toHaveCount(1);

    await lost.keyboard.press("Tab");

    await expect(lost.locator("a.active")).toHaveCount(0);
  });

  test("⏎ with nothing typed takes the near miss the mark is on", async ({ lost }) => {
    const miss = await lost.locator(".miss a").getAttribute("href");
    expect(miss).toBe("/b/bundle/");

    await lost.locator("#q").press("Enter");

    await lost.waitForURL("**/b/bundle/");
  });

  test("⏎ after a query opens the first match", async ({ lost }) => {
    await lost.locator("#q").fill("hostile");
    await lost.locator("#q").press("Enter");

    await lost.waitForURL("**/b/hostile/");
  });

  test("typing supersedes the guess, because it answers a different question", async ({ lost }) => {
    // The near miss is about the *path* you asked for. Once there is a query it
    // is an answer to something nobody asked, sitting above the answer to what
    // they did.
    await expect(lost.locator(".miss")).toBeVisible();
    await lost.locator("#q").fill("hostile");
    await expect(lost.locator(".miss")).toBeHidden();

    await lost.locator("#q").fill("");
    await expect(lost.locator(".miss")).toBeVisible();
  });

  test("the near miss is the same row anatomy as the list, not a sentence", async ({ lost }) => {
    // What a reader learns to read in the list reads the same as the guess,
    // because they are literally the same markup — one of them lit.
    const miss = lost.locator(".miss .brow");
    await expect(miss.locator(".b-title")).toBeVisible();
    await expect(miss.locator(".slug")).toHaveText("@bundle");
    await expect(miss.locator(".b-dir")).toContainText("fixtures/bundle");
    await expect(miss.locator(".b-cnt")).toContainText("concepts");
  });

  test("a query no bundle matches is offered the search that would match", async ({ lost }) => {
    // The escalation the graph page's box makes, arriving here for the same
    // reason: a bundle list cannot answer "where is the thing about sanitizing?"
    // and the hub can, because /search reads inside every bundle it hosts.
    // "sanitizer" is in the hostile fixture's bodies and in no bundle's name.
    await lost.locator("#q").fill("sanitizer");

    await expect(lost.locator("#s-bridge")).toBeVisible();
    await expect(lost.locator(".sb-msg")).toContainText("No bundle matches");
    await expect(lost.locator(".sb-msg b")).toHaveText("sanitizer");
    await expect(lost.locator("#sb-go")).toBeVisible();
  });

  test("⏎ at the dead end runs that search, and the hits join the same cursor", async ({ lost }) => {
    await lost.locator("#q").fill("gateway");
    await expect(lost.locator("#s-bridge")).toBeVisible();

    await lost.locator("#q").press("Enter");

    await expect(lost.locator("#hits")).toBeVisible();
    await expect(lost.locator("#hitlist li").first()).toBeVisible({ timeout: 10_000 });
    // A hit is a row like every other: Tab reaches it, and the mark moves onto
    // the first one because that is now what ⏎ would open.
    await expect(lost.locator("#hitlist a.active")).toHaveCount(1);
    const href = await lost.locator("#hitlist a.active").getAttribute("href");
    expect(href).toMatch(/\/b\/[^/]+\/\?select=/);
  });

  test("a search that finds nothing either says so, rather than an empty panel", async ({ lost }) => {
    await lost.locator("#q").fill("zzzznothinganywhere");
    await lost.locator("#q").press("Enter");

    await expect(lost.locator("#hitnote")).toHaveText("No concept matches either.", { timeout: 10_000 });
  });

  test("a healthy row carries no verdict edge, so a warning would be the only one", async ({ lost }) => {
    // Colour marks the exception. Six rules saying "nothing to report" is a page
    // where the one thing that matters cannot be found by looking.
    const edges = await lost.evaluate(() =>
      [ ...document.querySelectorAll("#blist .brow") ].map((li) => ({
        health: li.getAttribute("data-health"),
        shadow: getComputedStyle(li.querySelector("a")).boxShadow,
      })));
    expect(edges.length).toBeGreaterThan(0);
    for (const row of edges.filter((r) => r.health === "ok")) {
      expect(row.shadow, "an ok row is unmarked").toMatch(/rgba\(0, 0, 0, 0\)|none/);
    }
  });

  test("nothing overflows sideways, at a phone width or a desktop one", async ({ lost }) => {
    for (const width of [ 390, 1500 ]) {
      await lost.setViewportSize({ width, height: 800 });
      expect(await lost.evaluate(() => document.documentElement.scrollWidth),
        `overflowed at ${width}`).toBeLessThanOrEqual(width);
    }
  });
});
