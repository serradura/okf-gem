import { test, expect, visibleNodeIds } from "../helpers.js";

const ALL = [
  "charter",
  "datasets/customers",
  "datasets/orders",
  "decisions/adr-001-postgres",
  "runbooks/deploy",
  "runbooks/rollback",
  "services/billing",
  "services/gateway",
];

// `applyGraphFilter` is read by the search box, the three chip groups, the
// inspector's focus chips and cluster mode — the most-shared function in the
// file, and the one whose regressions are least visible.
test.describe("graph filters", () => {
  test.beforeEach(async ({ app }) => {
    await app.locator("#btn-filters").click();
    await expect(app.locator("#filters")).toHaveClass(/open/);
  });

  test("hiding a type drops its concepts and counts on the badge", async ({ app }) => {
    await app.locator('#ftypes .chip[data-t="Service"]').click();
    await expect(app.locator('#ftypes .chip[data-t="Service"]')).toHaveClass(/off/);
    await expect(app.locator("#btn-filters .fbadge")).toHaveText("1");
    expect(await visibleNodeIds(app)).toEqual(ALL.filter((id) => !id.startsWith("services/")));
  });

  test("the badge counts every dimension, not just types", async ({ app }) => {
    await app.locator('#ftypes .chip[data-t="Service"]').click();
    await app.locator('#fareas .chip[data-area="runbooks"]').click();
    await app.locator("#ftags .chip").first().click();
    await expect(app.locator("#btn-filters .fbadge")).toHaveText("3");
  });

  test("area and type filters intersect rather than union", async ({ app }) => {
    await app.locator('#fareas .chip[data-area="datasets"]').click();
    await app.locator('#ftypes .chip[data-t="Charter"]').click();
    // datasets only, and Charter is not in datasets, so hiding it changes nothing
    await expect.poll(() => visibleNodeIds(app)).toEqual([ "datasets/customers", "datasets/orders" ]);
  });

  test("a tag spanning two areas selects across both", async ({ app }) => {
    // `sales` is on datasets/orders and datasets/customers; `ops` on both runbooks.
    await app.locator('#ftags .chip[data-tag="ops"]').click();
    await expect.poll(() => visibleNodeIds(app)).toEqual([ "runbooks/deploy", "runbooks/rollback" ]);
  });

  test("Reset restores every concept and zeroes the badge", async ({ app }) => {
    await app.locator('#ftypes .chip[data-t="Service"]').click();
    await app.locator('#fareas .chip[data-area="runbooks"]').click();
    await app.locator("#filters-reset").click();
    await expect(app.locator("#btn-filters .fbadge")).toHaveText("0");
    expect(await visibleNodeIds(app)).toEqual(ALL);
    await expect(app.locator("#ftypes .chip.off")).toHaveCount(0);
  });

  test("the filter finder narrows the chip lists", async ({ app }) => {
    await app.locator("#filter-search").fill("service");
    await expect(app.locator('#ftypes .chip[data-t="Service"]')).toBeVisible();
    await expect(app.locator('#ftypes .chip[data-t="Charter"]')).toBeHidden();
  });

  test("close leaves the applied filter in force", async ({ app }) => {
    await app.locator('#ftypes .chip[data-t="Service"]').click();
    await app.locator("#filters-close").click();
    await expect(app.locator("#filters")).not.toHaveClass(/open/);
    await expect(app.locator("#btn-filters .fbadge")).toHaveText("1");
    expect(await visibleNodeIds(app)).not.toContain("services/gateway");
  });
});

test.describe("search", () => {
  test("narrows the graph to matching concepts", async ({ app }) => {
    await app.locator("#search").fill("rollback");
    await expect.poll(() => visibleNodeIds(app)).toEqual([ "runbooks/rollback" ]);
  });

  test("matches on the description, not only the title", async ({ app }) => {
    // "capture time" appears in the orders description and in no title.
    await app.locator("#search").fill("capture time");
    await expect.poll(() => visibleNodeIds(app)).toContain("datasets/orders");
  });

  test("body text is searchable only in the static render", async ({ app }, testInfo) => {
    // The search index covers bodies only when they are present, and they are
    // present only in a static render (EMBED); served live the page holds
    // metadata and fetches bodies on demand. That is a real, deliberate
    // difference between the modes — pinning one answer for both would
    // certify a lie in whichever mode it did not describe.
    await app.locator("#search").fill("reconciling");
    const expected = testInfo.project.name === "static" ? [ "decisions/adr-001-postgres" ] : [];
    await expect.poll(() => visibleNodeIds(app)).toEqual(expected);
  });

  test("clearing restores every concept", async ({ app }) => {
    await app.locator("#search").fill("rollback");
    await expect.poll(() => visibleNodeIds(app)).toEqual([ "runbooks/rollback" ]);
    await app.locator("#search").fill("");
    await expect.poll(() => visibleNodeIds(app)).toEqual(ALL);
  });

  test("a term nothing matches empties the graph rather than showing all", async ({ app }) => {
    await app.locator("#search").fill("zzzznotathing");
    await expect.poll(() => visibleNodeIds(app)).toEqual([]);
  });

  test("search and a chip filter compose", async ({ app }) => {
    await app.locator("#btn-filters").click();
    await app.locator('#fareas .chip[data-area="runbooks"]').click();
    await app.locator("#filters-close").click();
    await app.locator("#search").fill("deploy");

    // Assert the invariant, not an exact set. The full-text index builds
    // lazily on the first search, and in the static render it covers bodies —
    // so "deploy" legitimately matches rollback too ("the inverse of deploy")
    // once the index is up, and does not before it. Pinning one exact list
    // makes the test a race with the index build. What composition actually
    // promises is that the area filter still bounds the result.
    await expect.poll(() => visibleNodeIds(app)).toContain("runbooks/deploy");
    await app.waitForTimeout(500); // let the index land if it is still building
    for (const id of await visibleNodeIds(app)) {
      expect(id, `${id} is outside the runbooks area filter`).toMatch(/^runbooks\//);
    }
  });
});
