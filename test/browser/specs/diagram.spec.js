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
});
