import { test, expect, bootGraph, showView } from "../helpers.js";

// The inspector splitter: drag to resize, persisted, double-click to reset, and
// a restore clamped to the viewport so a width dragged on a desktop cannot
// swallow a phone. The panel width is --side-w, which reads --side-w-user (the
// dragged/stored value) and falls back to 380px.
test.describe("inspector splitter (1280px)", () => {
  const openStored = async (app, px) => {
    await app.evaluate((w) => localStorage.setItem("okf-side-w", w), String(px));
    await app.reload();
    await bootGraph(app);
    await app.locator("#btn-panel").click(); // open the inspector at its stored width
    await expect(app.locator(".graph-body")).toHaveAttribute("data-side", "default");
  };

  test("a stored width is restored when the panel opens", async ({ app }) => {
    await openStored(app, 520);
    await expect(app.locator("#side")).toHaveCSS("width", "520px");
  });

  test("a stored width wider than the viewport is clamped to 70%", async ({ app }) => {
    // 5000px must not swallow the 1280px window — restore clamps to round(0.7*w).
    await openStored(app, 5000);
    await expect(app.locator("#side")).toHaveCSS("width", "896px");
  });

  test("double-clicking the handle resets to the default width", async ({ app }) => {
    await openStored(app, 520);
    await expect(app.locator("#side")).toHaveCSS("width", "520px");
    await app.locator("#side-resizer").dblclick();
    await expect(app.locator("#side")).toHaveCSS("width", "380px");
  });

  test("dragging the handle widens the panel", async ({ app }) => {
    await app.locator("#btn-panel").click();
    await expect(app.locator("#side")).toHaveCSS("width", "380px");

    const h = await app.locator("#side-resizer").boundingBox();
    await app.mouse.move(h.x + h.width / 2, h.y + h.height / 2);
    await app.mouse.down();
    await app.mouse.move(h.x - 180, h.y + h.height / 2, { steps: 6 }); // drag left = wider
    await app.mouse.up();

    const w = await app.locator("#side").evaluate((el) => Math.round(el.getBoundingClientRect().width));
    expect(w, "dragging the handle left should widen the inspector").toBeGreaterThan(500);
  });

  // The panel width transitions over .22s, so read it only once it has settled.
  const settledWidth = async (app) => {
    let prev = -1;
    for (let i = 0; i < 25; i++) {
      await app.waitForTimeout(80);
      const w = await app.locator("#side").evaluate((el) => Math.round(el.getBoundingClientRect().width));
      if (w === prev) return w;
      prev = w;
    }
    return prev;
  };

  test("a dragged width persists across a reload", async ({ app }) => {
    await app.locator("#btn-panel").click();
    await expect(app.locator("#side")).toHaveCSS("width", "380px");

    const h = await app.locator("#side-resizer").boundingBox();
    await app.mouse.move(h.x + h.width / 2, h.y + h.height / 2);
    await app.mouse.down();
    await app.mouse.move(h.x - 160, h.y + h.height / 2, { steps: 6 });
    await app.mouse.up();
    const dragged = await settledWidth(app);
    expect(dragged).toBeGreaterThan(500);

    // the drag end wrote okf-side-w; the reloaded page restores it
    await app.reload();
    await bootGraph(app);
    await app.locator("#btn-panel").click();
    const restored = await settledWidth(app);
    expect(Math.abs(restored - dragged), "the reloaded width should match the dragged one").toBeLessThan(3);
  });
});

test.describe("file-tree splitter (1280px)", () => {
  test("dragging the handle widens the tree column", async ({ app }) => {
    await showView(app, "files");
    await expect(app.locator("#ftree-list")).toContainText("orders.md");

    const before = await app.locator(".ftree").evaluate((el) => Math.round(el.getBoundingClientRect().width));
    const h = await app.locator("#ftree-resizer").boundingBox();
    await app.mouse.move(h.x + h.width / 2, h.y + h.height / 2);
    await app.mouse.down();
    await app.mouse.move(h.x + 140, h.y + h.height / 2, { steps: 6 }); // drag right = wider
    await app.mouse.up();

    const after = await app.locator(".ftree").evaluate((el) => Math.round(el.getBoundingClientRect().width));
    expect(after, "dragging the handle right should widen the tree column").toBeGreaterThan(before + 80);
  });
});
