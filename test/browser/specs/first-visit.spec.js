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
});
