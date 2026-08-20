import { generatedOnlyPage, GENERATED_ONLY_PORT } from "../paths.js";
import { test as base, expect, bootGraph, showView } from "../helpers.js";

// The state a bundle is in the day its migration lands: two concepts declare
// `generated:`, none declares `verified:`, and one is still plain v0.1.
// trust-v02.spec.js cannot reach it — two of its concepts are verified, which
// is what its chip assertions are for.
//
// What lives here is the pair that has to agree. The cards show a tier chip
// whenever a concept declared `generated:` (an `unverified` tier is a real
// answer, not an absence), so the filter group offering that tier has to be
// there too. They were computed from two different predicates.
const test = base.extend({
  page2: async ({ page }, use, testInfo) => {
    const url = testInfo.project.name === "static"
      ? `file://${generatedOnlyPage}`
      : `http://127.0.0.1:${GENERATED_ONLY_PORT}/`;
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

const catalog = async (page) => {
  await showView(page, "catalog");
  await expect(page.locator("#cat-grid .card").first()).toBeVisible();
};

test.describe("a bundle generated but never verified", () => {
  test("the trust facet is offered wherever a trust chip is shown", async ({ page2 }) => {
    await catalog(page2);

    // Every card carries the tier, so the group that narrows on it must exist.
    await expect(page2.locator("#cat-grid .card .tier")).toHaveCount(2);
    await expect(page2.locator("#cat-ftrust-group")).not.toBeHidden();

    const chips = page2.locator("#cat-ftrust .chip");
    await expect(chips).toHaveCount(1);
    await expect(chips.first()).toHaveAttribute("data-trust", "unverified");

    // The count is the page's own evidence: three concepts carry an
    // `unverified` tier, but only the two that declared `generated:` wear a
    // chip, and a facet reading 3 beside 2 visible chips is the count
    // disagreeing with what the reader can see.
    await expect(chips.first().locator(".c")).toHaveText("2");
  });

  test("the offered trust facet actually narrows the grid", async ({ page2 }) => {
    // A visible filter that filters nothing is the other half of the bug.
    await catalog(page2);
    await page2.locator('#cat-ftrust .chip[data-trust="unverified"]').click();

    await expect(page2.locator("#cat-grid .card")).toHaveCount(2);
  });

  test("a multi-word status is one class, not one class per word", async ({ page2 }) => {
    await catalog(page2);
    const chip = page2.locator('#cat-grid .card[data-id="billing"] .status');

    await expect(chip).toHaveText("In Review");
    // §4.1 permits any status value, so `In Review` is supported input. Folded
    // straight into the class attribute it became `class="status in review"` —
    // two junk classes, either of which a stylesheet could already own.
    const classes = await chip.evaluate((el) => Array.from(el.classList));
    expect(classes.sort()).toEqual([ "in-review", "status" ]);
  });
});
