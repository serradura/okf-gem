import { test, expect } from "../helpers.js";

// The camera and layout bugs in the history are timing, not logic, and the
// current suite is least equipped to see them. The trap is expect.poll: it
// passes on the first frame that satisfies, and a layout animation passes
// through states that momentarily satisfy before it settles — so a poll greens
// against the bug. These read the *settled* state instead (positions stable
// across two samples), the way settledBox does for the canvas box.
test.describe("camera + layout", () => {
  test("un-clustering restores the chosen layout, not a hardcoded cose", async ({ app }) => {
    // adf96ff — un-clustering hardcoded a cose run and threw away whichever
    // layout the select was on. Every attempt to read this from the *result*
    // (exact positions, row count) proved too timing-fragile — fcose lazy-loads
    // from the CDN before clustering and the whole sequence lands at different
    // moments in the two render modes. So watch the cause, not the effect: spy on
    // cy.layout and record which layout un-clustering actually runs. It has to be
    // the selected grid, never a hardcoded cose. Synchronous, so no animation to
    // race.
    await app.locator("#layout").selectOption("grid");
    await app.locator("#btn-cluster").click();
    await expect(app.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "true");
    await expect.poll(() => app.evaluate(() => cy.nodes(":parent").length)).toBeGreaterThan(0);

    await app.evaluate(() => {
      window.__layouts = [];
      const orig = cy.layout.bind(cy);
      cy.layout = (opts) => { window.__layouts.push(opts && opts.name); return orig(opts); };
    });

    await app.locator("#btn-cluster").click();
    await expect(app.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "false");

    // The teardown runs runLayout(layoutSel.value); wait for that call, then
    // prove it was grid and nothing hardcoded cose in its place.
    await expect.poll(() => app.evaluate(() => window.__layouts)).toContain("grid");
    expect(await app.evaluate(() => window.__layouts),
      "un-clustering must re-run the selected grid, not a hardcoded cose").not.toContain("cose");
    await expect(app.locator("#layout")).toHaveValue("grid");
  });

  test("index layer to tree mode lands cleanly in one click", async ({ app }) => {
    // 456aa79 — two layouts raced one canvas and the tree landed wrong until a
    // second click; a stale /index promise could also drop map nodes into the
    // tree. After one click the map layer is gone and the tree is fitted.
    await app.locator("#btn-ix").click();
    await expect(app.locator("#btn-ix")).toHaveAttribute("aria-pressed", "true");
    await expect.poll(() => app.evaluate(() => cy.nodes(".ix").length)).toBeGreaterThan(0);

    await app.locator("#btn-tree").click();
    await expect(app.locator("#btn-tree")).toHaveAttribute("aria-pressed", "true");
    await expect(app.locator("#btn-ix")).toBeDisabled();
    // no map node leaked past the switch (removed synchronously by setTree)…
    await expect.poll(() => app.evaluate(() => cy.nodes(".ix").length)).toBe(0);
    expect(await app.evaluate(() => cy.nodes(".dir").length), "the tree drew its folders").toBeGreaterThan(0);
    // …and it settles fitted inside the viewport rather than mislaid off-canvas.
    // Polled, not settle-then-read: a transient mid-fit frame can hold still for
    // two samples and read as a settled miss.
    await expect.poll(() => app.evaluate(() => {
      const b = cy.elements(":visible").renderedBoundingBox(), w = cy.width(), h = cy.height();
      return b.x1 >= -2 && b.y1 >= -2 && b.x2 <= w + 2 && b.y2 <= h + 2;
    }), { timeout: 8000 }).toBe(true);
  });

  // Deliberately NOT here: a test for one-camera-move-per-click (ed6c0af). Three
  // observables were built and probed against a mutation that guts centerOn
  // (immediate pan, no defer/stop/resize coordination):
  //   - settled node position: identical either way (~190px off centre), because
  //     the panel's cy.resize() re-centres the whole graph and fires last.
  //   - cy 'pan' event bursts (a >120ms gap starts a new burst): one burst both
  //     ways — the two moves chain without a clean gap.
  //   - the span of pan-motion: ~450ms fixed, but under mutation it only
  //     *sometimes* stretches to ~900ms — the second move (the resize re-centre)
  //     is itself timing-dependent and often absent, so the span test greened
  //     against the gutted code.
  // The fix is sub-frame smoothing the page emits no signal to observe
  // deterministically; a test for it would green with centerOn deleted, which is
  // worse than none. This is the one honest hole, recorded in COVERAGE.md.
});
