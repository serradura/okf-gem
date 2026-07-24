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

// Where every leaf sits, rounded. A node the cluster layout never placed keeps
// the coordinates the force layout left it at — byte-identical, which is what
// makes "did the layout reach this node?" observable at all. Asserting a node
// sits *inside* its box cannot do it: a compound parent is sized from its
// children, so that holds by construction even when nothing was laid out.
// A point on the box's own body, clear of every descendant. The band matters: a
// compound parent is only hit-testable across its middle — measured, the label
// strip at the top (~15%) and the bottom ~20% fall through to the canvas — so
// aiming outside it silently tests the background instead of the box, and a
// "dragging the box pans" assertion would pass even with the box still grabbable.
const aimAtBoxBody = (page, id) => page.evaluate((boxId) => {
  const box = cy.getElementById(boxId);
  const b = box.renderedBoundingBox();
  const kids = box.descendants().map((n) => n.renderedBoundingBox());
  for (let fy = 0.3; fy <= 0.65; fy += 0.05) {
    for (let fx = 0.1; fx <= 0.95; fx += 0.05) {
      const x = b.x1 + (b.x2 - b.x1) * fx, y = b.y1 + (b.y2 - b.y1) * fy;
      if (!kids.some((k) => x >= k.x1 && x <= k.x2 && y >= k.y1 && y <= k.y2)) return { x, y };
    }
  }
  return null;
}, id);

// Wait for the layout to stop moving things, rather than guessing at a duration.
// A fixed sleep raced the end-transition: the drag would land mid-animation, the
// animation would win, and the test failed about once in three.
// Count layout runs from before the gesture that triggers one, so "has it
// started?" is a fact rather than an inference from elapsed time. `layoutstart`,
// not `layoutstop` — measured, the latter never fires here, and polling for it
// only ever times out.
const watchLayouts = (page) => page.evaluate(() => {
  window.__layouts = 0;
  window.__before = null;
  window.__snap = () => JSON.stringify(
    cy.nodes().map((n) => [ Math.round(n.position().x), Math.round(n.position().y) ]));
  cy.on("layoutstart", () => { window.__layouts++; window.__before = window.__before || window.__snap(); });
});

// Wait for the cluster layout to have begun *and* stopped moving things. Neither
// half is enough alone: clusterLayout is async (it awaits the lazy fcose load),
// so two identical position samples taken before it starts read as "settled" and
// the drag then lands mid-tiling — a real intermittent failure, not a slow
// machine. And the layout animates to its final positions after it starts, so
// the start event alone does not mean the geometry is stable either.
const settle = async (page) => {
  // 1. the layout has begun,
  await expect.poll(() => page.evaluate(() => window.__layouts || 0),
    { timeout: 15000, intervals: [ 100 ] }).toBeGreaterThan(0);
  // 2. it has actually moved something — with animate:'end' nothing moves while
  //    fcose computes, so position samples are identical *during* the run and
  //    "stable" arrives before the tiling does. This is the step whose absence
  //    made the drag specs fail about one run in thirty,
  await expect.poll(() => page.evaluate(() => window.__snap() !== window.__before),
    { timeout: 15000, intervals: [ 100 ] }).toBe(true);
  // 3. and it has stopped moving.
  let last = null;
  await expect.poll(async () => {
    const now = await page.evaluate(() => window.__snap());
    const same = now === last;
    last = now;
    return same;
  }, { timeout: 15000, intervals: [ 250 ] }).toBe(true);
};

const positions = (page) => page.evaluate(() => Object.fromEntries(cy.nodes()
  .filter((n) => !n.isParent())
  .map((n) => [ n.id(), `${Math.round(n.position().x)},${Math.round(n.position().y)}` ])));

test.describe("cluster mode — the layout covers what a cleared filter brings back", () => {
  // The layout runs over `:visible` only — deliberately, because fcose throws on
  // a node whose label went display:none mid-run. That leaves whatever a filter
  // was hiding unplaced, and clearing the filter brings those nodes back at
  // their pre-cluster coordinates, stretching the box drawn around them.
  test("a filter narrowed before clustering does not strand the rest", async ({ tree }) => {
    await tree.locator("#search").fill("api");
    const before = await positions(tree);
    await tree.locator("#btn-cluster").click();
    await expect(tree.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "true");

    await tree.locator("#search").fill("");
    await expect.poll(async () => {
      const now = await positions(tree);
      return Object.keys(before).filter((id) => before[id] === now[id]);
    }, { timeout: 7000 }).toEqual([]);
  });

  // The sharper case: nothing visible when clustering is switched on, so the
  // layout returns early and places nobody at all.
  test("clustering while the filter matches nothing still lays out on clear", async ({ tree }) => {
    await tree.locator("#search").fill("zzzz-matches-nothing");
    const before = await positions(tree);
    await tree.locator("#btn-cluster").click();
    await expect(tree.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "true");

    await tree.locator("#search").fill("");
    await expect.poll(async () => {
      const now = await positions(tree);
      return Object.keys(before).filter((id) => before[id] === now[id]);
    }, { timeout: 7000 }).toEqual([]);
  });
});

