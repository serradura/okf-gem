import { test as base, expect, bootGraph } from "../helpers.js";

// ?view / ?layout / ?select / #hash and the ?view=index shortcut. These carry
// state into a fresh page, so they need a URL the shared `app` fixture cannot
// give — a local fixture opens an arbitrary query and keeps the console watch.
const test = base.extend({
  deeplink: async ({ page, baseURL }, use) => {
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e)));
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    await page.addInitScript(() => { try { localStorage.setItem("okf-hello", "1"); } catch (e) {} });
    const open = async (query) => { await page.goto(baseURL + query); await bootGraph(page); return page; };
    await use({ page, open });
    if (errors.length) throw new Error(`page reported ${errors.length} console/page error(s):\n  ${errors.join("\n  ")}`);
  },
});

const sel = (id) => encodeURIComponent(id);

test.describe("deep links", () => {
  test("?view= opens that view on arrival", async ({ deeplink }) => {
    const p = await deeplink.open("?view=catalog");
    await expect(p.locator("#app")).toHaveAttribute("data-view", "catalog");
  });

  test("?view=index resolves to Files with the root map open", async ({ deeplink }) => {
    // index is a shortcut, not a view — ?view=index must run readIndex, not
    // setView('index') on a view that does not exist.
    const p = await deeplink.open("?view=index");
    await expect(p.locator("#app")).toHaveAttribute("data-view", "files");
    await expect(p.locator("#fp-title")).toHaveText("index.md");
  });

  test("?layout= selects and applies that layout", async ({ deeplink }) => {
    const p = await deeplink.open("?layout=grid");
    await expect(p.locator("#layout")).toHaveValue("grid");
  });

  test("?select= selects the node and shows it", async ({ deeplink }) => {
    const p = await deeplink.open("?select=" + sel("services/gateway"));
    await expect(p.locator("#app")).toHaveAttribute("data-view", "graph");
    await expect(p.locator("#side-body")).toContainText("The public edge");
    await expect.poll(() => p.evaluate(() => cy.getElementById("services/gateway").hasClass("hl"))).toBe(true);
  });

  test("a #hash selects that node", async ({ deeplink }) => {
    const p = await deeplink.open("#" + sel("services/billing"));
    await expect.poll(() => p.evaluate(() => cy.getElementById("services/billing").hasClass("hl"))).toBe(true);
    await expect(p.locator("#side-body")).toContainText("Billing");
  });

  test("a selection carries the view — ?view= plus ?select= lands on the graph", async ({ deeplink }) => {
    // deeplink-node-carries-view: selecting into a view nobody is looking at was
    // a silent no-op; goToGraph now brings the graph along.
    const p = await deeplink.open("?view=catalog&select=" + sel("services/gateway"));
    await expect(p.locator("#app")).toHaveAttribute("data-view", "graph");
    await expect.poll(() => p.evaluate(() => cy.getElementById("services/gateway").hasClass("hl"))).toBe(true);
  });
});
