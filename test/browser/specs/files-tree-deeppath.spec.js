import { test as base, expect } from "@playwright/test";
import { deeppathPage, DEEPPATH_PORT } from "../paths.js";
import { bootGraph, showView } from "../helpers.js";

// A bundle whose one real concept sits five directories down, so its folder's
// authored index.md carries a path long enough to overflow a tree row. Served on
// its own port and baked to its own static page like the other purpose-built
// fixtures. It exists for one regression (8241cc2): a long reserved-row path used
// to push its map/log badge off the row's right edge; the fix clips the name with
// an ellipsis (`.rn{min-width:0;overflow:hidden;text-overflow:ellipsis}`) instead.
const test = base.extend({
  deep: async ({ page }, use, testInfo) => {
    const url = testInfo.project.name === "static"
      ? `file://${deeppathPage}`
      : `http://127.0.0.1:${DEEPPATH_PORT}/`;
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

test.describe("file tree — a long reserved-row path", () => {
  test("a long indexes-only row ellipsizes instead of pushing its badge off the edge", async ({ deep }) => {
    // Indexes-only lays the reserved files out flat with their whole path, so the
    // deep map's row carries all 39 characters. The name box must clip it.
    await showView(deep, "files");
    await deep.locator("#ftree-ixonly").click();
    await expect(deep.locator("#ftree-ixonly")).toHaveAttribute("aria-pressed", "true");

    const row = deep.locator('.file[data-res="index"][data-path="alpha/bravo/charlie/delta/echo/index.md"]');
    const rn = row.locator(".rn");
    await expect(rn).toHaveText("alpha/bravo/charlie/delta/echo/index.md");

    // the name overflows its box and is clipped with an ellipsis (not wrapped,
    // not spilling) — read the geometry and the computed rules together
    const res = await rn.evaluate((el) => ({
      clipped: el.scrollWidth > el.clientWidth,
      overflow: getComputedStyle(el).overflow,
      ellipsis: getComputedStyle(el).textOverflow,
      wrap: getComputedStyle(el).whiteSpace,
    }));
    expect(res.clipped, "the 39-char name overflows its box").toBe(true);
    expect(res.overflow).toBe("hidden");
    expect(res.ellipsis).toBe("ellipsis");
    expect(res.wrap).toBe("nowrap");

    // and the badge is still within the row, not shoved past its right edge
    await expect(row.locator(".badge-res")).toBeVisible();
    const within = await row.evaluate((el) => {
      const b = el.querySelector(".badge-res").getBoundingClientRect();
      const r = el.getBoundingClientRect();
      return b.right <= r.right + 1;
    });
    expect(within, "the badge stays within the row's right edge").toBe(true);
  });
});
