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

  test("the fold-all control reflects the folders' collapsed state", async ({ app }) => {
    // syncFoldAll: the button offers Collapse when anything is open and Expand
    // (chevron rotated, .all-closed) when every foldable folder is shut.
    const btn = app.locator("#ftree-foldall");
    await expect(btn).toHaveAttribute("aria-label", "Collapse all folders");
    await expect(btn).toBeEnabled();
    await expect(btn).not.toHaveClass(/all-closed/);

    await btn.click();
    await expect(btn).toHaveAttribute("aria-label", "Expand all folders");
    await expect(btn).toHaveClass(/all-closed/);

    await btn.click();
    await expect(btn).toHaveAttribute("aria-label", "Collapse all folders");
    await expect(btn).not.toHaveClass(/all-closed/);
  });

  test("index/log rows sit above the concept files in their folder", async ({ app }) => {
    // subtree() renders resIn(dir) before the concept groups, so a folder's map
    // (services/index.md) lists above its concepts (services/gateway).
    const order = await app.evaluate(() => {
      const all = [ ...document.querySelectorAll("#ftree-list .file") ];
      return {
        ix: all.findIndex((e) => e.dataset.path === "services/index.md"),
        gw: all.findIndex((e) => e.dataset.id === "services/gateway"),
      };
    });
    expect(order.ix, "the services map must be present").toBeGreaterThanOrEqual(0);
    expect(order.gw, "the map must come before the concept").toBeGreaterThan(order.ix);
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

// The reader header (type badge + filename + graph button) carries a `hidden`
// attribute until a file is opened, and it is hidden by `.fp-head[hidden]{
// display:none}` — the same [hidden]-specificity precedent the log-button bug
// (indexes.spec) forced. Without that rule `.fp-head{display:flex}` wins and an
// empty header bar shows on the Files view with nothing open. toBeHidden reads
// computed display, so it holds the rule, not just the attribute; and opening a
// file is the positive control that the element can show in this view at all
// (so the hidden assertion is not passing on a hidden ancestor).
test.describe("file tree — reader header (desktop)", () => {
  test.beforeEach(async ({ app }) => {
    await showView(app, "files");
    await expect(app.locator("#ftree-list")).toContainText("orders.md");
  });

  test("the reader header is hidden until a file is open", async ({ app }) => {
    await expect(app.locator("#fp-head")).toBeHidden();

    await app.locator('.file[data-id="services/gateway"]').click();
    await expect(app.locator("#fp-head")).toBeVisible();
    await expect(app.locator("#fp-title")).toHaveText("Gateway");
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

test.describe("reserved files re-fetch fresh (server)", () => {
  test("a log re-reads on every open, so a new entry shows", async ({ app }, testInfo) => {
    test.skip(testInfo.project.name === "static", "server-only: the static bake reads logs from EMBED and never re-fetches");
    // openReserved sets LOGS=null before getLogs, so the log is re-read on every
    // open — an appended entry shows without a reload. Serve /log from a flag the
    // test flips: open log.md, flip the flag (a new entry), re-open, and the new
    // content appears. A cached getLogs would repeat the first.
    let logBody = "LOG-MARKER-ALPHA";
    await app.route((url) => url.pathname === "/log", (route) =>
      route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ logs: [ { path: "log.md", content: logBody } ] }) }));

    await showView(app, "files");
    await app.locator('.file[data-res="log"][data-path="log.md"]').click();
    await expect(app.locator("#fp-body")).toContainText("LOG-MARKER-ALPHA");

    logBody = "LOG-MARKER-BETA"; // as if a new line were appended to log.md
    await app.locator('.file[data-id="services/gateway"]').click();
    await app.locator('.file[data-res="log"][data-path="log.md"]').click();
    await expect(app.locator("#fp-body")).toContainText("LOG-MARKER-BETA");
  });
});

test.describe("file tree — the type/tag comboboxes", () => {
  test.beforeEach(async ({ app }) => {
    await showView(app, "files");
    await expect(app.locator("#ftree-list")).toContainText("orders.md");
  });

  test("picking a type narrows the tree to that type's concepts", async ({ app }) => {
    // The Files header carries two role=combobox filters; the type one narrows
    // the tree to concepts of that type (reserved index/log rows step aside
    // while either combo is set). Focus opens the listbox; the option is picked
    // on mousedown (blur closes the box 130ms later), so dispatch it directly.
    await expect(app.locator('#ftree-list .file[data-id="runbooks/deploy"]')).toBeVisible();

    await app.locator("#file-type-input").click();
    await expect(app.locator("#file-type-list")).toBeVisible();
    await app.locator('#file-type-list li[data-v="Service"]').dispatchEvent("mousedown");

    await expect(app.locator("#file-type-combo")).toHaveClass(/has/);
    await expect(app.locator('#ftree-list .file[data-id="services/gateway"]')).toBeVisible();
    await expect(app.locator('#ftree-list .file[data-id="services/billing"]')).toBeVisible();
    await expect(app.locator('#ftree-list .file[data-id="runbooks/deploy"]')).toHaveCount(0);
  });

  test("setting a combo filter hides the reserved index/log rows", async ({ app }) => {
    // Reserved files carry neither a type nor tags, so a combo filter is a
    // statement about concepts and they step aside for it: renderTree fills
    // `res` only when `!ft && !fg`. Set a type and the index/log rows go.
    await expect(app.locator("#ftree-list .file[data-res]").first()).toBeVisible();
    await app.locator("#file-type-input").click();
    await app.locator('#file-type-list li[data-v="Service"]').dispatchEvent("mousedown");
    await expect(app.locator("#file-type-combo")).toHaveClass(/has/);
    await expect(app.locator("#ftree-list .file[data-res]")).toHaveCount(0);
  });

  test("clearing the type combo restores the full tree", async ({ app }) => {
    // The ✕ clear button drops the filter and re-renders — the concepts it hid
    // come back. (Its own handle: #file-type-clear resets value to null.)
    await app.locator("#file-type-input").click();
    await app.locator('#file-type-list li[data-v="Service"]').dispatchEvent("mousedown");
    await expect(app.locator('#ftree-list .file[data-id="runbooks/deploy"]')).toHaveCount(0);

    await app.locator("#file-type-clear").click();
    await expect(app.locator("#file-type-combo")).not.toHaveClass(/has/);
    await expect(app.locator('#ftree-list .file[data-id="runbooks/deploy"]')).toBeVisible();
  });
});
