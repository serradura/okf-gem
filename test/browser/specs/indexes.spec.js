import { test, expect, showView } from "../helpers.js";

// The Files view's "Indexes only" filter and the preview's "Open in graph"
// button both had regressions that inverted their own rule (c7bb1b5): the
// filter cleared itself when it should have held and held when it should have
// cleared, and a log's graph button opened the *root index's* node — answering
// about a different file. These pin the corrected rules.
test.describe("indexes-only filter + reserved graph button", () => {
  test.beforeEach(async ({ app }) => {
    await showView(app, "files");
    await expect(app.locator("#ftree-list")).toContainText("orders.md");
  });

  test("opening a concept releases the filter that would hide it", async ({ app }) => {
    await app.locator("#ftree-ixonly").click();
    await expect(app.locator("#ftree-ixonly")).toHaveAttribute("aria-pressed", "true");

    // In indexes-only the tree shows the authored maps; open the root map and
    // follow one of its concept links. A concept cannot appear in an
    // indexes-only list, so opening it must drop the filter or the reader's
    // selection is invisible.
    await app.locator('.file[data-res="index"][data-path="index.md"]').click();
    await app.locator("#fp-body a", { hasText: "Gateway" }).first().click();

    await expect(app.locator("#ftree-ixonly")).toHaveAttribute("aria-pressed", "false");
    await expect(app.locator("#fp-title")).toHaveText("Gateway");
  });

  test("opening a map does not release the filter", async ({ app }) => {
    await app.locator("#ftree-ixonly").click();
    await expect(app.locator("#ftree-ixonly")).toHaveAttribute("aria-pressed", "true");

    // A map row is right there in the indexes-only list, so opening it is not a
    // reason to drop a filter the reader set — the rule yields only when it
    // would hide what was just opened.
    await app.locator('.file[data-res="index"][data-path="services/index.md"]').click();
    await expect(app.locator("#fp-title")).toHaveText("services/index.md");
    await expect(app.locator("#ftree-ixonly")).toHaveAttribute("aria-pressed", "true");
  });

  test("a map offers the graph button and it lands on that map", async ({ app }) => {
    // A directory map offers "Open in graph", and it opens *that* map: switch to
    // the graph, put the services map in the inspector labelled by its directory.
    await app.locator('.file[data-res="index"][data-path="services/index.md"]').click();
    await expect(app.locator("#fp-graph")).toBeVisible();
    await app.locator("#fp-graph").click();
    await expect(app.locator("#app")).toHaveAttribute("data-view", "graph");
    await expect(app.locator("#side-body")).toContainText("services/");
  });

  test("a log hides the graph button", async ({ app }) => {
    // A log is a chronology, not a place in the graph, so openReserved('log',…)
    // sets `#fp-graph.hidden = true` (the c7bb1b5 fix — a log's graph button used
    // to open the root index's node, answering about a different file).
    //
    // This suite found that the attribute alone did not hide it: #fp-graph is a
    // `.btn.text`, and `.btn.text{display:inline-flex}` outranked
    // `.btn[hidden]{display:none}` at equal specificity, so it rendered 143px
    // wide with a stale click handler. Fixed by adding `.btn.text[hidden]`, and
    // toBeHidden reads computed visibility — not the attribute — so it holds the
    // fix, not just the intent.
    await app.locator('.file[data-res="log"][data-path="log.md"]').click();
    await expect(app.locator("#fp-title")).toHaveText("log.md");
    await expect(app.locator("#fp-graph")).toBeHidden();
  });
});
