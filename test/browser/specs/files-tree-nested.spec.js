import { test as base, expect } from "@playwright/test";
import { treePage, TREE_PORT } from "../paths.js";
import { bootGraph, showView } from "../helpers.js";

// A nested-directory bundle — charter at the root, then platform/services/{api,
// auth} and data/warehouse/events, each intermediate directory holding only a
// subdirectory. It is served on its own port and baked to its own static page
// (paths.js), the same arrangement fixtures/hostile uses and for the same
// reason: these file-tree structure branches — a directory with only sub-dirs,
// folder headers showing just the last path segment, indentation that nests a
// parent above its child — have no way in through the flat 8-concept fixture,
// whose count assertions must stay put. Runs in both render modes like the rest.
const test = base.extend({
  tree: async ({ page }, use, testInfo) => {
    const url = testInfo.project.name === "static"
      ? `file://${treePage}`
      : `http://127.0.0.1:${TREE_PORT}/`;
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e)));
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    await page.addInitScript(() => { try { localStorage.setItem("okf-hello", "1"); } catch (e) {} });
    await page.goto(url);
    await bootGraph(page);
    await use(page);
    if (errors.length) throw new Error(`page reported ${errors.length} error(s):\n  ${errors.join("\n  ")}`);
  },
});

test.describe("file tree — a nested bundle", () => {
  test.beforeEach(async ({ tree }) => {
    await showView(tree, "files");
    await expect(tree.locator("#ftree-list")).toContainText("api.md");
  });

  test("a directory that holds only a subdirectory still renders as a folder", async ({ tree }) => {
    // platform/ has no files of its own — only services/ beneath it. dirParents()
    // walks the chain so the intermediate directory still draws a folder header,
    // with its child folder nested inside. data/ → warehouse/ is the second case.
    await expect(tree.locator('.ffolder[data-dir="platform"]')).toBeVisible();
    await expect(tree.locator('.ffolder[data-dir="platform/services"]')).toBeVisible();
    await expect(tree.locator('.ffolder[data-dir="data"]')).toBeVisible();
    await expect(tree.locator('.ffolder[data-dir="data/warehouse"]')).toBeVisible();

    // the concepts live only at the leaves — nothing sits directly under platform/
    await expect(tree.locator('.file[data-id="platform/services/api"]')).toBeVisible();
    await expect(tree.locator('.file[data-id="platform/services/auth"]')).toBeVisible();
  });

  test("a folder header shows only the last path segment", async ({ tree }) => {
    // The nested folder reads "services/", not "platform/services/"
    // (dir.split('/').pop()); the same for the intermediate and the sibling tree.
    await expect(tree.locator('.ffolder[data-dir="platform/services"] span')).toHaveText("services/");
    await expect(tree.locator('.ffolder[data-dir="platform"] span')).toHaveText("platform/");
    await expect(tree.locator('.ffolder[data-dir="data/warehouse"] span')).toHaveText("warehouse/");
  });

  test("indexes-only shows the empty state when there are no index or log files", async ({ tree }) => {
    // This bundle has no index.md or log.md, so narrowing to the authored layer
    // leaves nothing: flatRes() returns '' and the ixOnly branch falls through
    // to its empty-state message. (The main fixture, which has maps, never hits
    // this branch — it needs a bundle with none.)
    await tree.locator("#ftree-ixonly").click();
    await expect(tree.locator("#ftree-ixonly")).toHaveAttribute("aria-pressed", "true");
    await expect(tree.locator("#ftree-list .empty")).toContainText("No index.md or log.md files");
    await expect(tree.locator("#ftree-list .file")).toHaveCount(0);
  });

  test("directories nest by depth, each parent indented less than its child", async ({ tree }) => {
    // --d is the depth the renderer sets inline; the CSS turns it into a
    // padding-left of 8 + d*13px, so a child folder is indented past its parent
    // and a file past its folder. Read the computed padding to prove the nesting
    // (asserting the structure, not just that a class is present).
    const pad = (sel) => tree.locator(sel).evaluate((el) => parseFloat(getComputedStyle(el).paddingLeft));
    const platform = await pad('.ffolder[data-dir="platform"]');
    const services = await pad('.ffolder[data-dir="platform/services"]');
    const file = await pad('.file[data-id="platform/services/api"]');
    expect(services).toBeGreaterThan(platform);
    expect(file).toBeGreaterThan(services);
  });
});
