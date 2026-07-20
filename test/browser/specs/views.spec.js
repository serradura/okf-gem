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

  // KNOWN BUG — held open, but as `fixme`, not `fail`. The distinction is
  // load-sensitivity: the collapse is a race between setView's return-resize
  // rAF and the container getting its size back, and whether it lands depends
  // on how contended the event loop is. Run alone it reproduces every time; run
  // under the full suite's five parallel workers the rAF is delayed enough that
  // the container is already sized when it fires, so the graph comes back fine
  // and a `test.fail` reports an *unexpected pass*. That is the same flake a
  // held-open marker is supposed to remove, not add — a coin-flip red teaches
  // the maintainer to ignore the signal it exists to raise.
  //
  // So this is `fixme`: the bug stays on the record and in the report, the body
  // below documents exactly how to reproduce it (flip to `test.fail` and run
  // this file alone to watch it go red), and the suite stays deterministically
  // green. It joins one-camera-move as a real defect with no external observable
  // stable enough to gate on — both wait on the same fix: instrumentation in the
  // page, or the resize race closed at the source. Delete this marker then.
  //
  // The defect itself: dwell ~300ms or more on any other view and come back, and
  // the graph returns drawn at about a tenth of its size — a few dots in the
  // top-left corner, confirmed by screenshot. Both resize paths run and neither
  // is sufficient: setView's requestAnimationFrame(cy.resize()) fires while the
  // container is still 0×0, and the canvas ResizeObserver's 240ms debounce has
  // already cached the collapsed viewport by then.
  test.fixme("leaving and returning to the graph redraws it at full size", async ({ app }) => {
    // Cytoscape measures a hidden container as 0×0 and keeps that as its
    // renderer viewport; without a resize() on the way back the graph returns
    // drawn into a few dozen pixels at the origin.
    //
    // Assert the *rendered* bounding box, not cy.width() and not the #cy
    // element's box: both of those read the live container and stay correct
    // even while the render is collapsed, so a test on either passes with
    // every resize path disabled — it can never fail, which makes it worse
    // than no test.
    const before = await settledBox(app);
    expect(before.w).toBeGreaterThan(300);

    await showView(app, "stats");
    // Two preconditions, both required, neither assumable. The container has
    // to actually reach 0×0, *and* the canvas ResizeObserver's 240ms debounce
    // has to fire while it is there — that is what caches the 0×0 viewport.
    // A faster round trip leaves the graph fine no matter what the view
    // switch does, so a test without this dwell passes with every resize path
    // deleted.
    await app.waitForFunction(() => document.getElementById("cy").getBoundingClientRect().width === 0);
    await app.waitForTimeout(600);

    await showView(app, "graph");

    // settledBox, not a first-good-reading poll: the collapse takes ~200ms to
    // show, so an eager poll would accept the pre-collapse value and pass.
    const after = await settledBox(app);
    expect(after.w).toBeGreaterThan(300);
    expect(after.h).toBeGreaterThan(200);
  });
});
