import { treePage, TREE_PORT, deeppathPage, DEEPPATH_PORT } from "../paths.js";
import { test as base, expect, bootGraph } from "../helpers.js";

// Cluster mode used to draw one flat row of boxes, one per *first path segment*
// — the whole reason `areaOf` threw away every level below the first. It nests
// now, to a depth the reader picks, so these proofs need a bundle with more than
// one level: fixtures/tree (charter at the root, then platform/services/{api,
// auth} and data/warehouse/events, each intermediate directory holding nothing
// directly) and fixtures/deeppath (one concept five directories down). Both
// already have their own server + static page in paths.js, and both run here.
//
// The main 8-concept fixture is flat, so it can only ever prove depth 1 — which
// graph-modes.spec.js does, and which is the continuity pin: the default depth
// must draw exactly what the flat view always drew.
function fixtureFor(staticPath, port) {
  return async ({ page }, use, testInfo) => {
    const url = testInfo.project.name === "static" ? `file://${staticPath}` : `http://127.0.0.1:${port}/`;
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e)));
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    await page.addInitScript(() => { try { localStorage.setItem("okf-hello", "1"); } catch (e) {} });
    await page.goto(url);
    await bootGraph(page);
    await use(page);
    if (errors.length) throw new Error(`page reported ${errors.length} error(s):\n  ${errors.join("\n  ")}`);
  };
}

const test = base.extend({
  tree: fixtureFor(treePage, TREE_PORT),
  deep: fixtureFor(deeppathPage, DEEPPATH_PORT),
});

const boxes = (page) => page.evaluate(() => cy.nodes(":parent").map((n) => n.id()).sort());
const parentOf = (page, id) => page.evaluate((i) => {
  const p = cy.getElementById(i).parent();
  return p.nonempty() ? p[0].id() : null;
}, id);

