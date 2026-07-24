import { test, expect, clickNode } from "../helpers.js";

// The fullscreen diagram viewer. A Mermaid block in a body renders inline, and
// clicking it opens a Panzoom viewer that re-renders the diagram *from source*
// (cloning the inline SVG lost its colours — diagram-viewer-rerenders-source),
// takes focus, and returns it on close. It leans on the Mermaid and Panzoom CDN
// bundles, lazy-loaded on first use — the same CDN dependency the whole page
// carries — so a jsdelivr hiccup fails it, which is why the CI job is
// non-blocking. adr-001-postgres.md carries the diagram.
test.describe("diagram viewer", () => {
  const openAdr = async (app) => {
    await clickNode(app, "decisions/adr-001-postgres");
    // Mermaid loads from the CDN and renders the block into an <svg>.
    await expect(app.locator("#side-body #body .mermaid svg")).toBeVisible({ timeout: 20_000 });
  };

  test("clicking a rendered diagram opens the fullscreen viewer, focused", async ({ app }) => {
    await openAdr(app);
    await app.locator("#side-body #body .mermaid").click();

    await expect(app.locator("#dgv")).toBeVisible();
    // re-rendered from source, not cloned — the viewer holds its own svg
    await expect(app.locator("#dgv-pan svg")).toBeVisible();
    await expect(app.locator("#dgv-close")).toBeFocused();
  });

  test("Escape closes the viewer and returns focus to the diagram", async ({ app }) => {
    await openAdr(app);
    const mmd = app.locator("#side-body #body .mermaid");
    await mmd.click();
    await expect(app.locator("#dgv")).toBeVisible();

    await app.keyboard.press("Escape");
    await expect(app.locator("#dgv")).toBeHidden();
    await expect(mmd).toBeFocused();
  });

  test("a rendered diagram block advertises that it opens — zoom-in cursor, accent hover", async ({ app }) => {
    // The block is a role=button that opens the fullscreen viewer, and its
    // affordances say so: cursor:zoom-in always, and the border turns to the
    // accent on hover. (The :focus-visible outline is keyboard-only and left to
    // the eye.) The colour is read through a probe so it is an rgb-to-rgb compare.
    await openAdr(app);
    const mmd = app.locator("#side-body #body .mermaid");
    expect(await mmd.evaluate((el) => getComputedStyle(el).cursor)).toBe("zoom-in");

    const accent = await app.evaluate(() => {
      const probe = document.createElement("div");
      probe.style.color = getComputedStyle(document.documentElement).getPropertyValue("--accent").trim();
      document.body.appendChild(probe);
      const c = getComputedStyle(probe).color;
      probe.remove();
      return c;
    });
    await mmd.hover();
    await expect
      .poll(() => mmd.evaluate((el) => getComputedStyle(el).borderColor.replace(/\s/g, "")))
      .toBe(accent.replace(/\s/g, ""));
  });

  test("the open viewer swallows the page's other shortcuts", async ({ app }) => {
    // #dgv is modal: while it is up the keydown handler honours Escape and
    // returns before any other binding, so a view key that would otherwise
    // navigate is swallowed. Open it on the graph, press "3" (Files) — the view
    // must stay graph with the viewer still up — then Escape, the one key the
    // guard passes, closes it.
    await openAdr(app);
    await app.locator("#side-body #body .mermaid").click();
    await expect(app.locator("#dgv")).toBeVisible();
    await expect(app.locator("#app")).toHaveAttribute("data-view", "graph");

    await app.keyboard.press("3");
    await expect(app.locator("#app")).toHaveAttribute("data-view", "graph");
    await expect(app.locator("#dgv")).toBeVisible();

    await app.keyboard.press("Escape");
    await expect(app.locator("#dgv")).toBeHidden();
  });

  test("the viewer's zoom controls scale the diagram, and reset returns it", async ({ app }) => {
    // The three toolbar buttons drive Panzoom: #dgv-in / #dgv-out step the scale,
    // #dgv-reset returns to the fit start scale. Read the scale off the pan
    // element's transform matrix (its `a` component) — zoom in grows it, zoom out
    // shrinks it, reset lands back near where it started.
    await openAdr(app);
    await app.locator("#side-body #body .mermaid").click();
    await expect(app.locator("#dgv")).toBeVisible();

    const scale = () =>
      app.locator("#dgv-pan").evaluate((el) => new DOMMatrixReadOnly(getComputedStyle(el).transform).a);
    const s0 = await scale();
    expect(s0).toBeGreaterThan(0);

    await app.locator("#dgv-in").click();
    await expect.poll(scale).toBeGreaterThan(s0);
    const s1 = await scale();

    await app.locator("#dgv-out").click();
    await expect.poll(scale).toBeLessThan(s1);

    await app.locator("#dgv-reset").click();
    await expect.poll(scale).toBeCloseTo(s0, 1);
  });

  test("toggling the theme re-renders the inline diagram in the new theme", async ({ app }) => {
    // rethemeMermaid() runs on every setTheme: it re-initializes mermaid with the
    // new theme, clears each block back to its source, and re-runs — a diagram
    // rendered under the old theme keeps its old fills without it. Read the svg
    // through the stable .mermaid div (the svg itself is replaced), so a detached
    // node mid-re-render never throws the poll.
    await openAdr(app);
    const mmd = app.locator("#side-body #body .mermaid");
    const readSvg = () => mmd.evaluate((el) => { const s = el.querySelector("svg"); return s ? s.outerHTML : ""; });
    const before = await readSvg();
    expect(before).not.toBe("");

    await app.locator("#btn-theme").click();

    // The re-run is async (mermaid.run returns a promise); poll for the fresh
    // svg — different node fills and a new mermaid-assigned id.
    await expect.poll(readSvg, { timeout: 20_000 }).not.toBe(before);
    await expect(mmd.locator("svg")).toBeVisible();
  });
});
