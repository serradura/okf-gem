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

  test("dim reaches the cluster area boxes too", async ({ app }) => {
    // :parent sets no opacity of its own, so this one pins behaviour rather than
    // ordering — a selected concept's other-area boxes must fade with the rest.
    await app.locator("#btn-cluster").click();
    await expect(app.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "true");

    await clickNode(app, "services/gateway");
    await expect.poll(() => app.evaluate(() => cy.getElementById("services/gateway").hasClass("hl"))).toBe(true);

    const boxes = await app.evaluate(() => {
      const dim = cy.nodes(":parent").filter((n) => n.hasClass("dim"));
      return { n: dim.length, max: dim.length ? Math.max(...dim.map((n) => parseFloat(n.style("opacity")))) : null };
    });
    expect(boxes.n, "area boxes away from the selection should be dimmed").toBeGreaterThan(0);
    expect(boxes.max).toBeCloseTo(0.1, 5);
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
