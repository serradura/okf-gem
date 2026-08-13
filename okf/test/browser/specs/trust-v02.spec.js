import { v02Page, V02_PORT } from "../paths.js";
import { test as base, expect, bootGraph, showView, clickNode } from "../helpers.js";

// The §5 families rendered — served on its own port and baked to its own static
// page like fixtures/hostile and fixtures/manytags. The main fixture is written
// in v0.1 and cannot carry any of this: a `timestamp` records no actor, and
// `status`/`verified`/`stale_after` have no v0.1 spelling at all.
//
// What it pins is the part a string assertion on the emitted HTML cannot see:
// which chips a card actually shows, what the inspector's trust line says, and
// that the two new filter groups narrow the grid. Runs in both render modes,
// because the trust line is built by the server in one and derived from the baked
// catalog in the other — two implementations of one fragment, which is exactly
// where they would drift.
const test = base.extend({
  v02: async ({ page }, use, testInfo) => {
    const url = testInfo.project.name === "static"
      ? `file://${v02Page}`
      : `http://127.0.0.1:${V02_PORT}/`;
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e)));
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    await page.addInitScript(() => { try { localStorage.setItem("okf-hello", "1"); } catch (e) {} });
    await page.goto(url);
    await bootGraph(page);
    await use(page);
    if (errors.length) throw new Error(`page reported ${errors.length} error(s):\n  ${errors.join("\n  ")}`);
  },
});

const catalog = async (page) => {
  await showView(page, "catalog");
  await expect(page.locator("#cat-grid .card").first()).toBeVisible();
};

const card = (page, id) => page.locator(`#cat-grid .card[data-id="${id}"]`);

test.describe("§5 trust on the catalog cards", () => {
  test("a non-default status is badged and the default one is not", async ({ v02 }) => {
    await catalog(v02);

    // §5.4 defaults an absent status to `stable`, so badging it would put a
    // meaningless chip on every concept of every bundle. gateway declares
    // `stable` explicitly and must still show nothing.
    await expect(card(v02, "services/billing").locator(".status")).toHaveText("draft");
    await expect(card(v02, "services/legacy-billing").locator(".status")).toHaveText("deprecated");
    await expect(card(v02, "services/gateway").locator(".status")).toHaveCount(0);
  });

  test("all three trust tiers render, hyphenated the way the CLI prints them", async ({ v02 }) => {
    await catalog(v02);

    await expect(card(v02, "services/gateway").locator(".tier")).toHaveText("human-reviewed");
    await expect(card(v02, "services/billing").locator(".tier")).toHaveText("machine-confirmed");
    await expect(card(v02, "metrics/revenue").locator(".tier")).toHaveText("unverified");
  });

  test("a status chip and a tier chip are visually distinct channels", async ({ v02 }) => {
    // Type colour, status and trust are three channels on one card. If two of
    // them resolved to the same colour the card would read as one signal, which
    // is the regression a string assertion cannot see.
    await catalog(v02);
    const status = card(v02, "services/legacy-billing").locator(".status");
    const tier = card(v02, "services/gateway").locator(".tier");

    const statusColor = await status.evaluate((el) => getComputedStyle(el).color);
    const tierColor = await tier.evaluate((el) => getComputedStyle(el).color);

    expect(statusColor).not.toBe(tierColor);
    expect(statusColor).not.toBe("rgba(0, 0, 0, 0)");
  });

  test("a concept past its own stale_after is marked, one with a future date is not", async ({ v02 }) => {
    await catalog(v02);

    // Both dates are deliberately extreme — 2000-01-01 and 2099-12-31 — so the
    // marker never turns on a calendar rather than on a change.
    await expect(card(v02, "services/legacy-billing").locator(".mini.stale")).toContainText("expired 2000-01-01");
    await expect(card(v02, "metrics/revenue").locator(".mini.stale")).toHaveCount(0);
  });

  test("the card shows when a concept was generated", async ({ v02 }) => {
    await catalog(v02);

    await expect(card(v02, "services/gateway").locator(".mini").first()).toContainText("2026-06-02");
  });
});

test.describe("§5 trust in the inspector", () => {
  test("the trust line names the tier and who generated the concept", async ({ v02 }) => {
    await clickNode(v02, "services/gateway");

    const line = v02.locator("#side .meta-trust");
    await expect(line).toBeVisible();
    await expect(line.locator(".tier")).toHaveText("human-reviewed");
    await expect(line.locator(".gen")).toContainText("human:maintainer");
  });

  test("a machine-generated concept names its agent, not a person", async ({ v02 }) => {
    await clickNode(v02, "services/billing");

    await expect(v02.locator("#side .meta-trust .gen")).toContainText("reference_agent/gemini-2.5-pro");
    await expect(v02.locator("#side .meta-trust .tier")).toHaveText("machine-confirmed");
  });

  test("the trust line marks an expired concept", async ({ v02 }) => {
    await clickNode(v02, "services/legacy-billing");

    await expect(v02.locator("#side .meta-trust .stale")).toContainText("expired 2000-01-01");
    await expect(v02.locator("#side .meta-trust .status")).toHaveText("deprecated");
  });
});

