import { test, expect, clickNode } from "../helpers.js";

// Dim and highlight are Cytoscape *states*, and the whole reason they read at
// all is that their style rules are declared last in styleSheet(): Cytoscape
// resolves equal-specificity selectors by array order, so a base look declared
// after `.dim` silently beats it. `edge.tree` and `edge.ixe` each set their own
// opacity, so before the fix (138b705) a selected map or tree left its dashed
// edges at half opacity across the whole canvas and nothing read as emphasised.
//
// These assert the *resolved* opacity of a dimmed edge, not the class alone —
// the class is present either way; only the resolved value flips when the order
// is wrong. Move the `.dim`/`.hl` block back above `edge.tree`/`edge.ixe` in
// styleSheet() and the first two go red (0.1 → 0.7 / 0.5).
test.describe("emphasis (dim + highlight)", () => {
  // The resolved opacity of every dimmed edge in a class, plus the count — read
  // in one pass so the assertion sees exactly what Cytoscape painted.
  const dimmedEdges = (page, cls) =>
    page.evaluate((c) => {
      const dim = cy.edges(c).filter((e) => e.hasClass("dim"));
      return { n: dim.length, max: dim.length ? Math.max(...dim.map((e) => parseFloat(e.style("opacity")))) : null };
    }, cls);

  test("dim outranks a tree edge's own opacity", async ({ app }) => {
    await app.locator("#btn-tree").click();
    await expect(app.locator("#btn-tree")).toHaveAttribute("aria-pressed", "true");

    // Select a leaf: its own folder edge stays lit, every other tree edge dims.
    await clickNode(app, "services/gateway");
    await expect.poll(() => app.evaluate(() => cy.getElementById("services/gateway").hasClass("hl"))).toBe(true);

    const dim = await dimmedEdges(app, ".tree");
    expect(dim.n, "some tree edges should be dimmed away from the selection").toBeGreaterThan(0);
    // 0.1 = `.dim`; a value of 0.7 means `edge.tree` won and dim never applied.
    expect(dim.max).toBeCloseTo(0.1, 5);
  });

  test("dim outranks an index-layer edge's own opacity", async ({ app }) => {
    await app.locator("#btn-ix").click();
    await expect(app.locator("#btn-ix")).toHaveAttribute("aria-pressed", "true");
    // The layer is added from /index asynchronously.
    await expect.poll(() => app.evaluate(() => cy.nodes(".ix").length)).toBeGreaterThan(0);

    await clickNode(app, "services/gateway");
    await expect.poll(() => app.evaluate(() => cy.getElementById("services/gateway").hasClass("hl"))).toBe(true);

    const dim = await dimmedEdges(app, ".ixe");
    expect(dim.n, "index edges to other concepts should be dimmed").toBeGreaterThan(0);
    // 0.1 = `.dim`; 0.5 (or 0.3 for a synthesized map) means `edge.ixe` won.
    expect(dim.max).toBeCloseTo(0.1, 5);
  });

  test("selection stays legible in cluster mode", async ({ app }) => {
    // The subtle one, and a real bug this caught: in cluster mode every concept
    // lives inside a compound area box, and a compound parent's opacity cascades
    // to the nodes inside it. Dimming the boxes therefore fades the whole graph —
    // including the selected node and its neighbours, which were deliberately
    // un-dimmed. So emphasis must read the *effective* (on-screen) opacity, which
    // includes the parent's, not the node's own: the selection and its
    // neighbourhood have to stay bright while only the rest recedes.
    await app.locator("#btn-cluster").click();
    await expect(app.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "true");
    await expect.poll(() => app.evaluate(() => cy.nodes(":parent").length)).toBeGreaterThan(0);

    await clickNode(app, "services/gateway");
    await expect.poll(() => app.evaluate(() => cy.getElementById("services/gateway").hasClass("hl"))).toBe(true);

    const op = await app.evaluate(() => ({
      selected: cy.getElementById("services/gateway").effectiveOpacity(),
      neighbour: cy.getElementById("services/billing").effectiveOpacity(), // linked to gateway
      unrelated: cy.getElementById("datasets/customers").effectiveOpacity(), // a different area
    }));
    expect(op.selected, "the selected node must not be faded by its own area box").toBeGreaterThan(0.9);
    expect(op.neighbour, "a neighbour must stay lit").toBeGreaterThan(0.9);
    expect(op.unrelated, "an unrelated concept still recedes").toBeLessThan(0.2);
  });

  // The tap handler routes three node kinds through the *same* focusNode: a
  // concept, a folder (`.dir`) in tree mode, and a map (`.ix`) in the index
  // layer. The concept path is covered above; these two pin that a folder and a
  // map emphasise identically — hl on the tapped node, dim (with the resolved
  // 0.1 opacity) on an unrelated leaf. Gut the `.dir`/`.ix` branch of the tap
  // handler and these go red.
  test("tapping a folder node in tree mode emphasises it", async ({ app }) => {
    await app.locator("#btn-tree").click();
    await expect(app.locator("#btn-tree")).toHaveAttribute("aria-pressed", "true");
    await expect.poll(() => app.evaluate(() => cy.getElementById("dir::services").length)).toBe(1);

    await app.evaluate(() => cy.getElementById("dir::services").emit("tap"));
    await expect.poll(() => app.evaluate(() => cy.getElementById("dir::services").hasClass("hl"))).toBe(true);

    const op = await app.evaluate(() => ({
      folder: cy.getElementById("dir::services").effectiveOpacity(),
      unrelated: cy.getElementById("datasets/customers").effectiveOpacity(),
    }));
    expect(op.folder, "the tapped folder must stay lit").toBeGreaterThan(0.9);
    expect(op.unrelated, "a leaf outside the folder's neighbourhood recedes").toBeLessThan(0.2);
  });

  test("tapping a map node in the index layer emphasises it", async ({ app }) => {
    await app.locator("#btn-ix").click();
    await expect(app.locator("#btn-ix")).toHaveAttribute("aria-pressed", "true");
    await expect.poll(() => app.evaluate(() => cy.getElementById("ix::services").length)).toBe(1);

    await app.evaluate(() => cy.getElementById("ix::services").emit("tap"));
    await expect.poll(() => app.evaluate(() => cy.getElementById("ix::services").hasClass("hl"))).toBe(true);

    const op = await app.evaluate(() => ({
      map: cy.getElementById("ix::services").effectiveOpacity(),
      unrelated: cy.getElementById("datasets/customers").effectiveOpacity(),
    }));
    expect(op.map, "the tapped map must stay lit").toBeGreaterThan(0.9);
    expect(op.unrelated, "a concept outside the map's neighbourhood recedes").toBeLessThan(0.2);
  });

  test("the selected node carries the highlight border", async ({ app }) => {
    // The other half of the state block: `.hl` is a 3px accent border over the
    // concept's borderless base. Pins that selection is visible at all.
    await clickNode(app, "services/gateway");
    await expect.poll(() => app.evaluate(() => {
      const n = cy.getElementById("services/gateway");
      return n.hasClass("hl") ? parseFloat(n.style("border-width")) : 0;
    })).toBe(3);
  });
});
