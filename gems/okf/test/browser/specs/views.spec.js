import { test, expect, view, showView, settledBox } from "../helpers.js";

// Six rail buttons, five views: Index is Files with its index-only filter
// pressed, not a view of its own. `setView` touches nearly every section in
// the template, which makes it the single likeliest place for a change over
// here to break something over there.
test.describe("view switching", () => {
  test("the rail moves #app[data-view] and marks itself active", async ({ app }) => {
    for (const name of [ "catalog", "tags", "stats", "files", "graph" ]) {
      await showView(app, name);
      await expect(app.locator(`.rail-item[data-view="${name}"]`)).toHaveClass(/active/);
      await expect(app.locator(`#view-${name}`)).toHaveClass(/active/);
    }
  });

  test("Index lands on Files with the root map already open in the reader", async ({ app }) => {
    // readIndex() is setView('files') + openReserved('index','index.md') — it
    // opens the map, it does not press the index-only filter next to it.
    await app.locator('.rail-item[data-view="index"]').click();
    await expect(app.locator("#app")).toHaveAttribute("data-view", "files");
    await expect(app.locator("#ftree-ixonly")).toHaveAttribute("aria-pressed", "false");
    await expect(app.locator("#fp-title")).toHaveText("index.md");
    await expect(app.locator("#fp-body")).toContainText("Checkout Platform");
  });

  // Index and Files are one view, so `data-view` cannot tell them apart — and the
  // rail was reading nothing else, which left Files lit on the one screen the
  // reader reached by asking for Index. The open file is the only thing that
  // distinguishes them, so it is what the rail has to read.
  test("the rail says Index while the root map is open, and Files once it is not", async ({ app }) => {
    await app.locator('.rail-item[data-view="index"]').click();
    await expect(app.locator("#app")).toHaveAttribute("data-view", "files");
    await expect(app.locator('.rail-item[data-view="index"]')).toHaveClass(/active/);
    await expect(app.locator('.rail-item[data-view="files"]')).not.toHaveClass(/active/);

    await app.locator("#ftree-list .file[data-id]").first().click();
    await expect(app.locator('.rail-item[data-view="files"]')).toHaveClass(/active/);
    await expect(app.locator('.rail-item[data-view="index"]')).not.toHaveClass(/active/);
  });

  // Only the *root* map is what the Index rail item opens. A nested one is a file
  // in the tree like any other, so lighting Index there would claim the reader is
  // somewhere they never asked to be.
  test("a nested index.md is Files, not Index", async ({ app }) => {
    await app.locator('.rail-item[data-view="index"]').click();
    await app.locator('#ftree-list .file[data-path="services/index.md"]').click();

    await expect(app.locator("#fp-title")).toHaveText("services/index.md");
    await expect(app.locator('.rail-item[data-view="files"]')).toHaveClass(/active/);
    await expect(app.locator('.rail-item[data-view="index"]')).not.toHaveClass(/active/);
  });

  test("each view populates rather than staying on its loading placeholder", async ({ app }) => {
    await showView(app, "catalog");
    await expect(app.locator("#cat-cnt")).toHaveText("8 of 8 concepts");
    await expect(app.locator("#cat-grid .none")).toHaveCount(0);

    await showView(app, "stats");
    await expect(app.locator("#view-stats")).toContainText("8");
    await expect(app.locator("#view-stats")).toContainText("23");

    await showView(app, "tags");
    await expect(app.locator("#view-tags")).toContainText("5 distinct tags");

    await showView(app, "files");
    await expect(app.locator("#ftree-list")).toContainText("orders.md");
  });

  test("the number keys reach the same six views", async ({ app }) => {
    const keys = { 1: "graph", 3: "files", 4: "catalog", 5: "tags", 6: "stats" };
    for (const [ key, name ] of Object.entries(keys)) {
      await app.keyboard.press(key);
      expect(await view(app)).toBe(name);
    }
    // 2 is Index, which resolves to the files view (see above).
    await app.keyboard.press("2");
    expect(await view(app)).toBe("files");
  });

  test("a number key typed into a text field is text, not a shortcut", async ({ app }) => {
    await app.locator("#search").fill("");
    await app.locator("#search").press("4");
    expect(await view(app)).toBe("graph");
    await expect(app.locator("#search")).toHaveValue("4");
  });

  // Once a held-open bug (a `test.fixme` for months), now fixed and pinned. The
  // defect: dwell on another view and return to Graph, and the graph came back
  // drawn at a tenth of its size — a few dots in the top-left corner, confirmed
  // by screenshot. The cause was misdiagnosed for a long time as a resize race;
  // it was actually the boot fit. `fitGraph` reads the container's own width to
  // compute the zoom, and the one-shot fit scheduled 400ms after load
  // (setTimeout(fitGraph,400)) fires on whatever view you are on by then — leave
  // the graph inside that window and it fits a hidden 0×0 canvas, where
  // (w-2*pad)/bb.w goes negative and the zoom clamps to minZoom. The graph then
  // *stays* zoomed all the way out when you come back. The fix guards fitGraph to
  // skip a canvas with no size.
  //
  // This pins it deterministically by invoking that exact trigger — a fit while
  // the canvas is hidden — instead of racing the boot timer (which is what made
  // the old repro load-sensitive: under parallel load boot ran past 400ms, the
  // fit landed while the graph was still visible, and the bug did not reproduce).
  test("a fit fired while the graph is hidden does not collapse it on return", async ({ app }) => {
    const before = await settledBox(app);
    expect(before.w).toBeGreaterThan(300);
    const zoomBefore = await app.evaluate(() => +cy.zoom().toFixed(3));

    await showView(app, "stats");
    // Wait for Cytoscape's *own* width to reach 0, not the container's bounding
    // box. fitGraph computes the zoom from cy.width(), and that only collapses to
    // 0 once the canvas ResizeObserver's 240ms debounce has fired on the hidden
    // container — call fitGraph before that and cy.width() is still the old full
    // value, so nothing clamps and the bug hides. The RO resize is unguarded, so
    // this reaches 0 in both the fixed and the buggy build; the poll just waits.
    await expect.poll(() => app.evaluate(() => cy.width()), { timeout: 4000 }).toBe(0);
    // Fire the boot fit's exact call by hand, while genuinely hidden. Deterministic:
    // no dependence on when the 400ms timer lands relative to boot.
    await app.evaluate(() => fitGraph());
    await app.waitForTimeout(600); // let any (buggy) zoom-to-minZoom animation finish

    // The deterministic assertion, mode-independent: the hidden fit must NOT have
    // touched the zoom. Without the guard fitGraph clamps it to minZoom here (the
    // (w-2*pad)/bb.w term goes negative at cy.width()===0), and the graph is
    // already collapsed — this is what the guard prevents, in both render modes.
    // The rendered-box check below is the user-facing symptom, but it self-heals
    // in server mode when the pending boot-fit timer re-fits on return, so it is
    // the confirmation, not the guard.
    const zoomHidden = await app.evaluate(() => +cy.zoom().toFixed(3));
    expect(zoomHidden, "a fit on a hidden canvas must not clamp the zoom to minZoom").toBe(zoomBefore);

    await showView(app, "graph");
    // settledBox, not a first-good-reading poll: a collapse animates in over
    // ~200ms, so an eager poll would accept the pre-collapse value and pass.
    const after = await settledBox(app);
    expect(after.w).toBeGreaterThan(300);
    expect(after.h).toBeGreaterThan(200);
  });
});
