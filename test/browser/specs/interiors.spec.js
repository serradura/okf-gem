import { test, expect, showView, visibleNodeIds } from "../helpers.js";

// Catalog, Tags and Stats are whole views the suite only ever checked the
// headline count of. Their interiors navigate: a card, a tag, a bar all lead
// into the graph, and the stats bar clears filters and isolates a type on the
// way (its own fix), so a click that used to answer nothing now answers exactly.
test.describe("catalog interior", () => {
  test("a card opens that concept in the graph", async ({ app }) => {
    await showView(app, "catalog");
    await app.locator('#cat-grid .card[data-id="services/gateway"]').click();
    await expect(app.locator("#app")).toHaveAttribute("data-view", "graph");
    await expect(app.locator("#side-body")).toContainText("The public edge");
  });

  test("a type chip narrows the grid and its count", async ({ app }) => {
    await showView(app, "catalog");
    await app.locator('#cat-types .chip[data-t="Service"]').click();
    await expect(app.locator("#cat-cnt")).toHaveText("2 of 8 concepts");
  });

  test("the slide-over filters by area and by tag, not just the header types", async ({ app }) => {
    // The inline chips only cover the top types; areas and tags live in the
    // searchable slide-over (#cat-filters). Both narrow the grid and its count —
    // area "runbooks" is deploy+rollback, tag "sales" is customers+orders.
    await showView(app, "catalog");
    await app.locator("#cat-filters-btn").click();
    await expect(app.locator("#cat-filters")).toHaveClass(/open/);

    await app.locator('#cat-fareas .chip[data-area="runbooks"]').click();
    await expect(app.locator("#cat-cnt")).toHaveText("2 of 8 concepts");

    // clear the area, then a tag — the two filters are independent handles
    await app.locator("#cat-filters-reset").click();
    await expect(app.locator("#cat-cnt")).toHaveText("8 of 8 concepts");
    await app.locator('#cat-ftags .chip[data-tag="sales"]').click();
    await expect(app.locator("#cat-cnt")).toHaveText("2 of 8 concepts");
  });

  test("the slide-over's find box narrows the filter chips themselves", async ({ app }) => {
    // One find box narrows Type/Area/Tag chips together — a busy bundle doesn't
    // flood the panel. Typing "ops" leaves only the ops tag chip; the areas and
    // types, which contain no "ops", clear out.
    await showView(app, "catalog");
    await app.locator("#cat-filters-btn").click();
    await expect(app.locator("#cat-ftags .chip").first()).toBeVisible();

    await app.locator("#cat-filter-search").fill("ops");
    await expect(app.locator("#cat-ftags .chip")).toHaveCount(1);
    await expect(app.locator("#cat-ftags .chip")).toHaveAttribute("data-tag", "ops");
    await expect(app.locator("#cat-fareas .chip")).toHaveCount(0);
  });
});

test.describe("tags interior", () => {
  test("selecting a tag lists its concepts and a click opens the graph", async ({ app }) => {
    await showView(app, "tags");
    await app.locator('.tcloud[data-tag="ops"]').click();
    await expect(app.locator("#tag-detail")).toContainText("2 concepts");
    await app.locator('#tag-detail .titem[data-id="runbooks/deploy"]').click();
    await expect(app.locator("#app")).toHaveAttribute("data-view", "graph");
    await expect(app.locator("#side-body")).toContainText("Deploy");
  });

  test("a second tag adds to the selection", async ({ app }) => {
    await showView(app, "tags");
    await app.locator('.tcloud[data-tag="core"]').click();
    await app.locator('.tcloud[data-tag="ops"]').click();
    // the detail header names both tags at once
    await expect(app.locator("#tag-detail .shead h2")).toContainText("core");
    await expect(app.locator("#tag-detail .shead h2")).toContainText("ops");
  });

  test("a type filter recounts the cloud over the surviving concepts", async ({ app }) => {
    // The tags view counts and lists tags over the concepts that survive its
    // own Type/Area filters; a tag left with none disappears. Filtering to
    // Service (billing[core], gateway[edge,public,core]) drops sales and ops and
    // recounts core from 5 down to 2 — the count is over survivors, not global.
    await showView(app, "tags");
    await expect(app.locator("#tag-cnt")).toHaveText("5 distinct tags");
    await expect(app.locator('.tcloud[data-tag="core"] b')).toHaveText("5");

    await app.locator("#tag-filters-btn").click();
    await expect(app.locator("#tag-filters")).toHaveClass(/open/);
    await app.locator('#tag-ftypes .chip[data-t="Service"]').click();

    await expect(app.locator("#tag-cnt")).toHaveText("3 of 5 distinct tags");
    await expect(app.locator('.tcloud[data-tag="ops"]')).toHaveCount(0);
    await expect(app.locator('.tcloud[data-tag="core"] b')).toHaveText("2");
  });
});

test.describe("stats interior", () => {
  test("clicking a type bar jumps to the graph and isolates that type", async ({ app }) => {
    await showView(app, "stats");
    await app.locator('#bars-type .bar[data-val="Service"]').click();
    await expect(app.locator("#app")).toHaveAttribute("data-view", "graph");
    await expect.poll(() => visibleNodeIds(app)).toEqual([ "services/billing", "services/gateway" ]);
    await expect(app.locator("#btn-filters .fbadge")).not.toHaveText("0");
  });

  test("clicking an area bar isolates that area", async ({ app }) => {
    await showView(app, "stats");
    await app.locator('#bars-area .bar[data-val="runbooks"]').click();
    await expect(app.locator("#app")).toHaveAttribute("data-view", "graph");
    await expect.poll(() => visibleNodeIds(app)).toEqual([ "runbooks/deploy", "runbooks/rollback" ]);
  });
});
