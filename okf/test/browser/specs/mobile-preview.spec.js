import { test, expect, base, bootGraph, clickNode } from "../helpers.js";
import { hostilePage, HOSTILE_PORT } from "../paths.js";

// The touch preview card, and the takeover it exists to end.
//
// At ≤768px `.graph-body[data-side=default]` is `0 1fr`, so opening the
// inspector measures #stage at width 0 — a tap on a dot did not cover the
// graph, it *deleted* it. Exploring a phone became open → read → close → tap
// the next dot, and you could never see a concept and its neighbourhood at
// once. The card is the answer: the concept's head rides at the bottom, the
// graph keeps every pixel above it and stays live.
//
// The assertions that matter are computed layout and *counts of things that
// happened*, not strings: stage width, the selected node's rendered y against
// the card's top edge, and how many distinct transforms the card wears while it
// is on screen. That last one is the load-bearing oddity — the card must not
// animate, and "nothing animates" has no end-state observable at all.
//
// mobile-layout.spec.js owns the ≤768px chrome (the drawer, the ⚙ sheet); this
// file owns what a tap on a dot does at that width.

const card = (page) => page.locator("#preview");
const PHONE = { width: 375, height: 720 };

// The two nodes every walk below uses: any two distinct concepts. Read from
// Cytoscape rather than the fixture, so a fixture edit cannot silently retarget
// the spec at a folder node.
const twoNodes = (page) =>
  page.evaluate(() => cy.nodes().filter((n) => !n.isParent()).map((n) => n.id()).slice(0, 2));

// Everything the card is, at one instant. Read in a single evaluate: the card,
// the canvas and Cytoscape's camera all move together, and sampling them across
// three round-trips compares three different moments.
const readCard = (page) => page.evaluate(() => {
  const el = document.getElementById("preview");
  const r = el.getBoundingClientRect();
  const st = document.getElementById("stage").getBoundingClientRect();
  return {
    display: getComputedStyle(el).display,
    top: Math.round(r.top), left: Math.round(r.left),
    transform: el.style.transform,
    snap: el.getAttribute("data-snap"),
    title: (el.querySelector(".pv-title") || {}).textContent || "",
    meta: (el.querySelector(".pv-meta") || {}).textContent || "",
    stageW: Math.round(st.width), stageH: Math.round(st.height),
    side: document.querySelector(".graph-body").getAttribute("data-side"),
  };
});

