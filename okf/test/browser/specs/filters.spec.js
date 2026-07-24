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

  // All three chip groups mean the same thing, and this is the group that used
  // not to. Types were *subtractive* — every type shown until you clicked one to
  // hide it — while dirs and tags were additive, and so were the catalog's own
  // type chips two views away. Same component, same word, opposite meaning,
  // which is a thing a reader has to learn per panel rather than once.
  test("picking a type narrows to it, the way picking a dir or a tag does", async ({ app }) => {
    await app.locator('#ftypes .chip[data-t="Service"]').click();
    await expect(app.locator('#ftypes .chip[data-t="Service"]')).toHaveClass(/on/);
    await expect(app.locator("#btn-filters .fbadge")).toHaveText("1");
    expect(await visibleNodeIds(app)).toEqual(ALL.filter((id) => id.startsWith("services/")));
  });

  test("a second type adds to the first rather than replacing it", async ({ app }) => {
    // The compounding half. Two selections in one group is a union — show me
    // Services *and* Charters — exactly as two tags are.
    await app.locator('#ftypes .chip[data-t="Service"]').click();
    const services = await visibleNodeIds(app);
    await app.locator('#ftypes .chip[data-t="Charter"]').click();

    const both = await visibleNodeIds(app);
    expect(both.length).toBeGreaterThan(services.length);
    expect(both).toEqual(expect.arrayContaining(services));
    await expect(app.locator("#btn-filters .fbadge")).toHaveText("2");
  });

  test("clicking a selected type again puts it back, leaving nothing selected", async ({ app }) => {
    await app.locator('#ftypes .chip[data-t="Service"]').click();
    await app.locator('#ftypes .chip[data-t="Service"]').click();

    await expect(app.locator("#ftypes .chip.on")).toHaveCount(0);
    await expect(app.locator("#btn-filters .fbadge")).toHaveText("0");
    expect(await visibleNodeIds(app)).toEqual(ALL);
  });

  test("the badge counts every dimension, not just types", async ({ app }) => {
    await app.locator('#ftypes .chip[data-t="Service"]').click();
    await app.locator('#fdirs .chip[data-dir="runbooks"]').click();
    await app.locator("#ftags .chip").first().click();
    await expect(app.locator("#btn-filters .fbadge")).toHaveText("3");
  });

  test("groups intersect even where that leaves nothing", async ({ app }) => {
    // Within a group, selections union; across groups they intersect. Charter
    // lives outside datasets, so asking for both is an honest empty result —
    // and an empty graph with a badge of 2 is the correct answer, not a bug.
    await app.locator('#fdirs .chip[data-dir="datasets"]').click();
    await app.locator('#ftypes .chip[data-t="Charter"]').click();

    await expect.poll(() => visibleNodeIds(app)).toEqual([]);
    await expect(app.locator("#btn-filters .fbadge")).toHaveText("2");
  });

  test("a type and a dir that do overlap keep exactly the overlap", async ({ app }) => {
    await app.locator('#fdirs .chip[data-dir="datasets"]').click();
    await app.locator('#ftypes .chip[data-t="Dataset"]').click();

    await expect.poll(() => visibleNodeIds(app)).toEqual([ "datasets/customers", "datasets/orders" ]);
  });

  test("a tag spanning two dirs selects across both", async ({ app }) => {
    // `sales` is on datasets/orders and datasets/customers; `ops` on both runbooks.
    await app.locator('#ftags .chip[data-tag="ops"]').click();
    await expect.poll(() => visibleNodeIds(app)).toEqual([ "runbooks/deploy", "runbooks/rollback" ]);
  });

  test("Reset restores every concept and zeroes the badge", async ({ app }) => {
    await app.locator('#ftypes .chip[data-t="Service"]').click();
    await app.locator('#fdirs .chip[data-dir="runbooks"]').click();
    await app.locator("#filters-reset").click();
    await expect(app.locator("#btn-filters .fbadge")).toHaveText("0");
    expect(await visibleNodeIds(app)).toEqual(ALL);
    await expect(app.locator("#ftypes .chip.on")).toHaveCount(0);
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
    expect(await visibleNodeIds(app)).toContain("services/gateway");
  });
});

