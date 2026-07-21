import { test, expect } from "../helpers.js";

const css = (page, sel, prop) =>
  page.locator(sel).evaluate((el, p) => getComputedStyle(el)[p], prop);

// The ≤768px block is ~60 lines of CSS that no string assertion can check:
// it turns the rail into a drawer and folds the tools row into a sheet, and
// both only exist as computed style at a viewport width. This is the part of
// the template that most needs a real browser.
test.describe("phone (375px)", () => {
  test.use({ viewport: { width: 375, height: 720 } });

  test("the rail becomes a fixed drawer parked off-screen", async ({ app }) => {
    expect(await css(app, "#rail", "position")).toBe("fixed");
    // translateX(-76px): parked, not display:none — it has to animate in.
    expect(await css(app, "#rail", "transform")).toBe("matrix(1, 0, 0, 1, -76, 0)");
  });

  test("the hamburger and the controls toggle appear", async ({ app }) => {
    expect(await css(app, "#btn-menu", "display")).not.toBe("none");
    expect(await css(app, "#btn-controls", "display")).not.toBe("none");
  });

  test("the hamburger slides the drawer in and marks itself expanded", async ({ app }) => {
    await app.locator("#btn-menu").click();
    await expect(app.locator("#btn-menu")).toHaveAttribute("aria-expanded", "true");
    await expect(app.locator("#app")).toHaveClass(/nav-open/);
    await expect.poll(() => css(app, "#rail", "transform")).toBe("none");
  });

  test("the backdrop closes the drawer", async ({ app }) => {
    await app.locator("#btn-menu").click();
    await expect(app.locator("#app")).toHaveClass(/nav-open/);
    await app.locator("#nav-bk").dispatchEvent("mousedown");
    await expect(app.locator("#app")).not.toHaveClass(/nav-open/);
    await expect(app.locator("#btn-menu")).toHaveAttribute("aria-expanded", "false");
  });

  test("picking a view from the drawer closes it", async ({ app }) => {
    await app.locator("#btn-menu").click();
    await app.locator('.rail-item[data-view="catalog"]').click();
    await expect(app.locator("#app")).toHaveAttribute("data-view", "catalog");
    await expect(app.locator("#app")).not.toHaveClass(/nav-open/);
  });

  test("the controls toggle folds the tools row into a sheet", async ({ app }) => {
    await app.locator("#btn-controls").click();
    await expect(app.locator("#btn-controls")).toHaveAttribute("aria-expanded", "true");
    await expect(app.locator("#app")).toHaveClass(/controls-open/);
    await expect(app.locator("#search")).toBeVisible();
  });

  test("opening Filters folds the sheet away so it cannot cover the panel", async ({ app }) => {
    await app.locator("#btn-controls").click();
    await expect(app.locator("#app")).toHaveClass(/controls-open/);
    await app.locator("#btn-filters").click();
    await expect(app.locator("#app")).not.toHaveClass(/controls-open/);
    await expect(app.locator("#filters")).toHaveClass(/open/);
  });

  test("nothing overflows the viewport horizontally", async ({ app }) => {
    expect(await app.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(375);
  });

  test("the controls toggle is gone on Stats, which has no tools to fold", async ({ app }) => {
    // The ⚙ folds the graph/files tools into a sheet; Stats has no tools, so
    // `#app[data-view=stats] #btn-controls{display:none}` hides the toggle there.
    // It is present on the graph view (the discriminating control).
    expect(await css(app, "#btn-controls", "display")).not.toBe("none");
    await app.locator("#btn-menu").click();
    await app.locator('.rail-item[data-view="stats"]').click();
    await expect(app.locator("#app")).toHaveAttribute("data-view", "stats");
    expect(await css(app, "#btn-controls", "display")).toBe("none");
  });

  test("the ⚙ toggle carries the active-filter count even with the sheet folded away", async ({ app }) => {
    // On mobile the graph tools fold behind the ⚙; an active filter must still
    // call out from the bar, so ctlBadge() mirrors the filter count onto
    // #btn-controls and lights it. Open the sheet, open Filters, hide a type —
    // the ⚙ badge reads 1 and the button carries .on-filter.
    await expect(app.locator("#btn-controls .fbadge")).toHaveText("0");
    await app.locator("#btn-controls").click();
    await app.locator("#btn-filters").click();
    await app.locator('#ftypes .chip[data-t="Service"]').click();
    await expect(app.locator("#btn-controls .fbadge")).toHaveText("1");
    await expect(app.locator("#btn-controls")).toHaveClass(/on-filter/);
  });

  test("the folded tools sheet groups the icon row instead of flinging it edge to edge", async ({ app }) => {
    // Opening the sheet wraps #graph-controls; the icon buttons must sit as one
    // group (gap only), not spread with justify-content:space-between (a5f12ab —
    // four buttons at the extremes of a phone read as four unrelated things).
    await app.locator("#btn-controls").click();
    await expect(app.locator("#app")).toHaveClass(/controls-open/);
    expect(await css(app, "#graph-controls", "justifyContent")).not.toBe("space-between");
  });
});

test.describe("desktop (1280px)", () => {
  test.use({ viewport: { width: 1280, height: 900 } });

  test("the rail is in the layout and the mobile chrome is gone", async ({ app }) => {
    expect(await css(app, "#rail", "position")).not.toBe("fixed");
    expect(await css(app, "#btn-menu", "display")).toBe("none");
    expect(await css(app, "#btn-controls", "display")).toBe("none");
  });

  test("search sits in the bar, not behind a toggle", async ({ app }) => {
    await expect(app.locator("#search")).toBeVisible();
  });
});
