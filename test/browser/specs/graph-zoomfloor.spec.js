import { test as base, expect } from "@playwright/test";
import { biggraphPage, BIGGRAPH_PORT } from "../paths.js";
import { bootGraph, settledBox } from "../helpers.js";

// A 100-node ring, served on its own port and baked to its own static page like
// the other purpose-built fixtures. It exists for one contract the flat
// 8-concept fixture cannot reach: the zoom floor. cose lays the ring out as a
// large circle whose extent runs several times the canvas, which is the only
// shape that drives the fit-zoom below the default MIN_ZOOM and makes relaxZoom
// lower the floor. Runs in both render modes.
const test = base.extend({
  big: async ({ page }, use, testInfo) => {
    const url = testInfo.project.name === "static"
      ? `file://${biggraphPage}`
      : `http://127.0.0.1:${BIGGRAPH_PORT}/`;
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

test.describe("graph — the zoom floor", () => {
  test("relaxZoom lowers minZoom below the default for a graph bigger than the fit box", async ({ big }) => {
    // relaxZoom sets cy.minZoom to min(MIN_ZOOM, min(w/bb.w, h/bb.h)*.6), so when
    // the graph's extent is several times the viewport the floor drops below the
    // default MIN_ZOOM (0.2) — otherwise a big graph could never be zoomed out far
    // enough to see whole. The ring's extent runs ~3.5× the canvas height, so the
    // floor must relax. (The 8-node fixture fits at maxZoom and never moves it,
    // which is why this needs a big fixture of its own.)
    await big.waitForFunction(() => document.readyState === "complete");
    await big.waitForTimeout(1500); // let the cose layout and its layoutstop relax settle
    await settledBox(big);

    const minZoom = await big.evaluate(() => cy.minZoom());
    expect(minZoom, "the floor relaxed below the default 0.2").toBeLessThan(0.2);
  });
});