test.describe("cluster mode — nested boxes", () => {
  test("depth 1 draws the flat view: one box per first segment, plus the root", async ({ tree }) => {
    await tree.locator("#btn-cluster").click();
    await expect(tree.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "true");

    expect(await tree.locator("#cluster-depth").inputValue()).toBe("1");
    expect(await boxes(tree)).toEqual([ "box::.", "box::data", "box::platform" ]);
    // a concept two levels down attaches to its truncated ancestor, not its own dir
    expect(await parentOf(tree, "platform/services/api")).toBe("box::platform");
    expect(await parentOf(tree, "charter")).toBe("box::.");
  });

  test("depth 2 nests each first-segment box over its children", async ({ tree }) => {
    await tree.locator("#btn-cluster").click();
    await tree.locator("#cluster-depth").selectOption("2");

    await expect.poll(() => boxes(tree)).toEqual([
      "box::.", "box::data", "box::data/warehouse", "box::platform", "box::platform/services",
    ]);
    expect(await parentOf(tree, "box::platform/services")).toBe("box::platform");
    expect(await parentOf(tree, "platform/services/api")).toBe("box::platform/services");
    // the root box never nests another — it holds direct-root concepts only
    expect(await parentOf(tree, "charter")).toBe("box::.");
    expect(await tree.evaluate(() => cy.getElementById("box::.").children().filter((n) => n.isParent()).length)).toBe(0);
  });

  test("an intermediate box holding only sub-boxes still renders", async ({ tree }) => {
    // platform/ has no concepts directly in it. Under the old children()-based
    // emptiness rule such a box always read "empty" and was hidden, taking its
    // whole nested branch off the canvas with it.
    await tree.locator("#btn-cluster").click();
    await tree.locator("#cluster-depth").selectOption("2");

    await expect.poll(() => tree.evaluate(() => cy.getElementById("box::platform").style("display"))).toBe("element");
    expect(await tree.evaluate(() => cy.getElementById("box::platform").children().filter((n) => !n.isParent()).length)).toBe(0);
  });

  test("filtering every leaf of a branch hides the whole branch of boxes", async ({ tree }) => {
    // Typed *while the tiling animation is still running*, deliberately: fcose
    // measures every node it is handed, and a nested compound graph whose nodes
    // went display:none mid-run threw on a label it could no longer measure
    // ("Cannot read properties of undefined (reading 'labelWidth')"). The fixture
    // check at the top of this file fails the test on any page error, so this is
    // the spec that pins the layout being handed the visible subset only.
    await tree.locator("#btn-cluster").click();
    await tree.locator("#cluster-depth").selectOption("2");
    await tree.locator("#search").fill("warehouse-only-nothing-matches-platform");

    await expect.poll(() => tree.evaluate(() => cy.getElementById("box::platform/services").style("display"))).toBe("none");
    await expect.poll(() => tree.evaluate(() => cy.getElementById("box::platform").style("display"))).toBe("none");
  });

  test("a surviving leaf keeps every box above it on the canvas", async ({ tree }) => {
    await tree.locator("#btn-cluster").click();
    await tree.locator("#cluster-depth").selectOption("2");
    await tree.locator("#btn-filters").click();
    await tree.locator('#fdirs .chip[data-dir="platform/services"]').click();

    await expect.poll(() => tree.evaluate(() => cy.getElementById("box::platform").style("display"))).toBe("element");
    await expect.poll(() => tree.evaluate(() => cy.getElementById("box::platform/services").style("display"))).toBe("element");
    await expect.poll(() => tree.evaluate(() => cy.getElementById("box::data").style("display"))).toBe("none");
  });

  test("turning clustering off removes every box and hands back the layout select", async ({ tree }) => {
    const total = () => tree.evaluate(() => cy.nodes().length);
    const before = await total();

    await tree.locator("#btn-cluster").click();
    await tree.locator("#cluster-depth").selectOption("2");
    await expect.poll(() => boxes(tree)).not.toEqual([]);
    await expect(tree.locator("#layout")).toBeDisabled();

    await tree.locator("#btn-cluster").click();
    await expect(tree.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "false");
    await expect.poll(() => boxes(tree)).toEqual([]);
    await expect.poll(total).toBe(before);
    await expect(tree.locator("#layout")).toBeEnabled();
    await expect(tree.locator("#cluster-depth")).toBeHidden();
  });

  test("the depth select offers every level the bundle has, and only while clustered", async ({ deep }) => {
    // deeppath's one concept sits at alpha/bravo/charlie/delta/echo — five levels.
    await expect(deep.locator("#cluster-depth")).toBeHidden();

    await deep.locator("#btn-cluster").click();
    await expect(deep.locator("#cluster-depth")).toBeVisible();
    expect(await deep.locator("#cluster-depth").evaluate((el) => [ ...el.options ].map((o) => o.value)))
      .toEqual([ "1", "2", "3", "4", "5" ]);

    await deep.locator("#cluster-depth").selectOption("5");
    await expect.poll(() => parentOf(deep, "alpha/bravo/charlie/delta/echo/service"))
      .toBe("box::alpha/bravo/charlie/delta/echo");
  });

  test("box labels are the last path segment, the root spelled (root)", async ({ tree }) => {
    await tree.locator("#btn-cluster").click();
    await tree.locator("#cluster-depth").selectOption("2");

    await expect.poll(() => tree.evaluate(() => cy.getElementById("box::platform/services").data("label"))).toBe("services/");
    expect(await tree.evaluate(() => cy.getElementById("box::platform").data("label"))).toBe("platform/");
    expect(await tree.evaluate(() => cy.getElementById("box::.").data("label"))).toBe("(root)");
  });

  test("tapping a nested box opens that directory's map, not its first segment's", async ({ tree }) => {
    await tree.locator("#btn-cluster").click();
    await tree.locator("#cluster-depth").selectOption("2");
    await expect.poll(() => boxes(tree)).toContain("box::platform/services");

    await tree.evaluate(() => { cy.getElementById("box::platform/services").emit("tap"); });
    await expect(tree.locator("#side-body")).toContainText("platform/services");
  });
});
