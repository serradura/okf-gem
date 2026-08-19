import { test, expect } from "../helpers.js";

// The index.md map layer (btn-ix), drawn over the concepts. Two things the suite
// never checked: authorship shows as form — a synthesized map's edges are
// fainter than an authored one's (edge.ixe-syn 0.3 vs edge.ixe 0.5) — and a map
// whose concepts are all filtered away leaves the canvas with them (ixVisibility).
test.describe("index layer", () => {
  test.beforeEach(async ({ app }) => {
    await app.locator("#btn-ix").click();
    await expect(app.locator("#btn-ix")).toHaveAttribute("aria-pressed", "true");
    await expect.poll(() => app.evaluate(() => cy.nodes(".ix").length)).toBeGreaterThan(0);
  });

  test("a synthesized map's edges are drawn fainter than an authored map's", async ({ app }) => {
    // services/ has an index.md (authored); datasets/ has none (synthesized).
    const op = await app.evaluate(() => {
      const syn = cy.edges(".ixe-syn"), authored = cy.edges(".ixe").not(".ixe-syn");
      const min = (c) => Math.min(...c.map((e) => parseFloat(e.style("opacity"))));
      const max = (c) => Math.max(...c.map((e) => parseFloat(e.style("opacity"))));
      return { synN: syn.length, authN: authored.length, syn: syn.length ? max(syn) : null, auth: authored.length ? min(authored) : null };
    });
    expect(op.synN, "the synthesized datasets map has edges").toBeGreaterThan(0);
    expect(op.authN, "the authored services map has edges").toBeGreaterThan(0);
    // Both were raised (.3/.5 -> .55/.85) because a dash carries about half the
    // ink of a solid line, so matching a plain edge's opacity did not match its
    // presence — at .5 these were 1.16:1 against the light canvas, invisible.
    // The gap between them is the contract; the values are what deliver it.
    expect(op.syn).toBeCloseTo(0.55, 5);
    expect(op.auth).toBeCloseTo(0.85, 5);
    expect(op.syn, "authorship still shows as form: synthesized reads fainter").toBeLessThan(op.auth);
  });

  test("a map whose concepts are all filtered away leaves the canvas", async ({ app }) => {
    // Narrow to Service — both datasets concepts fall out, so the datasets map
    // has nothing left to point at and hides too; the services map stays.
    // (This used to click Dataset, back when a type chip *hid* its type. Same
    // contract, same outcome, reached the way every other chip group is.)
    await app.locator("#btn-filters").click();
    await app.locator('#ftypes .chip[data-t="Service"]').click();

    await expect.poll(() => app.evaluate(() => cy.getElementById("ix::datasets").style("display"))).toBe("none");
    await expect.poll(() => app.evaluate(() => cy.getElementById("ix::services").style("display"))).toBe("element");
  });

  test("a synthesized map node is filled fainter than an authored one", async ({ app }) => {
    // The same authorship-as-form the edges carry, on the nodes: an authored map
    // (services/, node.ix) fills at --accent / opacity .9, a synthesized one
    // (datasets/, node.ix-syn) at --faint / opacity .2. The fill opacity tells
    // them apart.
    const res = await app.evaluate(() => {
      const syn = cy.nodes(".ix-syn");
      const authored = cy.nodes(".ix").not(".ix-syn");
      const op = (n) => parseFloat(n.style("background-opacity"));
      return {
        synN: syn.length,
        authN: authored.length,
        synOp: syn.length ? Math.max(...syn.map(op)) : null,
        authOp: authored.length ? Math.min(...authored.map(op)) : null,
      };
    });
    expect(res.synN, "datasets/ is a synthesized map node").toBeGreaterThan(0);
    expect(res.authN, "services/ is an authored map node").toBeGreaterThan(0);
    expect(res.synOp).toBeCloseTo(0.2, 5);
    expect(res.authOp).toBeCloseTo(0.9, 5);
  });
});
