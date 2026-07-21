import { test, expect, showView } from "../helpers.js";

// collapsedDirs, foldedByRoot and the .tree-min class are three pieces of state
// that must agree, and the history shows them disagreeing repeatedly: a search
// that force-expanded every folder left the fold clicks dead (0e9eab8),
// "collapse all" folded the root and hid the top-level folders (4b80b80), and
// closing the root left a single row with the button that closed it unable to
// bring the tree back (2163bfe, aeef15b). These pin the corrected machine.
test.describe("file tree — collapse (desktop)", () => {
  test.beforeEach(async ({ app }) => {
    await showView(app, "files");
    await expect(app.locator("#ftree-list")).toContainText("orders.md");
  });

  test("a collapsed folder stays collapsed while a search is active", async ({ app }) => {
    const services = app.locator('.ffolder[data-dir="services"]');
    await expect(app.locator('.file[data-id="services/billing"]')).toBeVisible();

    await services.click();
    await expect(services).toHaveClass(/closed/);
    // Closed folders render as their header alone — the subtree is gone.
    await expect(app.locator('.file[data-id="services/billing"]')).toHaveCount(0);

    // A filter that matches inside the closed folder must not force it open —
    // the header still shows (a collapsed group is never a hidden match), but
    // the fold is honoured, so the match stays tucked away.
    await app.locator("#search").fill("billing");
    await expect(services).toHaveClass(/closed/);
    await expect(app.locator('.file[data-id="services/billing"]')).toHaveCount(0);
  });

  test("collapse-all folds every folder inside the root but leaves the root open", async ({ app }) => {
    const root = app.locator('.ffolder.root[data-dir="."]');
    const services = app.locator('.ffolder[data-dir="services"]');
    const datasets = app.locator('.ffolder[data-dir="datasets"]');

    await app.locator("#ftree-foldall").click();

    // Every top-level folder header is collapsed…
    await expect(services).toHaveClass(/closed/);
    await expect(datasets).toHaveClass(/closed/);
    // …but the root stays open, so those headers are still on screen — the one
    // thing a reader wants left standing after "collapse all".
    await expect(root).not.toHaveClass(/closed/);
    await expect(services).toBeVisible();
    await expect(app.locator('.file[data-id="services/billing"]')).toHaveCount(0);
    await expect(app.locator("#ftree-foldall")).toHaveClass(/all-closed/);

    // The same button now expands everything, root included.
    await app.locator("#ftree-foldall").click();
    await expect(services).not.toHaveClass(/closed/);
    await expect(app.locator('.file[data-id="services/billing"]')).toBeVisible();
  });

  test("collapse-all stays reversible after the root was closed by hand", async ({ app }) => {
    // The fold controls read every folder from the tree walk, not just the ones
    // on screen — so closing the root (which hides all the sub-headers) does not
    // strand them: expand-all still knows they exist and brings them back.
    await app.locator('.ffolder.root[data-dir="."]').click();
    await expect(app.locator('.ffolder[data-dir="services"]')).toHaveCount(0); // hidden under closed root
    await expect(app.locator("#ftree-foldall")).toBeEnabled();

    // Fold-all then expand-all round-trips the whole tree back to open.
    await app.locator("#ftree-foldall").click();
    await app.locator("#ftree-foldall").click();
    await expect(app.locator('.ffolder.root[data-dir="."]')).not.toHaveClass(/closed/);
    await expect(app.locator('.file[data-id="services/billing"]')).toBeVisible();
  });
});

test.describe("file tree — collapse (mobile 375px)", () => {
  test.use({ viewport: { width: 375, height: 720 } });

  test.beforeEach(async ({ app }) => {
    // The rail is a drawer parked off-screen here, so reach Files through the
    // hamburger the way a reader does — picking a view closes the drawer.
    await app.locator("#btn-menu").click();
    await app.locator('.rail-item[data-view="files"]').click();
    await expect(app.locator("#app")).toHaveAttribute("data-view", "files");
    await expect(app.locator("#ftree-list")).toContainText("orders.md");
    // Leaving the graph on a compact layout raises the one-time "other views"
    // note; dismiss it so it cannot sit over the tree.
    const note = app.locator("#hello2");
    if (await note.isVisible()) await app.locator("#hello2-x").click();
  });

  test("collapsing the root folds the list to its header", async ({ app }) => {
    // On a stacked layout the list sits on top of the reader, so a root with
    // nothing under it hands the screen back rather than showing one lone row.
    await app.locator('.ffolder.root[data-dir="."]').click();
    await expect(app.locator(".files-grid")).toHaveClass(/tree-min/);
    await expect(app.locator("#ftree-min")).toHaveAttribute("aria-expanded", "false");
  });

  test("reopening the list undoes the root collapse but preserves a file collapse", async ({ app }) => {
    const services = app.locator('.ffolder[data-dir="services"]');
    const root = app.locator('.ffolder.root[data-dir="."]');

    // Collapse a normal folder first, then the root (which also folds the list).
    await services.click();
    await expect(services).toHaveClass(/closed/);
    await root.click();
    await expect(app.locator(".files-grid")).toHaveClass(/tree-min/);

    // Bringing the list back must undo *the root collapse it caused* — or the
    // reader lands on one row with no way to reopen the tree — while leaving the
    // folder they closed by hand alone.
    await app.locator("#ftree-min").click();
    await expect(app.locator(".files-grid")).not.toHaveClass(/tree-min/);
    await expect(root).not.toHaveClass(/closed/);
    await expect(services).toHaveClass(/closed/);
  });
});
