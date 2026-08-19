import { test, expect } from "../helpers.js";

// The ≤768px chrome is the part of the template that moves most, and its
// regressions live entirely in computed layout — a control at its natural width
// with a chevron over dead space, an icon orphaned on its own wrapped line, a
// header that broke onto two. String assertions cannot see any of it; these read
// getBoundingClientRect and getComputedStyle at a real phone width.
const sameRow = (a, b) => Math.abs(a - b) <= 1;

test.describe("mobile chrome — the tools sheet (375px)", () => {
  test.use({ viewport: { width: 375, height: 720 } });

  test("the ident ellipsizes instead of overflowing the bar", async ({ app }) => {
    // adf96ff — a long bundle name used to push the ⚙ off the edge.
    const ident = app.locator(".ident");
    await expect(ident).toHaveCSS("text-overflow", "ellipsis");
    await expect(ident).toHaveCSS("overflow-x", "hidden");
    // the link/count subtitle is dropped at this width so the title owns the row
    await expect(app.locator(".ident .muted")).toBeHidden();
    // and the bar as a whole does not scroll sideways
    expect(await app.evaluate(() => document.getElementById("topbar").scrollWidth))
      .toBeLessThanOrEqual(375);
  });

  test("the folded tools sheet is two even columns with no orphaned icon", async ({ app }) => {
    // dec7cad — wrapping by whatever fit left one icon alone on a line. The two
    // word-carrying controls take a column each (row 1); the icon buttons then
    // share a line of their own (row 2), none stranded.
    await app.locator("#btn-controls").click();
    await expect(app.locator("#app")).toHaveClass(/controls-open/);

    const r = await app.evaluate(() => {
      const top = (id) => Math.round(document.getElementById(id).getBoundingClientRect().top);
      const selTop = Math.round(document.querySelector("#graph-controls .selwrap").getBoundingClientRect().top);
      return { filters: top("btn-filters"), sel: selTop, fit: top("btn-fit"),
        cluster: top("btn-cluster"), tree: top("btn-tree"), ix: top("btn-ix") };
    });
    // Row 1: Filters and the layout select, side by side.
    expect(sameRow(r.filters, r.sel), "Filters and the layout select share a row").toBe(true);
    // Row 2: all four icon buttons together, none orphaned onto a third line.
    expect(sameRow(r.fit, r.cluster) && sameRow(r.cluster, r.tree) && sameRow(r.tree, r.ix),
      "the four icon buttons share one row").toBe(true);
    expect(r.fit, "the icons sit below the word controls, not beside them").toBeGreaterThan(r.filters);
  });

  test("the layout select fills its wrapper so the whole control is clickable", async ({ app }) => {
    // a5f12ab — stretching only the wrapper left the select at its natural width
    // with the chevron pinned over dead space, and every click on it lost.
    await app.locator("#btn-controls").click();
    await expect(app.locator("#app")).toHaveClass(/controls-open/);

    const w = await app.evaluate(() => {
      const sel = document.querySelector("#graph-controls .selwrap");
      const lay = document.getElementById("layout");
      return { wrap: sel.getBoundingClientRect().width, layout: lay.getBoundingClientRect().width };
    });
    expect(w.layout).toBeGreaterThan(0);
    expect(Math.abs(w.layout - w.wrap), "the select spans its wrapper edge to edge").toBeLessThanOrEqual(1);
  });
});

test.describe("mobile chrome — the files header (375px)", () => {
  test.use({ viewport: { width: 375, height: 720 } });

  test("the file-tree header stays on one line", async ({ app }) => {
    // b376e8c — the tab bar broke onto two rows on a phone. Reach Files through
    // the drawer (the rail is off-screen here), then read every header control's
    // top: one distinct value means one line.
    await app.locator("#btn-menu").click();
    await app.locator('.rail-item[data-view="files"]').click();
    await expect(app.locator("#app")).toHaveAttribute("data-view", "files");
    await expect(app.locator("#ftree-list")).toContainText("orders.md");

    // The bar centres its items (align-items:center), so a short text label and
    // a 34px button have different tops on the *same* row — the honest "one line"
    // test is a shared vertical centre, not an identical top. A wrapped header
    // would split the centres by about a row's height.
    const centres = await app.evaluate(() =>
      [ ...document.querySelectorAll(".ftabs > *") ]
        .filter((el) => getComputedStyle(el).display !== "none")
        .map((el) => { const r = el.getBoundingClientRect(); return Math.round(r.top + r.height / 2); }));
    const span = Math.max(...centres) - Math.min(...centres);
    expect(centres.length, "the header has several controls").toBeGreaterThan(2);
    expect(span, `header controls span ${span}px vertically: ${centres}`).toBeLessThanOrEqual(3);
  });
});
