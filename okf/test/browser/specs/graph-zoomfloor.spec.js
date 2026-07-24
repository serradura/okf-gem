import { biggraphPage, BIGGRAPH_PORT } from "../paths.js";
import { test as base, expect, bootGraph, settledBox } from "../helpers.js";

// A 100-node ring, served on its own port and baked to its own static page like
// the other purpose-built fixtures. It exists for one contract the flat
// 8-concept fixture cannot reach: the zoom floor. 100 nodes lay out over an
// extent several times the canvas, which is the only shape that drives the
// fit-zoom below the default MIN_ZOOM and makes relaxZoom lower the floor. Runs
// in both render modes.
//
// It used to read the *boot* layout, and that was a coin flip. cose seeds itself
// from Math.random, so the spread — and with it the floor — varies run to run:
// measured across ten runs, minZoom landed anywhere from 0.135 to 0.2, and 0.2
// is the value that fails. The margin was never the ~3.5× the old comment
// claimed; it was whatever that run's dice gave. The spec now runs `circle`
// instead, which is deterministic (3732×3721 every time, floor ~0.14) and still
// reaches relaxZoom by the same road — runLayout → layoutstop → relaxZoom.
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
    // enough to see whole. (The 8-node fixture fits at maxZoom and never moves
    // it, which is why this needs a big fixture of its own.)
    await big.waitForFunction(() => document.readyState === "complete");
    await big.locator("#layout").selectOption("circle");
    await settledBox(big);

    // Polled, not read once: the layout is deterministic but the moment its
    // layoutstop lands is not, and a starved worker can be seconds behind. What
    // makes the poll safe here is that nothing on the page writes minZoom but
    // relaxZoom — so the floor falls once and stays down, and a pass cannot be
    // an animation frame caught mid-flight.
    await expect.poll(() => big.evaluate(() => cy.minZoom()), { timeout: 15_000 })
      .toBeLessThan(0.2);
  });
});
