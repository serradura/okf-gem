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
