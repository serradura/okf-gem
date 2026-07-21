import { test, expect, visibleNodeIds, settledBox } from "../helpers.js";

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

  test("cluster disables the layout selector, and undoing it re-enables", async ({ app }) => {
    // Cluster runs its own fcose tiling, so the layout selector is meaningless
    // while it is on — the page disables it (setClustered: layoutSel.disabled=on)
    // rather than let a pick silently do nothing.
    await expect(app.locator("#layout")).toBeEnabled();
    await app.locator("#btn-cluster").click();
    await expect(app.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "true");
    await expect(app.locator("#layout")).toBeDisabled();

    await app.locator("#btn-cluster").click();
    await expect(app.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "false");
    await expect(app.locator("#layout")).toBeEnabled();
  });

  test("tree and cluster are mutually exclusive — entering tree drops and disables cluster", async ({ app }) => {
    // The two grouped views never coexist. Entering tree both un-clusters
    // (setTree's `if(on&&clustered)setClustered(false)`) and disables the cluster
    // button (setTree: btnCluster.disabled=on), so there is no way back into
    // cluster from tree. Leaving tree re-enables it.
    await app.locator("#btn-cluster").click();
    await expect(app.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "true");

    await app.locator("#btn-tree").click();
    await expect(app.locator("#btn-tree")).toHaveAttribute("aria-pressed", "true");
    await expect(app.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "false");
    await expect(app.locator("#btn-cluster")).toBeDisabled();

    await app.locator("#btn-tree").click();
    await expect(app.locator("#btn-tree")).toHaveAttribute("aria-pressed", "false");
    await expect(app.locator("#btn-cluster")).toBeEnabled();
  });

  test("entering tree mode disables the index button and tears down the layer", async ({ app }) => {
    // The index layer and tree mode both rebuild the elements, so they cannot
    // coexist: setTree(true) disables #btn-ix and, if the layer is up, calls
    // setIxNodes(false) to remove its `.ix` nodes. Turn the layer on first so the
    // teardown has something to undo.
    await app.locator("#btn-ix").click();
    await expect(app.locator("#btn-ix")).toHaveAttribute("aria-pressed", "true");
    await expect.poll(() => app.evaluate(() => cy.nodes(".ix").length)).toBeGreaterThan(0);

    await app.locator("#btn-tree").click();
    await expect(app.locator("#btn-tree")).toHaveAttribute("aria-pressed", "true");
    await expect(app.locator("#btn-ix")).toBeDisabled();
    await expect(app.locator("#btn-ix")).toHaveAttribute("aria-pressed", "false");
    await expect.poll(() => app.evaluate(() => cy.nodes(".ix").length)).toBe(0);

    // Leaving tree mode hands the index button back.
    await app.locator("#btn-tree").click();
    await expect(app.locator("#btn-ix")).toBeEnabled();
  });

  test("a filter still applies inside cluster mode", async ({ app }) => {
    await app.locator("#btn-cluster").click();
    await app.locator("#btn-filters").click();
    await app.locator('#fareas .chip[data-area="services"]').click();
    await expect.poll(() => visibleNodeIds(app)).toEqual([ "services/billing", "services/gateway" ]);
  });

  test("clustering re-applies the active filter, and an emptied area box hides", async ({ app }) => {
    // A2-15: setClustered runs applyGraphFilter before tiling, so a filter set
    // *before* clustering still takes. A2-14: a compound area box whose concepts
    // are all filtered away hides too, while one with a survivor stays. Filter to
    // area services first, then cluster — the services box stands, datasets is gone.
    await app.locator("#btn-filters").click();
    await app.locator('#fareas .chip[data-area="services"]').click();
    await app.locator("#btn-cluster").click();
    await expect(app.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "true");

    await expect.poll(() => app.evaluate(() => cy.getElementById("area::services").style("display"))).toBe("element");
    await expect.poll(() => app.evaluate(() => cy.getElementById("area::datasets").style("display"))).toBe("none");
  });

  test("switching layouts keeps every node on the canvas", async ({ app }) => {
    for (const layout of [ "grid", "circle", "concentric", "breadthfirst", "cose" ]) {
      await app.locator("#layout").selectOption(layout);
      await expect.poll(() => total(app)).toBe(8);
    }
  });

  test("a lazy layout whose CDN fails falls back to cose", async ({ app }) => {
    // The three lazy layouts (fcose/dagre/cola) fetch their engine from the CDN
    // on first use. If that load fails, ensureLayout returns false and runLayout
    // resets the selector to cose instead of leaving a dead selection on a layout
    // that never applied. Block fcose's scripts and pick it — the selector must
    // land on cose, and the graph stays laid out.
    app.allowErrors(); // the blocked <script> logs a resource error + the loader warns
    await app.route(/cytoscape-fcose|cose-base|layout-base/, (route) => route.abort());
    await app.locator("#layout").selectOption("fcose");

    await expect.poll(() => app.locator("#layout").inputValue()).toBe("cose");
    expect(await app.evaluate(() => cy.nodes().filter((n) => n.visible()).length)).toBeGreaterThan(0);
  });

  test("a stale index-layer fetch is dropped when the toggle flips before it lands", async ({ app }, testInfo) => {
    test.skip(testInfo.project.name === "static", "server-only: the static bake reads the index from EMBED, so there is no in-flight fetch to strand");
    // The index layer's add is async: setIxNodes bumps ixSeq and fetches /index,
    // and the .then guards on (seq!==ixSeq || !ixNodes || treeMode), so a toggle
    // flipped while the fetch is in flight cancels the landing (the ixSeq ticket).
    // Hold /index, turn the layer on then straight back off, and the late
    // response must draw nothing — the layer stays empty and the button off.
    await app.route((url) => url.pathname === "/index", async (route) => {
      await new Promise((r) => setTimeout(r, 400));
      route.continue();
    });

    await app.locator("#btn-ix").click(); // on — fetch A starts, held
    await app.locator("#btn-ix").click(); // off before A lands — bumps ixSeq, ixNodes=false
    await expect(app.locator("#btn-ix")).toHaveAttribute("aria-pressed", "false");

    await app.waitForTimeout(700); // let the held fetch resolve; the guard drops it
    expect(await app.evaluate(() => cy.nodes(".ix").length)).toBe(0);
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

  test("the 0 key fits the graph", async ({ app }) => {
    // The keyboard equivalent of #btn-fit (graph view only). Let the one-shot
    // boot fit run and settle FIRST — else it re-fits during the poll below and
    // the test passes with the key doing nothing (the boot timer, not `0`, fit
    // the graph). That fit is `addEventListener('load',()=>setTimeout(fitGraph,
    // 400))`, so it is keyed off the `load` event — which waits on the CDN
    // scripts and can land well after bootGraph. Gate on readyState==='complete'
    // (load has fired), then clear the 400ms timer + its 450ms ease, then settle.
    await app.waitForFunction(() => document.readyState === "complete");
    await app.waitForTimeout(900);
    await settledBox(app);
    // Shove the graph well out of frame — and confirm it actually left, or the
    // test can't tell a fit from a no-op — then 0, and assert it lands back in.
    await app.evaluate(() => { cy.zoom(3); cy.pan({ x: -3000, y: -3000 }); });
    const outside = await app.evaluate(() => {
      const b = cy.elements().renderedBoundingBox();
      return b.x2 < 0 || b.y2 < 0 || b.x1 > cy.width() || b.y1 > cy.height();
    });
    expect(outside, "the artificial pan must push the graph off-screen").toBe(true);

    await app.keyboard.press("0");
    await expect.poll(() => app.evaluate(() => {
      const b = cy.elements().renderedBoundingBox();
      return b.x1 >= -1 && b.y1 >= -1 && b.x2 <= cy.width() + 1 && b.y2 <= cy.height() + 1;
    })).toBe(true);
  });

  test("tree edges render dashed and folder nodes carry the accent", async ({ app }) => {
    // The tree picture's two visual contracts: folder→child edges are dashed
    // (edge.tree line-style), and folder nodes are accent squares like maps
    // (node.dir background-color = --accent, round-rectangle). The colour is
    // read through a probe element so the comparison is rgb-to-rgb.
    await app.locator("#btn-tree").click();
    await expect(app.locator("#btn-tree")).toHaveAttribute("aria-pressed", "true");
    await expect.poll(() => app.evaluate(() => cy.getElementById("dir::services").length)).toBe(1);

    const res = await app.evaluate(() => {
      const probe = document.createElement("div");
      probe.style.color = getComputedStyle(document.documentElement).getPropertyValue("--accent").trim();
      document.body.appendChild(probe);
      const accent = getComputedStyle(probe).color;
      probe.remove();
      const edges = cy.edges(".tree");
      const dir = cy.getElementById("dir::services");
      return {
        edgeCount: edges.length,
        line: edges.length ? edges[0].style("line-style") : null,
        bg: dir.style("background-color"),
        shape: dir.style("shape"),
        accent,
      };
    });
    expect(res.edgeCount, "tree mode draws folder→child edges").toBeGreaterThan(0);
    expect(res.line).toBe("dashed");
    // Cytoscape returns rgb() without spaces, the DOM with them — same colour.
    expect(res.bg.replace(/\s/g, "")).toBe(res.accent.replace(/\s/g, ""));
    expect(res.shape).toBe("round-rectangle");
  });

  test("a folder node is unselectable and exempt from the graph filter", async ({ app }) => {
    // In tree mode the folder-as-node is chrome, not a concept. Tapping it
    // emphasises and shows the directory but never reaches select(), so no #hash
    // lands (a concept tap writes one — the emphasis/inspector specs pin that).
    // And applyGraphFilter skips `.dir`, so a term nothing matches empties the
    // concepts while the folder stands.
    await app.locator("#btn-tree").click();
    await expect.poll(() => app.evaluate(() => cy.getElementById("dir::services").length)).toBe(1);

    await app.evaluate(() => cy.getElementById("dir::services").emit("tap"));
    await expect.poll(() => app.evaluate(() => cy.getElementById("dir::services").hasClass("hl"))).toBe(true);
    expect(await app.evaluate(() => location.hash)).toBe("");

    await app.locator("#search").fill("zzzznotathing");
    await expect.poll(() => app.evaluate(() => cy.getElementById("services/gateway").style("display"))).toBe("none");
    expect(await app.evaluate(() => cy.getElementById("dir::services").style("display"))).toBe("element");
  });
});
