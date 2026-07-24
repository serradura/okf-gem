import { chromium } from "playwright";
import { fileURLToPath } from "node:url";
import path from "node:path";

// Regenerates .github/server-{light,dark}.png — the README's graph-server shot.
// `bundle exec rake browser:shots` boots the server and runs this; it exists so
// the pair can be refreshed in one command rather than by hand, which is how
// they came to be three releases out of date (a topbar without the Bundles
// panel, over a bundle seven concepts smaller than the one in the repo).
// Same composition as the pair it replaces: force layout, the overview concept
// selected so its neighbours light and the rest dim, inspector open. Only the
// bundle behind it is current.
//
// Each theme gets its own fresh page, and the second replays the first's node
// positions. Two things forced that. Two independent loads lay the graph out
// differently (the force layout is seeded randomly), which made the <picture>
// swap look like two different bundles; and toggling the theme in place instead
// left Cytoscape drawing its labels from a stale texture atlas — every caption
// shaved by its first glyph, and only in the re-themed shot.
const PORT = process.env.SHOT_PORT || "8877";
const here = path.dirname(fileURLToPath(import.meta.url));
// Four hops, not three: `.github/` belongs to the repository, and this file sits
// inside the gem (okf/test/browser/). Written against the gem root it wrote to a
// directory nobody reads, silently, while still printing that it had succeeded.
const OUT = path.resolve(here, "..", "..", "..", ".github");
// 1727x964 at DPR 2 lands within a few pixels of the images being replaced
// (3454x1928), so the README's layout does not shift under the swap.
const VIEWPORT = { width: 1727, height: 964 };

const browser = await chromium.launch();
let positions = null;

for (const theme of [ "light", "dark" ]) {
  const ctx = await browser.newContext({ viewport: VIEWPORT, deviceScaleFactor: 2, colorScheme: theme });
  const page = await ctx.newPage();
  // The first-visit hello sheet would sit over the graph; the theme is read
  // from this same key before first paint.
  await page.addInitScript((t) => {
    try {
      localStorage.setItem("okf-hello", "1");
      localStorage.setItem("okf-theme", t);
    } catch (e) {}
  }, theme);

  await page.goto(`http://127.0.0.1:${PORT}/?select=overview`, { waitUntil: "load" });
  await page.waitForFunction(() => window.cy && cy.nodes().length > 0);
  // the boot fit is a 400ms timer plus a 450ms ease; the body fetch and marked
  // land after that
  await page.waitForTimeout(3500);

  if (positions) {
    await page.evaluate((p) => {
      cy.stop();
      cy.batch(() => cy.nodes().forEach((n) => { if (p[n.id()]) n.position(p[n.id()]); }));
    }, positions);
    await page.waitForTimeout(400);
  }

  // Centre on the selection at a fixed zoom rather than fitting to anything: a
  // fit lands at a different scale on every layout — once with the captions
  // unreadable, once with them clipped at the canvas edge.
  await page.evaluate(() => {
    cy.stop();
    cy.zoom(1);
    cy.center(cy.getElementById("overview"));
  });
  await page.waitForTimeout(900);

  if (!positions) {
    positions = await page.evaluate(() => {
      const out = {};
      cy.nodes().forEach((n) => { out[n.id()] = { x: n.position().x, y: n.position().y }; });
      return out;
    });
  }

  const file = `${OUT}/server-${theme}.png`;
  await page.screenshot({ path: file });
  console.log("wrote", file);
  await ctx.close();
}

await browser.close();
