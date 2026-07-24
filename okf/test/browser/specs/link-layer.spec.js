import { bundleMapPage } from "../paths.js";
import { test, expect, base, bootGraph, clickNode } from "../helpers.js";

// The link layer: how many arrows the graph draws. Three settings on a
// segmented control (all / spine / none), a selected concept's own links always
// shown in full, and a density-driven default that opens a thicket on its spine
// rather than all of it. `test/integration/render/` proves the control is
// *emitted*; only this proves it *works* — the class it exists to catch is a
// filter that stops composing or a handler that throws where the DOM still
// looks plausible. (links.spec.js is a different thing: body-link resolution.)
//
// The main fixture (8 concepts, 23 links, undirected degree 5.75) sits just
// under the auto-spine threshold, so `app` boots on `all` — a known start the
// interactive assertions below depend on. The dense default has its own block
// on a fixture that clears the threshold.

// Link edges only. In the default graph view there are no `tree`/`ixe` edges
// (those belong to file-tree and index modes), so every edge is a link — but
// filter anyway, so a future change that leaves one behind does not quietly
// inflate these counts.
const linkStats = (page) => page.evaluate(() => {
  const links = cy.edges().not(".tree").not(".ixe");
  return {
    mode: linkMode,
    total: links.length,
    hidden: links.filter((e) => e.hasClass("linkhid")).length,
    spine: links.filter((e) => e.data("cut") === 0).length,
  };
});

const checked = (page) =>
  page.locator('#links [data-links][aria-checked="true"]').getAttribute("data-links");

test.describe("the link layer — three amounts of wiring", () => {
  test("boots on all: every link drawn, `all` the checked segment", async ({ app }) => {
    const s = await linkStats(app);
    expect(s.mode).toBe("all");
    expect(s.hidden).toBe(0);
    expect(s.total).toBe(23);
    expect(await checked(app)).toBe("all");
  });

  test("spine hides exactly the non-spine links, keeps the backbone", async ({ app }) => {
    await app.locator('#links [data-links="spine"]').click();
    const s = await linkStats(app);
    expect(s.mode).toBe("spine");
    // 11 of 23 are cut===0 (the spine); the other 12 hide.
    expect(s.spine).toBe(11);
    expect(s.hidden).toBe(s.total - s.spine);
    expect(await checked(app)).toBe("spine");
  });

  test("none hides every link; all brings them all back", async ({ app }) => {
    await app.locator('#links [data-links="none"]').click();
    let s = await linkStats(app);
    expect(s.mode).toBe("none");
    expect(s.hidden).toBe(s.total);

    await app.locator('#links [data-links="all"]').click();
    s = await linkStats(app);
    expect(s.mode).toBe("all");
    expect(s.hidden).toBe(0);
  });

  test("selecting a concept reveals its own links in full, whatever the setting", async ({ app }) => {
    // The whole argument for hiding links: they stop being noise and become the
    // answer the moment a concept is selected. In `none` every link is hidden —
    // then a selection must bring that concept's own back.
    await app.locator('#links [data-links="none"]').click();
    expect((await linkStats(app)).hidden).toBe(23);

    await clickNode(app, "services/billing");
    const revealed = await app.evaluate(() =>
      cy.getElementById("services/billing").connectedEdges().not(".tree").not(".ixe")
        .every((e) => !e.hasClass("linkhid")));
    expect(revealed, "the selected concept's links are all shown").toBe(true);

    // …and only that concept's — a link touching neither the selection nor its
    // neighbours stays hidden, so the reveal is a spotlight, not a reset to all.
    const others = await app.evaluate(() => {
      const own = cy.getElementById("services/billing").connectedEdges();
      return cy.edges().not(".tree").not(".ixe").not(own).some((e) => e.hasClass("linkhid"));
    });
    expect(others, "links elsewhere stay hidden").toBe(true);
  });

  test("the segments are a radio group the arrow keys drive", async ({ app }) => {
    const seg = app.locator("#links");
    await expect(seg).toHaveAttribute("role", "radiogroup");

    await app.locator('#links [data-links="all"]').focus();
    await app.keyboard.press("ArrowRight");
    expect(await checked(app)).toBe("spine");
    expect((await linkStats(app)).mode).toBe("spine");

    await app.keyboard.press("ArrowRight");
    expect(await checked(app)).toBe("none");

    // Wraps, and exactly one segment is ever checked.
    await app.keyboard.press("ArrowRight");
    expect(await checked(app)).toBe("all");
    await expect(app.locator('#links [aria-checked="true"]')).toHaveCount(1);
  });
});

test.describe("the link layer — the dense default opens on the spine", () => {
  test("a bundle over the density threshold boots on spine, not the thicket", async ({ dense }) => {
    // densegraph is 110 concepts / 880 links, undirected degree 16 — well over
    // the threshold. It must open with the arrows already thinned to the spine,
    // or the feature's whole reason (don't greet a reader with a thicket) is
    // unmet. The edges are hidden, never removed: cy still holds all 880 (the
    // boot-split spec pins that), the link layer only sets `linkhid`.
    const s = await linkStats(dense);
    expect(s.mode).toBe("spine");
    expect(await checked(dense)).toBe("spine");
    expect(s.total).toBe(880);
    expect(s.hidden).toBe(s.total - s.spine);
    expect(s.hidden).toBeGreaterThan(0);
  });

  test("a browsable bundle under the threshold is left on all", async ({ app }) => {
    // The other half of the contract: auto-spine must not fire on a graph a
    // reader can already take in. The main fixture (degree 5.75) is that graph.
    expect((await linkStats(app)).mode).toBe("all");
  });
});

test.describe("the link layer — `--map` opens on none with the boxes on", () => {
  // A dedicated fixture in both projects would prove nothing extra: `--map`
  // bakes `map_json=true` into the template the same way live or static, and the
  // boot code it triggers is one rAF. So this runs on the static --map page
  // only. It carries its own console-error watch because the payload it guards
  // is exactly a throw: the map boot once hit a binding in its temporal dead
  // zone and the ReferenceError silently unbound every statement after it, and
  // the page still came up looking almost right.
  const mapTest = base.extend({
    map: async ({ page }, use) => {
      const errors = [];
      page.on("pageerror", (e) => errors.push(String(e)));
      page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
      await page.addInitScript(() => { try { localStorage.setItem("okf-hello", "1"); } catch (e) {} });
      await page.goto(`file://${bundleMapPage}`);
      await bootGraph(page);
      await use(page);
      if (errors.length) throw new Error(`page reported ${errors.length} error(s):\n  ${errors.join("\n  ")}`);
    },
  });

  mapTest("no arrows, directories boxed, and the rest of the page still bound", async ({ map }) => {
    // none + clustered, applied on the boot rAF.
    await expect.poll(() => map.evaluate(() => linkMode), { timeout: 10_000 }).toBe("none");
    expect(await map.evaluate(() => cy.edges().not(".tree").not(".ixe").every((e) => e.hasClass("linkhid")))).toBe(true);
    expect(await map.evaluate(() => clustered)).toBe(true);
    expect(await checked(map)).toBe("none");

    // The TDZ regression's tell was not the map itself but the statements after
    // it: the boot fit, the palette, the keyboard map — all silently unbound. If
    // the rAF threw, one of those globals would be missing. Probe one.
    expect(await map.evaluate(() => typeof MIN_ZOOM)).toBe("number");
  });
});
