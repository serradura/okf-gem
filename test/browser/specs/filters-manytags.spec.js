import { manytagsPage, MANYTAGS_PORT } from "../paths.js";
import { test as base, expect, bootGraph } from "../helpers.js";

// A bundle with 45 distinct tags (tag01…tag45), served on its own port and baked
// to its own static page like fixtures/hostile and fixtures/tree. It exists for
// one contract the main fixture's five tags cannot reach: the filter finder caps
// its tag chips at the top 40 by count until a search is typed, at which point
// the finder reaches every tag. Runs in both render modes.
const test = base.extend({
  many: async ({ page }, use, testInfo) => {
    const url = testInfo.project.name === "static"
      ? `file://${manytagsPage}`
      : `http://127.0.0.1:${MANYTAGS_PORT}/`;
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

test.describe("filter finder — the tag chip cap", () => {
  test("tag chips cap at 40 until the finder reaches all of them", async ({ many }) => {
    // 45 distinct tags, but the graph filter shows only the top 40 by count
    // (tagsByCount.slice(0,40)) so a busy bundle does not flood the panel.
    // Typing into the finder switches to tagsByCount.filter(match), which reaches
    // every tag — "tag" matches all 45, proving the cap lifts on search.
    await many.locator("#btn-filters").click();
    await expect(many.locator("#ftags .chip").first()).toBeVisible();
    await expect(many.locator("#ftags .chip")).toHaveCount(40);

    await many.locator("#filter-search").fill("tag");
    await expect(many.locator("#ftags .chip")).toHaveCount(45);

    // and a tag that the cap had hidden is now reachable and selectable
    await expect(many.locator('#ftags .chip[data-tag="tag45"]')).toBeVisible();
  });
});
