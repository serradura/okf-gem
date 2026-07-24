import { test, expect, showView } from "../helpers.js";

// The ? sheet and the search key. The sheet is a modal that takes focus and
// closes on Esc or a second ?; the / key focuses the search only where the view
// has one — search-key-scoped, because / used to focus a box that stats hides.
test.describe("keyboard help sheet", () => {
  test("? opens the sheet, focuses close, and lists the bindings", async ({ app }) => {
    await app.keyboard.press("?");
    await expect(app.locator("#kb")).toBeVisible();
    await expect(app.locator("#kb-x")).toBeFocused();
    await expect(app.locator("#kb-list dt")).not.toHaveCount(0);
    await expect(app.locator("#kb-list")).toContainText("switch view");
  });

  test("Esc closes it, and a second ? toggles it shut", async ({ app }) => {
    await app.keyboard.press("?");
    await expect(app.locator("#kb")).toBeVisible();
    await app.keyboard.press("Escape");
    await expect(app.locator("#kb")).toBeHidden();

    await app.locator("#btn-help").click();
    await expect(app.locator("#kb")).toBeVisible();
    await app.keyboard.press("?");
    await expect(app.locator("#kb")).toBeHidden();
  });

  test("the sheet manages focus — close on open, opener on close", async ({ app }) => {
    // Modal focus management: opening focuses the close button, closing returns
    // focus to the control that opened it.
    await app.locator("#btn-help").click();
    await expect(app.locator("#kb")).toBeVisible();
    await expect(app.locator("#kb-x")).toBeFocused();

    await app.locator("#kb-x").click();
    await expect(app.locator("#kb")).toBeHidden();
    await expect(app.locator("#btn-help")).toBeFocused();
  });

  test("/ focuses the search where the view has one, and does nothing on stats", async ({ app }) => {
    await app.keyboard.press("/");
    await expect(app.locator("#search")).toBeFocused();

    await app.locator("#search").blur();
    await showView(app, "stats"); // stats has no search box
    await app.keyboard.press("/");
    await expect(app.locator("#search")).not.toBeFocused();
  });
});
