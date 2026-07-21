import { test, expect, visibleNodeIds } from "../helpers.js";

// The three canvas toggles each rebuild the graph's elements, and each has to
// undo itself exactly. A mode that leaks its nodes back into the plain view is
// the classic symptom here, so every test toggles off and checks the count
// returns to 8.
test.describe("graph modes", () => {
  const total = (page) => page.evaluate(() => cy.nodes().length);
  const parents = (page) => page.evaluate(() => cy.nodes().filter((n) => n.isParent()).map((n) => n.id()).sort());

  test("cluster wraps the concepts in one compound parent per area", async ({ app }) => {
    await app.locator("#btn-cluster").click();
    await expect(app.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "true");
    expect(await parents(app)).toEqual([
      "area::(root)", "area::datasets", "area::decisions", "area::runbooks", "area::services",
    ]);
    expect(await total(app)).toBe(13);
  });

  test("cluster undoes itself completely", async ({ app }) => {
    await app.locator("#btn-cluster").click();
    await expect(app.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "true");
    await app.locator("#btn-cluster").click();
    await expect(app.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "false");
    expect(await parents(app)).toEqual([]);
    expect(await total(app)).toBe(8);
  });

  test("tree mode adds folder nodes and undoes itself", async ({ app }) => {
    await app.locator("#btn-tree").click();
    await expect(app.locator("#btn-tree")).toHaveAttribute("aria-pressed", "true");
    expect(await total(app)).toBe(13);
    // Folders are nodes, not compound parents — the tree is drawn with edges.
    expect(await parents(app)).toEqual([]);

    await app.locator("#btn-tree").click();
    expect(await total(app)).toBe(8);
  });

  test("the index layer adds the map nodes and undoes itself", async ({ app }) => {
    await app.locator("#btn-ix").click();
    await expect(app.locator("#btn-ix")).toHaveAttribute("aria-pressed", "true");
    expect(await total(app)).toBe(13);

    await app.locator("#btn-ix").click();
    await expect(app.locator("#btn-ix")).toHaveAttribute("aria-pressed", "false");
    expect(await total(app)).toBe(8);
  });

  test("a filter still applies inside cluster mode", async ({ app }) => {
    await app.locator("#btn-cluster").click();
    await app.locator("#btn-filters").click();
    await app.locator('#fareas .chip[data-area="services"]').click();
    await expect.poll(() => visibleNodeIds(app)).toEqual([ "services/billing", "services/gateway" ]);
  });

  test("switching layouts keeps every node on the canvas", async ({ app }) => {
    for (const layout of [ "grid", "circle", "concentric", "breadthfirst", "cose" ]) {
      await app.locator("#layout").selectOption(layout);
      await expect.poll(() => total(app)).toBe(8);
    }
  });

  test("fit brings the whole graph inside the viewport", async ({ app }) => {
    // Zoom right in on one corner, then fit. Asserting the zoom *number* would
    // be wrong: eight nodes fit at maxZoom, so a correct fit can legitimately
    // leave the zoom where it was. What fit promises is that every node ends
    // up inside the rendered viewport, so that is what this checks.
    await app.evaluate(() => { cy.zoom(1.6); cy.pan({ x: -400, y: -400 }); });
    await app.locator("#btn-fit").click();

    await expect.poll(() => app.evaluate(() => {
      const b = cy.elements().renderedBoundingBox();
      return b.x1 >= -1 && b.y1 >= -1 && b.x2 <= cy.width() + 1 && b.y2 <= cy.height() + 1;
    })).toBe(true);
  });
});
