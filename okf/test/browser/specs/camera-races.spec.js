import { test, expect } from "../helpers.js";

// The camera and layout bugs in the history are timing, not logic, and the
// current suite is least equipped to see them. The trap is expect.poll: it
// passes on the first frame that satisfies, and a layout animation passes
// through states that momentarily satisfy before it settles — so a poll greens
// against the bug. These read the *settled* state instead (positions stable
// across two samples), the way settledBox does for the canvas box.
test.describe("camera + layout", () => {
  // The force layouts used to animate every tick of the simulation — the visible
  // "bounce". On a small graph that reads as the layout settling; at a few
  // hundred concepts it is hundreds of full re-renders a second and the browser
  // stops keeping up. Watch the cause (the options handed to cy.layout), because
  // the effect is a frame rate no assertion can read.
  const spy = (page) => page.evaluate(() => {
    window.__opts = [];
    const orig = cy.layout.bind(cy);
    cy.layout = (o) => { window.__opts.push({ name: o && o.name, animate: o && o.animate }); return orig(o); };
  });

  test("a force layout never animates per tick — it settles, then moves once", async ({ app }) => {
    await spy(app);
    await app.locator("#layout").selectOption("cose");

    await expect.poll(() => app.evaluate(() => window.__opts.map((o) => o.name))).toContain("cose");
    const run = await app.evaluate(() => window.__opts.find((o) => o.name === "cose"));
    expect(run.animate, "animate:true is the per-tick bounce; 'end' transitions once").not.toBe(true);
    expect(run.animate).toBe("end");
  });

  test("past a few hundred nodes the transition is dropped entirely", async ({ app }) => {
    // The fixture is 8 concepts, so the branch is unreachable without building
    // the condition it turns on: add enough nodes that the page is in the size
    // class the complaint came from, then ask for a layout.
    await app.evaluate(() => {
      const add = [];
      for (let i = 0; i < 320; i++) add.push({ group: "nodes", data: { id: `synthetic::${i}`, title: `n${i}` } });
      cy.add(add);
    });
    await spy(app);
    await app.locator("#layout").selectOption("cose");

    await expect.poll(() => app.evaluate(() => window.__opts.map((o) => o.name))).toContain("cose");
    const run = await app.evaluate(() => window.__opts.find((o) => o.name === "cose"));
    expect(run.animate, "a big graph gets no transition at all").toBe(false);
  });

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

  // one-camera-move-per-click (ed6c0af). This was the suite's documented hole:
  // three *end-state* observables were probed against a mutation that guts
  // centerOn (immediate pan, no defer) and none discriminated — settled position
  // is identical either way (the panel's cy.resize() re-centres last), pan-event
  // bursts chain into one, and the motion span only sometimes stretched. The
  // fix's contract is not where the node lands but *when and how often* the pan
  // commits, and the end state cannot see that. So the page now carries a
  // test-only counter (window.__camCenters), bumped just before each committed
  // centre-pan, and this reads it at the one moment that discriminates: the
  // synchronous instant right after the tap, before the 260ms defer could fire.
  test("a panel-opening click commits exactly one centre-pan, and it is the deferred one", async ({ app }) => {
    // Precondition the whole test rests on: the panel is closed, so this first
    // click is the panel-opening one that takes centerOn's deferred branch. A
    // click with the panel already open pans immediately by design — a different
    // path, not this bug.
    await expect(app.locator(".graph-body")).toHaveAttribute("data-side", "hidden");
    const id = await app.evaluate(() => cy.nodes().filter((n) => !n.isParent())[0].id());

    // Emit the tap and read the counter in the SAME evaluate, so the read lands
    // synchronously after the tap handler ran (select → focusNode → centerOn,
    // which only *schedules* setTimeout(go,260)). Fixed code: the pan is deferred,
    // so nothing has committed yet and the counter is still 0. The gutted
    // immediate-pan would already read 1 here — this is the assertion that fails
    // against the bug, and the reason an end-state test could not.
    const committedSynchronously = await app.evaluate((nodeId) => {
      cy.getElementById(nodeId).emit("tap");
      return window.__camCenters;
    }, id);
    expect(committedSynchronously, "the pan must be deferred, not fired on the click").toBe(0);

    // The deferred pan then commits — exactly once (the ~260ms defer elapses).
    await expect.poll(() => app.evaluate(() => window.__camCenters), { timeout: 4000 }).toBe(1);

    // And it never doubles: no immediate pan the settling panel then shifts a
    // second time. Wait past the defer and the animation and confirm it held at 1.
    await app.waitForTimeout(700);
    expect(await app.evaluate(() => window.__camCenters),
      "one committed pan per click, never the double movement").toBe(1);
  });
});
