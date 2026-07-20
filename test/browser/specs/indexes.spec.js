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

  // KNOWN BUG — a real one this suite just turned up, held open like the
  // graph-collapse case in views.spec.js so the baseline stays green while the
  // bug stays on the record. Playwright flags it as an unexpected pass the
  // moment it is fixed; delete the marker then.
  //
  // A log is a chronology, not a place in the graph, so openReserved('log',…)
  // sets `#fp-graph.hidden = true` — the fix for c7bb1b5, where a log's graph
  // button opened the *root index's* node (a log's directory is the root),
  // answering about a different file.
  //
  // The attribute is set, but the button stays visible: it is a `.btn.text`, and
  // `.btn.text{display:inline-flex}` (template line 132) outranks
  // `.btn[hidden]{display:none}` (line 131) — equal specificity (0,2,0), so the
  // later rule wins. Measured: hidden attribute present, computed display flex,
  // 143px wide on screen. Worse, openReserved for a log never re-points the
  // button's onclick, so the visible button fires whatever the last map or
  // concept set — the exact "different file" symptom the fix removed.
  //
  // The maintainer already hit this `[hidden]`-loses-to-a-display-rule gotcha
  // once, at line 492 (`.fp-head[hidden]{display:none}`, with a comment naming
  // it); `#fp-graph` was missed. The one-line fix follows that precedent:
  // `.btn.text[hidden]{display:none}` (specificity 0,3,0, so it wins).
  test.fail("a log hides the graph button", async ({ app }) => {
    await app.locator('.file[data-res="log"][data-path="log.md"]').click();
    await expect(app.locator("#fp-title")).toHaveText("log.md");
    // toBeHidden reads computed visibility, not the attribute — which is the
    // whole point: the attribute is set and the button shows anyway.
    await expect(app.locator("#fp-graph")).toBeHidden();
  });
});