test.describe("touch preview — the takeover, ended (375px)", () => {
  test.use({ viewport: PHONE });

  test("a tap fills the card and the graph keeps every pixel it had", async ({ app }) => {
    // The regression this whole feature exists to fix. Before: #stage measured
    // 0×609 on an iPhone viewport the moment a dot was tapped.
    const before = await readCard(app);
    expect(before.display, "the card is inert until something is selected").toBe("none");
    const [ a ] = await twoNodes(app);

    await clickNode(app, a);

    const after = await readCard(app);
    expect(after.display).toBe("flex");
    expect(after.stageW, "the graph is still there — this is the bug").toBeGreaterThan(0);
    expect(after.stageW, "and it is the full width, not a sliver").toBe(before.stageW);
    expect(after.side, "the inspector never opens on the card branch").toBe("hidden");
    expect(after.title.length, "the card carries the concept's head").toBeGreaterThan(0);
    await expect(app.locator("#preview .pv-meta")).toContainText(/\d+ links? out · \d+ in/);
  });

  test("the selected node is above the card, not behind the thing describing it", async ({ app }) => {
    // cy.center() would park the node in the middle of the canvas, which at peek
    // is under the card. The camera aims at the middle of the *visible band*.
    const [ a ] = await twoNodes(app);
    await clickNode(app, a);
    await expect(card(app)).toBeVisible();

    // The pan is animated (420ms), so let it land before reading a position.
    await expect.poll(() => app.evaluate((id) => {
      const el = document.getElementById("preview");
      const r = cy.container().getBoundingClientRect();
      return cy.getElementById(id).renderedPosition().y + r.top < el.getBoundingClientRect().top;
    }, a), { timeout: 6000 }).toBe(true);
  });

  test("dot to dot swaps the card in place — one card, one transform", async ({ app }) => {
    // The original bug report in miniature: every swap used to replay a 0.26s
    // entrance, so exploring read as a slideshow. The card now stays put and its
    // contents change under it.
    const [ a, b ] = await twoNodes(app);
    await clickNode(app, a);
    const first = await readCard(app);

    await clickNode(app, b);
    const second = await readCard(app);

    expect(second.title, "the head is the new concept's").not.toBe(first.title);
    expect(second.transform, "and the card did not move to say so").toBe(first.transform);
    expect(await app.locator("#preview").count(), "one card, reused").toBe(1);
  });

  test("a miss on bare canvas leaves the card up", async ({ app }) => {
    // It used to dismiss. On a phone the dots are small and the misses constant,
    // so the card kept vanishing and the next dot replayed the entrance. Both
    // halves of that are gone; dismissing is explicit.
    const [ a ] = await twoNodes(app);
    await clickNode(app, a);
    await expect(card(app)).toBeVisible();

    await app.evaluate(() => { cy.emit("tap"); });
    await app.waitForTimeout(150);

    await expect(card(app)).toBeVisible();
  });

  test("the card wears exactly one transform for its whole life on screen", async ({ app }) => {
    // "Nothing animates" has no end-state observable — a card that slid in and a
    // card that appeared land in the same place. So watch the cause: every
    // transform the element takes while it is up. A transition, a rAF stage or a
    // close timer all show up here as a second value.
    await app.evaluate(() => {
      window.__pvT = [];
      const el = document.getElementById("preview");
      new MutationObserver(() => {
        if (!el.classList.contains("up")) return;
        const t = el.style.transform;
        if (t) window.__pvT.push(t);
      }).observe(el, { attributes: true, attributeFilter: [ "style", "class" ] });
    });

    const [ a, b ] = await twoNodes(app);
    await clickNode(app, a);
    await clickNode(app, b);
    await app.locator("#pv-x").click();
    await expect(card(app)).toBeHidden();
    await clickNode(app, a);
    await expect(card(app)).toBeVisible();

    const values = await app.evaluate(() => [ ...new Set(window.__pvT) ]);
    expect(values.length, `open, swap, close and reopen took ${values.length} transforms: ${values}`).toBe(1);
  });

  test("at full the card's own body scrolls and the card stays put", async ({ app }) => {
    // A concept with links, so the body has something taller than the pane.
    const a = await app.evaluate(() =>
      cy.nodes().filter((n) => !n.isParent() && (outL[n.id()] || []).length > 0)[0].id());
    await clickNode(app, a);
    await app.locator("#pv-grip").focus();
    await app.keyboard.press("ArrowUp");
    await app.keyboard.press("ArrowUp");
    await expect(card(app)).toHaveAttribute("data-snap", "full");
    // The body only exists past peek, and it loads lazily.
    await expect(app.locator("#pv-body .rel").first()).toBeVisible();

    const at = await readCard(app);
    const pane = await app.evaluate(() => {
      const b = document.getElementById("pv-body");
      const s = getComputedStyle(b);
      b.scrollTop = 400;
      // touch-action is the whole of it: the drag listens on the grip and the
      // head, and `touch-action:none` there is what stops the browser claiming
      // the gesture for a scroll. Applied to the body as well it would take the
      // body's own scrolling with it, and at `full` that is all there is to do.
      return { overflow: s.overflowY, touch: s.touchAction, top: b.scrollTop };
    });
    const after = await readCard(app);

    expect(pane.overflow, "the body is a scroll container of its own").toBe("auto");
    expect(pane.touch, "and the drag surface does not extend over it").not.toBe("none");
    expect(after.transform, "scrolling the body must not drag the card").toBe(at.transform);
    expect(after.snap).toBe("full");
  });

  test("a Links to row walks to that concept without closing the card", async ({ app }) => {
    // Walking the neighbourhood from inside the card is what makes exploring
    // continuous — the alternative is close, hunt for the dot, tap, reopen.
    const from = await app.evaluate(() =>
      cy.nodes().filter((n) => !n.isParent() && (outL[n.id()] || []).length > 0)[0].id());
    await clickNode(app, from);
    await app.locator("#pv-grip").focus();
    await app.keyboard.press("ArrowUp");
    await expect(card(app)).toHaveAttribute("data-snap", "half");

    const before = await readCard(app);
    const camBefore = await app.evaluate(() => window.__camCenters);
    await app.locator("#pv-body [data-go]").first().click();

    const after = await readCard(app);
    expect(after.title, "the head is the row you tapped").not.toBe(before.title);
    expect(after.snap, "and the card stays where you put it").toBe("half");
    await expect(card(app)).toBeVisible();
    await expect.poll(() => app.evaluate(() => window.__camCenters), { timeout: 4000 })
      .toBeGreaterThan(camBefore);
  });

  test("✕ and Esc both dismiss it, and Esc clears the selection with it", async ({ app }) => {
    const [ a, b ] = await twoNodes(app);
    await clickNode(app, a);
    await app.locator("#pv-x").click();
    await expect(card(app)).toBeHidden();

    await clickNode(app, b);
    await expect(card(app)).toBeVisible();
    await app.keyboard.press("Escape");

    await expect(card(app)).toBeHidden();
    expect(await app.evaluate(() => cy.elements(".hl").length), "the highlight goes with it").toBe(0);
  });

  test("a downward drag on the grip throws it away", async ({ app }) => {
    const [ a ] = await twoNodes(app);
    await clickNode(app, a);
    const grip = await app.locator("#pv-grip").boundingBox();

    await app.mouse.move(grip.x + grip.width / 2, grip.y + grip.height / 2);
    await app.mouse.down();
    for (let y = 40; y <= 320; y += 40) await app.mouse.move(grip.x + grip.width / 2, grip.y + y);
    await app.mouse.up();

    await expect(card(app)).toBeHidden();
  });

  test("tapping the head toggles peek and half", async ({ app }) => {
    const [ a ] = await twoNodes(app);
    await clickNode(app, a);
    await expect(card(app)).toHaveAttribute("data-snap", "peek");

    await app.locator("#pv-head").click();
    await expect(card(app)).toHaveAttribute("data-snap", "half");

    await app.locator("#pv-head").click();
    await expect(card(app)).toHaveAttribute("data-snap", "peek");
  });

  test("a folder tap fills the card too, instead of doing nothing at all", async ({ app }) => {
    // showDir/showLog write into #side-body, which on the card branch is a panel
    // nobody can see — so tree and cluster modes were dead on touch: not a crash,
    // just a tap with no visible answer anywhere.
    await app.locator("#btn-controls").click();
    await app.locator("#btn-tree").click();
    await expect(app.locator("#btn-tree")).toHaveAttribute("aria-pressed", "true");
    await expect.poll(() => app.evaluate(() => cy.nodes(".dir").length)).toBeGreaterThan(0);

    const dir = await app.evaluate(() => cy.nodes(".dir")[0].id());
    await clickNode(app, dir);

    await expect(card(app)).toBeVisible();
    await expect(app.locator("#preview .pv-title")).not.toBeEmpty();
    await expect(app.locator("#preview .pv-meta")).toContainText(/concepts?/);
    expect((await readCard(app)).stageW, "and the graph is still whole").toBeGreaterThan(0);
  });

  test("the canvas hint stands down under the card rather than sitting behind it", async ({ app }) => {
    await expect(app.locator(".ghint")).toBeVisible();
    const [ a ] = await twoNodes(app);
    await clickNode(app, a);
    await expect(app.locator(".ghint")).toBeHidden();
  });

  test("nothing the card does makes the page scroll sideways", async ({ app }) => {
    const [ a ] = await twoNodes(app);
    await clickNode(app, a);
    await app.locator("#pv-grip").focus();
    await app.keyboard.press("ArrowUp");
    expect(await app.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(375);
  });
});

test.describe("touch preview — a portrait tablet is not a stretched phone (820px)", () => {
  test.use({ viewport: { width: 820, height: 1180 } });

  test("the card runs here too, but starts where the rail ends", async ({ app }) => {
    // The rail only folds at 768px, so a full-bleed card on a portrait tablet
    // would bury the Stats rail item — the takeover again, just shorter.
    const [ a ] = await twoNodes(app);
    await clickNode(app, a);

    const c = await readCard(app);
    expect(c.display).toBe("flex");
    expect(c.left, "inset past the 76px rail").toBe(76);
    expect(c.stageW).toBeGreaterThan(0);
    expect(c.side).toBe("hidden");
  });

  test("the inspector toggle is gone, rather than opening an empty panel", async ({ app }) => {
    // #btn-panel and `\` still reached setSide here, and the panel they opened
    // showed the "Select a concept…" placeholder forever, because show() never
    // runs on this branch.
    await expect(app.locator("#btn-panel")).toBeHidden();
    const [ a ] = await twoNodes(app);
    await clickNode(app, a);
    await app.keyboard.press("\\");
    await expect(app.locator(".graph-body")).toHaveAttribute("data-side", "hidden");
  });

  test("no sideways scroll at tablet width either", async ({ app }) => {
    const [ a ] = await twoNodes(app);
    await clickNode(app, a);
    expect(await app.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(820);
  });
});

test.describe("touch preview — the desktop is untouched (1600px)", () => {
  test.use({ viewport: { width: 1600, height: 1000 } });

  test("a click still opens the side inspector and the card never appears", async ({ app }) => {
    const width = await app.evaluate(() => document.documentElement.scrollWidth);
    const [ a ] = await twoNodes(app);
    await clickNode(app, a);

    await expect(app.locator(".graph-body")).toHaveAttribute("data-side", "default");
    await expect(app.locator("#side-body .title")).toBeVisible();
    const c = await readCard(app);
    expect(c.display, "display:none, so it contributes no layout at all").toBe("none");
    expect(await app.evaluate(() => document.documentElement.scrollWidth),
      "and does not widen the document — the bug the Bundles panel already taught").toBe(width);
  });
});

// The card is a second surface rendering the same authored strings, which is
// exactly where the sanitizer rule earns its keep: a new render path that
// reaches innerHTML without going through esc() and renderMarkdown reopens the
// hole the template closed once. sanitization.spec.js proves the inspector
// against fixtures/hostile; this proves the card, at a phone width, with the
// same payloads and the same flags — the bundle sets them on `window` itself,
// so the assertion is "the script did not run", not "the markup looks clean".
const FLAGS = [
  "__xssInline", "__xssImg", "__xssSvg", "__xssFrame",
  "__xssClick", "__xssHover", "__xssHref", "__xssForm", "__xssTitle", "__xssTag",
];

const hostile = base.extend({
  phone: async ({ page }, use, testInfo) => {
    const url = testInfo.project.name === "static"
      ? `file://${hostilePage}`
      : `http://127.0.0.1:${HOSTILE_PORT}/`;
    await page.setViewportSize(PHONE);
    await page.addInitScript(() => {
      try { localStorage.setItem("okf-hello", "1"); } catch (e) {}
    });
    await page.goto(url);
    await bootGraph(page);
    await use(page);
  },
});

hostile.describe("touch preview — hostile input", () => {
  hostile("a title of markup is shown as text, and the body is sanitized", async ({ phone }) => {
    // `attributes` carries a title that closes the script tag it is inlined in;
    // `payload` carries the bodies. Both reach the card.
    await phone.evaluate(() => { cy.getElementById("attributes").emit("tap"); });
    await expect(phone.locator("#preview")).toBeVisible();
    expect(await phone.locator("#preview .pv-title *").count(), "the title is text, not markup").toBe(0);
    await expect(phone.locator("#preview .pv-title")).toContainText("<script>");

    await phone.evaluate(() => { cy.getElementById("payload").emit("tap"); });
    await phone.locator("#pv-grip").focus();
    await phone.keyboard.press("ArrowUp");

    // The prose assertion is load-bearing: a body that failed to render at all
    // would pass every "no script ran" check below and look like a sanitizer.
    await expect(phone.locator("#pv-md")).toContainText("SAFE-MARKER-9F3A");
    expect(await phone.evaluate((names) => names.filter((n) => window[n] !== undefined), FLAGS)).toEqual([]);
    await expect(phone.locator("#pv-md script")).toHaveCount(0);
    await expect(phone.locator("#pv-md iframe")).toHaveCount(0);
  });
});