test.describe("search", () => {
  test("narrows the graph to matching concepts", async ({ app }) => {
    // Assert the invariant, not an exact set — like "search and a chip filter
    // compose" below, and for the same reason. "rollback" is a title match, but
    // the static render also indexes bodies, and deploy.md's body says "go to
    // rollback", so once the lazy index builds "rollback" matches deploy too.
    // Pinning [rollback] alone raced the index build (green only if the poll read
    // the pre-index substring state first) and flaked under load.
    // (In static the body index also pulls in concepts whose body mentions
    // rollback — deploy and gateway link to it — so the exact set is mode- and
    // timing-dependent; the invariant is not.)
    await app.locator("#search").fill("rollback");
    await expect.poll(() => visibleNodeIds(app)).toContain("runbooks/rollback");
    await app.waitForTimeout(500); // let the index land if it is still building
    const ids = await visibleNodeIds(app);
    expect(ids, "rollback stays in the narrowed result").toContain("runbooks/rollback");
    expect(ids.length, "the graph is narrowed, not showing all 8").toBeLessThan(8);
  });

  test("matches on the description, not only the title", async ({ app }) => {
    // "capture time" appears in the orders description and in no title.
    await app.locator("#search").fill("capture time");
    await expect.poll(() => visibleNodeIds(app)).toContain("datasets/orders");
  });

  test("a one-edit typo still matches — the index is fuzzy", async ({ app }) => {
    // searchOptions carry fuzzy:0.2, so a typo within one edit still finds its
    // concept: "gatway" → gateway (one deletion). It is neither a substring of
    // any field (nothing contains "gatway") nor a prefix of "gateway" (which
    // begins "gatew…"), so a match here is the fuzzy tolerance and nothing else,
    // once the lazy MiniSearch index builds. Poll past the pre-index empty state.
    await app.locator("#search").fill("gatway");
    await expect.poll(() => visibleNodeIds(app)).toContain("services/gateway");
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
    // The narrowing is asserted by its invariant (see above); the point here is
    // that clearing brings everything back.
    await app.locator("#search").fill("rollback");
    await expect.poll(() => visibleNodeIds(app)).toContain("runbooks/rollback");
    await expect.poll(() => visibleNodeIds(app).then((ids) => ids.length)).toBeLessThan(8);
    await app.locator("#search").fill("");
    await expect.poll(() => visibleNodeIds(app)).toEqual(ALL);
  });

  test("a term nothing matches empties the graph rather than showing all", async ({ app }) => {
    await app.locator("#search").fill("zzzznotathing");
    await expect.poll(() => visibleNodeIds(app)).toEqual([]);
  });

  test("search and a chip filter compose", async ({ app }) => {
    await app.locator("#btn-filters").click();
    await app.locator('#fdirs .chip[data-dir="runbooks"]').click();
    await app.locator("#filters-close").click();
    await app.locator("#search").fill("deploy");

    // Assert the invariant, not an exact set. The full-text index builds
    // lazily on the first search, and in the static render it covers bodies —
    // so "deploy" legitimately matches rollback too ("the inverse of deploy")
    // once the index is up, and does not before it. Pinning one exact list
    // makes the test a race with the index build. What composition actually
    // promises is that the dir filter still bounds the result.
    await expect.poll(() => visibleNodeIds(app)).toContain("runbooks/deploy");
    await app.waitForTimeout(500); // let the index land if it is still building
    for (const id of await visibleNodeIds(app)) {
      expect(id, `${id} is outside the runbooks dir filter`).toMatch(/^runbooks\//);
    }
  });

  test("the MiniSearch index is built lazily — its script loads only on first search focus", async ({ app }) => {
    // The full-text index is not built at boot: searchInput.onfocus calls
    // buildFtIndex, which loadScript-loads MiniSearch from the CDN. Route its
    // script with a flag: nothing requests it until the box is focused, then it
    // is. (route.fallback lets the real load through, so no console error — and
    // unlike continue() it defers to the context's vendor cache underneath
    // rather than going straight to the network.)
    let loaded = false;
    await app.route(/minisearch@7\.2\.0/, (route) => { loaded = true; return route.fallback(); });

    await app.waitForTimeout(300);
    expect(loaded, "MiniSearch is not loaded before any search interaction").toBe(false);
    expect(await app.evaluate(() => typeof window.MiniSearch)).toBe("undefined");

    await app.locator("#search").focus();
    await expect.poll(() => loaded).toBe(true);
  });

  test("search falls back to substring matching when the index is unavailable", async ({ app }) => {
    // Until the index is ready (or if the CDN is down), ftMatch returns null and
    // applyGraphFilter falls back to a substring test on title/type/tags/desc.
    // Block MiniSearch outright so the index can never build, then search a title
    // substring: the graph still narrows to the match.
    app.allowErrors(); // the blocked MiniSearch <script> logs a resource error
    await app.route(/minisearch@7\.2\.0/, (route) => route.abort());

    await app.locator("#search").fill("gateway");
    await expect.poll(() => visibleNodeIds(app)).toEqual([ "services/gateway" ]);
  });
});
