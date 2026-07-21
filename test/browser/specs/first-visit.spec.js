import { test as base, expect } from "@playwright/test";
import { bootGraph } from "../helpers.js";

// The first-visit notes. Every other spec seeds okf-hello to dismiss them; this
// one deliberately does not, so it lands on the first-visit path — the note, its
// "Read the index" button, the canvas hint standing down while it is up, and (on
// a phone) the second "other views" note that fires on leaving the graph.
const test = base.extend({
  fresh: async ({ page, baseURL }, use) => {
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e)));
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    await page.goto(baseURL); // no okf-hello seed — this is a first visit
    await bootGraph(page);
    await use(page);
    if (errors.length) throw new Error(`page reported ${errors.length} console/page error(s):\n  ${errors.join("\n  ")}`);
  },
});

test.describe("first visit (desktop)", () => {
  test("the welcome note shows and the canvas hint stands down", async ({ fresh }) => {
    await expect(fresh.locator("#hello")).toBeVisible();
    // the ghint says the same three gestures, so it hides while the note is up
    await expect(fresh.locator(".ghint")).toBeHidden();
  });

  test("Read the index dismisses the note and opens the index", async ({ fresh }) => {
    await fresh.locator("#hello-go").click();
    await expect(fresh.locator("#hello")).toBeHidden();
    await expect(fresh.locator("#app")).toHaveAttribute("data-view", "files");
    await expect(fresh.locator("#fp-title")).toHaveText("index.md");
  });

  test("the welcome note belongs to the graph and hides on other views", async ({ fresh }) => {
    // `#app:not([data-view=graph]) ~ #hello` — the note is the graph's, so
    // leaving the graph hides it (without dismissing it) and returning restores
    // it. No click on #hello-x: this is the CSS, not the dismissal.
    await expect(fresh.locator("#hello")).toBeVisible();
    await fresh.locator('.rail-item[data-view="catalog"]').click();
    await expect(fresh.locator("#hello")).toBeHidden();
    await fresh.locator('.rail-item[data-view="graph"]').click();
    await expect(fresh.locator("#hello")).toBeVisible();
  });

  test("dismissing restores the hint and stays dismissed across a reload", async ({ fresh }) => {
    await fresh.locator("#hello-x").click();
    await expect(fresh.locator("#hello")).toBeHidden();
    await expect(fresh.locator(".ghint")).toBeVisible();

    await fresh.reload();
    await bootGraph(fresh);
    await expect(fresh.locator("#hello")).toBeHidden();
  });
});

test.describe("first visit (mobile 375px)", () => {
  test.use({ viewport: { width: 375, height: 720 } });

  test("a second note points at the other views on leaving the graph", async ({ fresh }) => {
    await fresh.locator("#hello-x").click();
    // leave the graph through the drawer; the "other views" note fires on the way
    await fresh.locator("#btn-menu").click();
    await fresh.locator('.rail-item[data-view="catalog"]').click();
    await expect(fresh.locator("#app")).toHaveAttribute("data-view", "catalog");
    await expect(fresh.locator("#hello2")).toBeVisible();

    await fresh.locator("#hello2-x").click();
    await expect(fresh.locator("#hello2")).toBeHidden();
  });

  test("opening ☰ answers the second note and remembers it", async ({ fresh }) => {
    // ☰ is the only way off the graph on a phone, so the *first* tap comes
    // before the note ever shows — hello2Done early-returns then, or the flag
    // would burn on a hint never seen. Once the note is up (having left the
    // graph), the next ☰ tap dismisses it: the reader has demonstrably found the
    // menu, so it stops asking, and the choice persists.
    await fresh.locator("#hello-x").click();
    await fresh.locator("#btn-menu").click(); // first tap: note not yet shown
    await fresh.locator('.rail-item[data-view="catalog"]').click();
    await expect(fresh.locator("#hello2")).toBeVisible();

    await fresh.locator("#btn-menu").click(); // second tap: answers the note
    await expect(fresh.locator("#hello2")).toBeHidden();
    expect(await fresh.evaluate(() => localStorage.getItem("okf-hello2"))).toBe("1");

    // Persisted: after a reload, leaving the graph does not raise it again.
    await fresh.reload();
    await bootGraph(fresh);
    await fresh.locator("#btn-menu").click();
    await fresh.locator('.rail-item[data-view="catalog"]').click();
    await expect(fresh.locator("#app")).toHaveAttribute("data-view", "catalog");
    await expect(fresh.locator("#hello2")).toBeHidden();
  });
});

test.describe("first visit — short landscape viewport", () => {
  test.use({ viewport: { width: 900, height: 450 } });

  test("the welcome note reflows to a two-column grid when the viewport is short", async ({ fresh }) => {
    // @media (max-height:480px) and (min-width:769px) lays the note out as a
    // two-column grid so it does not eat a short landscape phone's whole height.
    // At a normal height it is a block; here it must be a grid.
    await expect(fresh.locator("#hello")).toBeVisible();
    expect(await fresh.locator("#hello").evaluate((el) => getComputedStyle(el).display)).toBe("grid");
  });
});

test.describe("first visit — a coarse pointer", () => {
  test.use({ hasTouch: true, isMobile: true, viewport: { width: 390, height: 780 } });

  test("a touch primary pointer swaps the note's click wording for tap/pinch", async ({ fresh }) => {
    // @media (pointer:coarse) shows the ".hello-touch" line ("tap any dot… pinch
    // to zoom") and hides the mouse ".hello-point" one — the gesture wording
    // follows the input, not a guess.
    await expect(fresh.locator("#hello")).toBeVisible();
    expect(await fresh.locator("#hello .hello-touch").evaluate((el) => getComputedStyle(el).display)).toBe("inline");
    expect(await fresh.locator("#hello .hello-point").evaluate((el) => getComputedStyle(el).display)).toBe("none");
  });
});
