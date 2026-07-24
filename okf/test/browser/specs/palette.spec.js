import { test, expect } from "../helpers.js";

// The command palette (⌘/Ctrl-K). Its worst regression had the Index row call
// setView('index') — a view that does not exist — and blank the page; the fix
// reads the rail for its view list and routes every choice through the rail
// button (goRail), so Index resolves to Files exactly as the rail does. Views
// are the whole list in standalone mode (no hub), which is what both test modes
// are, so an empty query lists them all.
test.describe("command palette", () => {
  const sw = (app) => app.locator("#sw");

  test("Ctrl-K opens it focused, Escape closes it", async ({ app }) => {
    await app.keyboard.press("Control+k");
    await expect(sw(app)).toBeVisible();
    await expect(app.locator("#sw-input")).toBeFocused();
    await app.keyboard.press("Escape");
    await expect(sw(app)).toBeHidden();
  });

  test("typing a view and pressing Enter jumps to it", async ({ app }) => {
    await app.keyboard.press("Control+k");
    await app.locator("#sw-input").fill("catalog");
    await expect(app.locator("#sw-list a[data-view='catalog']")).toBeVisible();
    await app.keyboard.press("Enter");
    await expect(app.locator("#app")).toHaveAttribute("data-view", "catalog");
    await expect(sw(app)).toBeHidden();
  });

  test("the Index row lands on Files, never a blank view", async ({ app }) => {
    await app.keyboard.press("Control+k");
    await app.locator("#sw-input").fill("index");
    // View rows are keyboard-selected (the list's click handler is for bundle
    // rows); Enter takes the single filtered option.
    await expect(app.locator("#sw-list a[data-view='index']")).toBeVisible();
    await app.keyboard.press("Enter");
    await expect(app.locator("#app")).toHaveAttribute("data-view", "files");
    await expect(app.locator("#fp-title")).toHaveText("index.md");
  });

  test("the arrow keys move the active option", async ({ app }) => {
    await app.keyboard.press("Control+k");
    const opts = app.locator("#sw-list a[data-view]");
    await expect(opts.first()).toHaveClass(/active/);
    await app.keyboard.press("ArrowDown");
    await expect(opts.nth(1)).toHaveClass(/active/);
    await expect(opts.first()).not.toHaveClass(/active/);
  });

  test("the ⇄ switch-bundle button is hidden in standalone (no hub)", async ({ app }) => {
    // #btn-switch only un-hides when HUB is set (a hub serving siblings). Both
    // projects here are standalone, so the ⇄ button stays hidden and the palette
    // is reached by the chord and the hint alone. palette-hub proves the other
    // side — the same button visible when a hub is behind it.
    await expect(app.locator("#btn-switch")).toBeHidden();
  });

  test("a query matching nothing shows the no-matches note", async ({ app }, testInfo) => {
    // Two empty states, and which one you get says whether a finder ran. A
    // static file has none, so the query falls through to the generic note
    // (render's `if(!h)`); a served bundle asks its /search, gets nothing, and
    // says so in those words.
    await app.keyboard.press("Control+k");
    await app.locator("#sw-input").fill("zzznomatchxyz");
    await expect(app.locator("#sw-list a.none")).toContainText(
      testInfo.project.name === "static" ? "no matches" : "no concepts match");
    // and it is inert — a note, not an option
    await expect(app.locator("#sw-list a[data-view], #sw-list a[data-path]")).toHaveCount(0);
  });
});