test.describe("cluster mode — a box is scenery, not a handle", () => {
  // These two drive a real mouse gesture at a point computed from live geometry,
  // against a canvas whose layout and camera are both animating asynchronously.
  // settle() waits for the layout to start, to move something, and to stop, and
  // that removed most of it — but roughly one run in a hundred still aims at a
  // point the page has moved by the time mousedown lands, and the drag pans
  // instead of grabbing. The race is in the setup, never in the assertion: when
  // the gesture reaches the box the result is deterministic (measured 8/8 on a
  // settled canvas). So a retry re-runs the aim, not the proof — which is the one
  // case retries are legitimate. If these ever fail twice running, that is a real
  // regression and not this.
  test.describe.configure({ retries: 2 });

  // A big cluster is mostly box: its empty interior is the largest drag target on
  // the canvas. While that interior grabbed the compound node, dragging to look
  // around dragged the *directory* instead of the view, and the bigger the
  // cluster the harder the page was to navigate.
  test("dragging a box's empty interior pans the canvas, leaving the box put", async ({ tree }) => {
    await watchLayouts(tree);
    await tree.locator("#btn-cluster").click();
    await expect(tree.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "true");
    await expect.poll(() => tree.evaluate(() => cy.getElementById("box::platform").length)).toBe(1);
    await settle(tree); // geometry must be stable to aim at

    const canvas = await tree.locator("#cy").boundingBox();
    const at = await aimAtBoxBody(tree, "box::platform");
    expect(at, "the fixture must leave some empty box interior to aim at").not.toBeNull();

    const read = () => tree.evaluate(() => JSON.stringify([ cy.getElementById("box::platform").position(), cy.pan() ]));
    const [ b0, p0 ] = JSON.parse(await read());
    await tree.mouse.move(canvas.x + at.x, canvas.y + at.y);
    await tree.mouse.down();
    await tree.mouse.move(canvas.x + at.x + 60, canvas.y + at.y + 40, { steps: 8 });
    await tree.mouse.up();
    await tree.waitForTimeout(300);
    const [ b1, p1 ] = JSON.parse(await read());

    expect({ dx: Math.round(b1.x - b0.x), dy: Math.round(b1.y - b0.y) }).toEqual({ dx: 0, dy: 0 });
    expect({ dx: Math.round(p1.x - p0.x), dy: Math.round(p1.y - p0.y) }).toEqual({ dx: 60, dy: 40 });
  });

  // Moving a box is still a real gesture, just no longer the default one: the
  // common action (look around) stays unmodified and the rare one (tidy a box)
  // takes Alt. Ctrl is deliberately not the key — on macOS Ctrl+mousedown is the
  // system secondary click.
  test("Alt turns a box back into a handle, and releasing it gives the pan back", async ({ tree }) => {
    await watchLayouts(tree);
    await tree.locator("#btn-cluster").click();
    await expect(tree.locator("#btn-cluster")).toHaveAttribute("aria-pressed", "true");
    await expect.poll(() => tree.evaluate(() => cy.getElementById("box::platform").length)).toBe(1);
    await settle(tree);

    const canvas = await tree.locator("#cy").boundingBox();
    const aim = () => aimAtBoxBody(tree, "box::platform");
    const read = () => tree.evaluate(() => JSON.stringify([ cy.getElementById("box::platform").position(), cy.pan() ]));
    const drag = async (at) => {
      await tree.mouse.move(canvas.x + at.x, canvas.y + at.y);
      await tree.mouse.down();
      await tree.mouse.move(canvas.x + at.x + 60, canvas.y + at.y + 40, { steps: 8 });
      await tree.mouse.up();
      await tree.waitForTimeout(300);
    };

    const held = await aim();
    expect(held, "no free point on the box body to aim at").not.toBeNull();
    const [ b0, p0 ] = JSON.parse(await read());
    await tree.keyboard.down("Alt");
    await drag(held);
    await tree.keyboard.up("Alt");
    const [ b1, p1 ] = JSON.parse(await read());
    expect(Math.round(b1.x - b0.x) !== 0 || Math.round(b1.y - b0.y) !== 0, "Alt+drag must move the box").toBe(true);
    expect({ dx: Math.round(p1.x - p0.x), dy: Math.round(p1.y - p0.y) }).toEqual({ dx: 0, dy: 0 });

    // and the release restores panning — a modifier that leaks its state is worse
    // than no modifier
    const after = await aim();
    expect(after, "no free point on the box body after the move").not.toBeNull();
    const [ b2, p2 ] = JSON.parse(await read());
    await drag(after);
    const [ b3, p3 ] = JSON.parse(await read());
    expect({ dx: Math.round(b3.x - b2.x), dy: Math.round(b3.y - b2.y) }).toEqual({ dx: 0, dy: 0 });
    expect({ dx: Math.round(p3.x - p2.x), dy: Math.round(p3.y - p2.y) }).toEqual({ dx: 60, dy: 40 });
  });
});

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