test.describe("§5 filter groups", () => {
  test("status and trust chips appear, counted off the catalog", async ({ v02 }) => {
    await catalog(v02);
    await v02.locator("#cat-filters-btn").click();

    // Derived from the catalog rather than a fixed vocabulary, and counted on
    // the EFFECTIVE status — the same rule `--status` narrows by — so `stable`
    // gets a chip here (two concepts read stable) even though a card never
    // badges it.
    await expect(v02.locator("#cat-fstatus .chip")).toHaveCount(3);
    await expect(v02.locator('#cat-fstatus .chip[data-status="draft"]')).toBeVisible();
    await expect(v02.locator('#cat-fstatus .chip[data-status="stable"] .c')).toHaveText("2");
    await expect(v02.locator("#cat-ftrust .chip")).toHaveCount(3);
  });

  test("a status chip narrows the grid and counts the narrowing", async ({ v02 }) => {
    await catalog(v02);
    await v02.locator("#cat-filters-btn").click();
    await v02.locator('#cat-fstatus .chip[data-status="draft"]').click();

    await expect(v02.locator("#cat-grid .card")).toHaveCount(1);
    await expect(card(v02, "services/billing")).toBeVisible();
    await expect(v02.locator("#cat-cnt")).toHaveText("1 of 4 concepts");
    await expect(v02.locator("#cat-filters-btn .fbadge")).toHaveText("1");
  });

  test("a trust chip narrows the grid, and the two filters compose", async ({ v02 }) => {
    await catalog(v02);
    await v02.locator("#cat-filters-btn").click();
    await v02.locator('#cat-ftrust .chip[data-trust="unverified"]').click();

    await expect(v02.locator("#cat-grid .card")).toHaveCount(2);

    // stable AND unverified — revenue only, since legacy-billing is deprecated.
    await v02.locator('#cat-fstatus .chip[data-status="deprecated"]').click();
    await expect(v02.locator("#cat-grid .card")).toHaveCount(1);
    await expect(card(v02, "services/legacy-billing")).toBeVisible();
    await expect(v02.locator("#cat-filters-btn .fbadge")).toHaveText("2");
  });

  test("the new filters compose with the search box rather than replacing it", async ({ v02 }) => {
    // applyGraphFilter's catalog twin reads the chips and the query together;
    // a filter that silently won the tie would be the regression here.
    await catalog(v02);
    await v02.locator("#cat-filters-btn").click();
    await v02.locator('#cat-ftrust .chip[data-trust="unverified"]').click();
    await v02.locator("#cat-filters-close").click();

    await v02.locator("#search").fill("revenue");
    await expect(v02.locator("#cat-grid .card")).toHaveCount(1);
    await expect(card(v02, "metrics/revenue")).toBeVisible();
  });

  test("Reset clears the §5 groups along with the rest", async ({ v02 }) => {
    await catalog(v02);
    await v02.locator("#cat-filters-btn").click();
    await v02.locator('#cat-fstatus .chip[data-status="draft"]').click();
    await v02.locator('#cat-ftrust .chip[data-trust="machine-confirmed"]').click();
    await expect(v02.locator("#cat-filters-btn .fbadge")).toHaveText("2");

    await v02.locator("#cat-filters-reset").click();

    await expect(v02.locator("#cat-filters-btn .fbadge")).toHaveText("0");
    await expect(v02.locator("#cat-grid .card")).toHaveCount(4);
  });
});

test.describe("§5 expiry against the viewer's clock", () => {
  // No baked verdict: a static render lives for months, so the marker is
  // computed at view time from `stale_after` and the viewer's own today —
  // driven here with Playwright's clock, so the assertion never depends on
  // the machine's calendar.
  test("the marker flips as the clock crosses stale_after", async ({ page }, testInfo) => {
    const url = testInfo.project.name === "static"
      ? `file://${v02Page}`
      : `http://127.0.0.1:${V02_PORT}/`;
    await page.clock.install({ time: new Date("2099-12-30T12:00:00") });
    await page.addInitScript(() => { try { localStorage.setItem("okf-hello", "1"); } catch (e) {} });
    await page.goto(url);
    await bootGraph(page);
    await showView(page, "catalog");
    await expect(page.locator('#cat-grid .card[data-id="metrics/revenue"] .mini.stale')).toHaveCount(0);

    await page.clock.setFixedTime(new Date("2099-12-31T12:00:00"));
    await page.reload();
    await bootGraph(page);
    await showView(page, "catalog");
    await expect(page.locator('#cat-grid .card[data-id="metrics/revenue"] .mini.stale')).toContainText("expired 2099-12-31");
  });
});

test.describe("§5 sources in the page's own search", () => {
  // The asymmetry is pinned, not latent: the baked page indexes the source
  // text (it holds it), the served page does not (its catalog row carries only
  // a count) — the same trade the payload already makes for `body`.
  test("a source-only term matches on the static page and not on the served one", async ({ v02 }, testInfo) => {
    await catalog(v02);
    await v02.locator("#search").fill("escalation");

    if (testInfo.project.name === "static") {
      await expect(v02.locator("#cat-grid .card")).toHaveCount(1);
      await expect(card(v02, "services/gateway")).toBeVisible();
    } else {
      await expect(v02.locator("#cat-grid .none")).toBeVisible();
    }
  });
});
