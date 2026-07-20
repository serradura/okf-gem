import { test, expect, bootGraph } from "../helpers.js";

const theme = (page) => page.evaluate(() => document.documentElement.getAttribute("data-theme"));

// The theme toggle writes data-theme on the root and persists it; the boot
// script in <head> reads it back before first paint so a reload does not flash
// the wrong theme.
test.describe("theme", () => {
  test("the toggle flips the theme both ways", async ({ app }) => {
    const before = await theme(app);
    expect([ "light", "dark" ]).toContain(before);

    await app.locator("#btn-theme").click();
    expect(await theme(app)).not.toBe(before);

    await app.locator("#btn-theme").click();
    expect(await theme(app)).toBe(before);
  });

  test("the choice survives a reload and is set before first paint", async ({ app }) => {
    const before = await theme(app);
    await app.locator("#btn-theme").click();
    const chosen = await theme(app);
    expect(chosen).not.toBe(before);

    await app.reload();
    // Read before waiting for the graph — the <head> script has already run, so
    // the theme is correct at first paint, not after boot.
    expect(await theme(app)).toBe(chosen);
    await bootGraph(app);
  });
});

// With no stored choice the boot script falls back to the system preference:
// localStorage.getItem('okf-theme') || (matchMedia(prefers-color-scheme:dark) …).
// The app fixture seeds okf-hello but never okf-theme, so each fresh context
// resolves purely from the emulated colour scheme — the dark case is the
// discriminating one, since a bug that ignored the query would boot light.
test.describe("boot follows the system preference when nothing is stored", () => {
  test.describe("a dark system preference", () => {
    test.use({ colorScheme: "dark" });
    test("boots dark", async ({ app }) => {
      expect(await theme(app)).toBe("dark");
    });
  });

  test.describe("a light system preference", () => {
    test.use({ colorScheme: "light" });
    test("boots light", async ({ app }) => {
      expect(await theme(app)).toBe("light");
    });
  });
});
