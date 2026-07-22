import { test as base, expect } from "../helpers.js";
import path from "node:path";
import { PANEL_PORT, RO_PORT, panelDir } from "../paths.js";

// The Bundles panel — the registry, on the graph page. Before it, changing
// which bundle `/` opens meant leaving the graph for `/b/`, and knowing that
// `/b/` existed at all. The ⚙ in the rail is the affordance; the slide-over is
// the surface.
//
// hub_bundles_test.rb proves what GET /bundles answers and hub_writes_test.rb
// proves what each POST does to the file and to the served set. What only a
// browser can prove is everything in between: that a panel parked off-canvas
// does not widen the document, that a row's menu opens where it belongs, that
// Rename takes the row over and comes back with the new name on it, and that a
// read-only server explains itself instead of quietly having no buttons.
//
// Serial, and every spec puts back what it changed — one live registry.
const PANEL = `http://127.0.0.1:${PANEL_PORT}/b/one/`;

const test = base.extend({
  bp: async ({ page }, use) => {
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e)));
    page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
    await page.addInitScript(() => {
      try { localStorage.setItem("okf-hello", "1"); localStorage.setItem("okf-swseen", "1"); } catch (e) {}
    });
    await page.goto(PANEL);
    await use(page);
    if (errors.length) throw new Error(`page reported ${errors.length} console/page error(s):\n  ${errors.join("\n  ")}`);
  },
});

test.describe.configure({ mode: "serial" });

// One project only: `okf render` bakes a single bundle and knows of no set, so
// there is no static counterpart to prove anything about. The panel's absence
// there is asserted from the main fixture instead, at the bottom of this file.
test.skip(() => test.info().project.name !== "server",
  "the Bundles panel exists only under a served hub");

const open = async (page) => {
  await page.locator("#btn-ws").click();
  await expect(page.locator("#ws")).toBeVisible();
};

const rowFor = (page, slug) => page.locator(".ws-row").filter({ hasText: `@${slug}` });

test.describe("bundles panel — what it shows", () => {
  test("the ⚙ in the rail opens a slide-over that says what it is and how much", async ({ bp }) => {
    await expect(bp.locator("#ws")).toBeHidden();

    await open(bp);

    await expect(bp.locator("#ws h3")).toHaveText("Bundles");
    await expect(bp.locator("#ws-sub")).toHaveText("3 bundles in the registry");
    await expect(bp.locator(".ws-row")).toHaveCount(3);
  });

  test("a row carries every fact a reader chooses between bundles by", async ({ bp }) => {
    await open(bp);
    const row = rowFor(bp, "two");

    // Relative on purpose — every page lives at <prefix>/b/<slug>/, so "../two/"
    // reaches its sibling under any mount. Resolved is what a click follows.
    expect(await row.locator(".ws-title").evaluate((a) => a.href)).toMatch(/\/b\/two\/$/);
    // The ref is the row's name, not a note beside it: a bundle is addressed by
    // its slug, so that is what the loudest thing on the row says.
    await expect(row.locator(".ws-title")).toHaveText("@two");
    await expect(row.locator(".ws-meta")).toContainText("8 concepts");
    // The word is the message; the colour only echoes it, so a reader who
    // cannot see green loses nothing.
    await expect(row.locator(".ws-health")).toHaveText(/no problems|warning|error/);
  });

  test("the default and the one being read are each marked, and differently", async ({ bp }) => {
    await open(bp);

    await expect(rowFor(bp, "one").locator(".ws-pill.def")).toHaveText("default");
    await expect(rowFor(bp, "one").locator(".ws-pill.cur")).toHaveText("current");
    await expect(rowFor(bp, "two").locator(".ws-pill")).toHaveCount(0,
      "a row that is neither wears neither");
  });

  test("the wordmark is the way back to every bundle", async ({ bp }) => {
    expect(await bp.locator("a.rail-brand").evaluate((a) => a.href)).toMatch(/\/b\/$/);
  });
});

// The bug the prototype found, and the reason this file asserts a number nobody
// looks at: a slide-over parked at translateX(100%) still occupies layout, and
// #views does not clip (the Filters panel gets away with it only because #stage
// does). Closed, it widened the document by its own 340px — a horizontal
// scrollbar on every page, from a panel nobody had opened.
test.describe("bundles panel — the panel that widened the page", () => {
  test("a closed panel takes no layout, and the document does not scroll sideways", async ({ bp }) => {
    await expect(bp.locator("#ws")).toBeHidden();

    const { scrollW, clientW } = await bp.evaluate(() => ({
      scrollW: document.documentElement.scrollWidth,
      clientW: document.documentElement.clientWidth,
    }));
    expect(scrollW).toBe(clientW);
  });

  test("nor does one mid-slide, which is where it actually showed", async ({ bp }) => {
    // Sampled across the whole animation, not after it. The panel is only off
    // the right edge *while it is moving*, so a measurement taken once it has
    // landed is a measurement taken after the scrollbar has gone.
    await bp.locator("#btn-ws").click();
    const worst = await bp.evaluate(async () => {
      const doc = document.documentElement;
      let max = 0;
      for (let i = 0; i < 30; i++) {
        max = Math.max(max, doc.scrollWidth);
        await new Promise((r) => requestAnimationFrame(r));
      }
      return { max, clientW: doc.clientWidth };
    });
    await expect(bp.locator("#ws")).toBeVisible();
    expect(worst.max).toBe(worst.clientW);
  });

  test("closed means display:none, not merely off-canvas", async ({ bp }) => {
    // The fix, stated as the fix: `hidden` while closed, so it is out of the
    // box entirely rather than parked beside it.
    await expect(bp.locator("#ws")).toHaveAttribute("hidden", "");
    await open(bp);
    await expect(bp.locator("#ws")).not.toHaveAttribute("hidden", "");
  });
});

test.describe("bundles panel — the menu", () => {
  test("each row carries one ⋯, and the verbs live in its menu", async ({ bp }) => {
    await open(bp);
    const row = rowFor(bp, "two");

    await row.locator(".ws-menu-btn").click();

    const menu = bp.locator(".ws-menu");
    await expect(menu.getByRole("button", { name: "Make default" })).toBeEnabled();
    await expect(menu.getByRole("button", { name: /Rename/ })).toBeVisible();
    await expect(menu.getByRole("button", { name: /Remove/ })).toBeVisible();
  });

  test("the default row's Make default is disabled, and says why", async ({ bp }) => {
    await open(bp);

    await rowFor(bp, "one").locator(".ws-menu-btn").click();

    const item = bp.locator(".ws-menu").getByRole("button", { name: /default/ });
    await expect(item).toBeDisabled();
    await expect(item).toHaveText(/Already the default/);
  });

  test("esc peels one layer: the menu first, then the panel", async ({ bp }) => {
    // An open menu covers the row beneath it, so esc is the way out — and it
    // must not take the whole panel with it, nor answer nothing at all.
    await open(bp);
    await rowFor(bp, "two").locator(".ws-menu-btn").click();
    await expect(bp.locator(".ws-menu")).toHaveCount(1);

    await bp.keyboard.press("Escape");
    await expect(bp.locator(".ws-menu")).toHaveCount(0);
    await expect(bp.locator("#ws")).toBeVisible("the panel is still there — only the menu closed");

    await bp.keyboard.press("Escape");
    await expect(bp.locator("#ws")).toBeHidden();
  });

  test("two menus are never open at once", async ({ bp }) => {
    await open(bp);
    await rowFor(bp, "two").locator(".ws-menu-btn").click();
    await expect(bp.locator(".ws-menu")).toHaveCount(1);

    await bp.keyboard.press("Escape");
    await rowFor(bp, "three").locator(".ws-menu-btn").click();

    await expect(bp.locator(".ws-menu")).toHaveCount(1);
    await expect(bp.locator('.ws-menu-btn[aria-expanded="true"]')).toHaveCount(1);
  });
});

// A hub bound to anything but loopback is read-only, full stop — there is no
// flag that opens it. The panel's job there is not to hide quietly: hidden controls with
// no explanation read as a broken page, and the reader cannot tell a permission
// from a bug. Its own fixture, on a real 0.0.0.0 bind, so this proves the rule's
// actual effect rather than a simulation of it.
const roTest = base.extend({
  ro: async ({ page }, use) => {
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e)));
    page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
    await page.addInitScript(() => {
      try { localStorage.setItem("okf-hello", "1"); localStorage.setItem("okf-swseen", "1"); } catch (e) {}
    });
    await page.goto(`http://127.0.0.1:${RO_PORT}/b/one/`);
    await use(page);
    if (errors.length) throw new Error(`page reported ${errors.length} console/page error(s):\n  ${errors.join("\n  ")}`);
  },
});

roTest.describe("bundles panel — read-only", () => {
  roTest.skip(() => roTest.info().project.name !== "server", "a hub is a served thing");

  roTest("the page holds no token it may not use", async ({ ro }) => {
    expect(await ro.evaluate(() => MANAGE_TOKEN)).toBeNull();
    // and the panel still opens: the list is worth reading either way
    expect(await ro.evaluate(() => MANAGE_ROOT)).not.toBeNull();
  });

  roTest("every fact stays, and every control goes", async ({ ro }) => {
    await ro.locator("#btn-ws").click();
    await expect(ro.locator("#ws")).toBeVisible();

    await expect(ro.locator(".ws-row")).toHaveCount(3);
    await expect(ro.locator(".ws-row").first().locator(".ws-health")).toBeVisible();
    // nothing here changes anything
    await expect(ro.locator(".ws-menu-btn")).toHaveCount(0);
  });

  roTest("and a sentence says why, and how", async ({ ro }) => {
    await ro.locator("#btn-ws").click();

    const note = ro.locator(".ws-ro-note");
    await expect(note).toContainText("Read-only");
    await expect(note).toContainText("loopback");
    // the way in is named, not left to be guessed
    await expect(note).toContainText("--read-only");
    await expect(note).toContainText("okf registry");
  });
});

test.describe("bundles panel — where it does not belong", () => {
  test("no registry behind the page means no ⚙ at all", async ({ app }) => {
    // The main fixture is a single-bundle server; neither it nor the baked file
    // has a registry, so there is nothing here to manage. The button stays in
    // the markup and stays hidden — the same contract #btn-switch keeps, and
    // one revealed by the same null.
    await expect(app.locator("#btn-ws")).toBeHidden();
    expect(await app.evaluate(() => MANAGE_ROOT)).toBeNull();
  });

  test("the footer says who adds a bundle, because the panel does not", async ({ bp }) => {
    await open(bp);

    await expect(bp.locator(".ws-foot")).toContainText("okf registry set");
    await expect(bp.locator(".ws-foot")).toContainText("terminal");
    await expect(bp.locator("#ws").getByRole("button", { name: /^Add/ })).toHaveCount(0,
      "registering is the agent's act, and the panel does not pretend otherwise");
  });
});

test.describe("bundles panel — acting on a row", () => {
  test("Rename takes over the row, and Cancel puts it back untouched", async ({ bp }) => {
    await open(bp);
    const row = rowFor(bp, "two");
    await row.locator(".ws-menu-btn").click();
    await bp.locator(".ws-menu").getByRole("button", { name: /Rename/ }).click();

    await expect(row.locator(".ws-slug-edit")).toBeFocused();
    await expect(row.locator(".ws-hint")).toBeVisible();

    await row.getByRole("button", { name: "Cancel" }).click();

    await expect(row.locator(".ws-slug-edit")).toHaveCount(0);
    await expect(rowFor(bp, "two")).toHaveCount(1);
  });

  test("Rename saves, and the whole list comes back knowing the new name", async ({ bp }) => {
    await open(bp);
    await rowFor(bp, "three").locator(".ws-menu-btn").click();
    await bp.locator(".ws-menu").getByRole("button", { name: /Rename/ }).click();
    await rowFor(bp, "three").locator(".ws-slug-edit").fill("renamed");
    await rowFor(bp, "three").getByRole("button", { name: "Save" }).click();

    await expect(bp.locator("#ws-flash")).toContainText("@renamed");
    expect(await rowFor(bp, "renamed").locator(".ws-title").evaluate((a) => a.href)).toMatch(/\/b\/renamed\/$/);
    await expect(rowFor(bp, "three")).toHaveCount(0);

    // put it back
    await rowFor(bp, "renamed").locator(".ws-menu-btn").click();
    await bp.locator(".ws-menu").getByRole("button", { name: /Rename/ }).click();
    await rowFor(bp, "renamed").locator(".ws-slug-edit").fill("three");
    await rowFor(bp, "renamed").getByRole("button", { name: "Save" }).click();
    await expect(rowFor(bp, "three")).toHaveCount(1);
  });

  test("Make default moves the badge, and the server agrees", async ({ bp }) => {
    await open(bp);
    await rowFor(bp, "two").locator(".ws-menu-btn").click();
    await bp.locator(".ws-menu").getByRole("button", { name: "Make default" }).click();

    await expect(rowFor(bp, "two").locator(".ws-pill.def")).toHaveText("default");
    await expect(rowFor(bp, "one").locator(".ws-pill.def")).toHaveCount(0);

    const landed = await bp.request.get(`http://127.0.0.1:${PANEL_PORT}/`, { maxRedirects: 0 });
    expect(landed.headers().location).toMatch(/\/b\/two\/$/);

    // put it back
    await rowFor(bp, "one").locator(".ws-menu-btn").click();
    await bp.locator(".ws-menu").getByRole("button", { name: "Make default" }).click();
    await expect(rowFor(bp, "one").locator(".ws-pill.def")).toHaveText("default");
  });

  test("Remove states what it will and will not do, and Cancel is a real way out", async ({ bp }) => {
    await open(bp);
    const row = rowFor(bp, "two");
    await row.locator(".ws-menu-btn").click();
    await bp.locator(".ws-menu").getByRole("button", { name: /Remove/ }).click();

    // No armed link, no timed revert: a strip that says the consequence, and
    // says the one thing a reader actually fears is *not* going to happen.
    await expect(row.locator(".ws-confirm")).toContainText("@two");
    await expect(row.locator(".ws-confirm")).toContainText("The folder stays where it is");

    await row.getByRole("button", { name: "Cancel" }).click();

    await expect(row.locator(".ws-confirm")).toHaveCount(0);
    await expect(rowFor(bp, "two")).toHaveCount(1, "nothing was removed by looking at it");
  });

  test("Remove removes, and the bundle stops being served", async ({ bp }) => {
    await open(bp);
    await rowFor(bp, "three").locator(".ws-menu-btn").click();
    await bp.locator(".ws-menu").getByRole("button", { name: /Remove/ }).click();
    await rowFor(bp, "three").locator(".ws-confirm").getByRole("button", { name: "Remove" }).click();

    await expect(rowFor(bp, "three")).toHaveCount(0);
    await expect(bp.locator("#ws-sub")).toHaveText("2 bundles in the registry");
    const gone = await bp.request.get(`http://127.0.0.1:${PANEL_PORT}/b/three/`);
    expect(gone.status()).toBe(404);
  });

  test("with nothing left, the panel says so and names the way out", async ({ bp }) => {
    // An empty list rendering *nothing* reads as a broken page. It is a real
    // state — the one a fresh install is in — and the only way to reach it is
    // to remove the last row while looking at it, so this spec goes there and
    // puts the registry back afterwards. (A hub with an empty registry cannot
    // stand in: it serves no bundle, so there is no page to open a panel from.)
    await open(bp);
    for (const slug of [ "two", "one" ]) {
      await rowFor(bp, slug).locator(".ws-menu-btn").click();
      await bp.locator(".ws-menu").getByRole("button", { name: /Remove/ }).click();
      await rowFor(bp, slug).locator(".ws-confirm").getByRole("button", { name: "Remove" }).click();
      await expect(rowFor(bp, slug)).toHaveCount(0);
    }

    await expect(bp.locator(".ws-empty")).toBeVisible();
    await expect(bp.locator(".ws-empty")).toContainText("okf registry set");

    // Put the world back. The page is still loaded and its token is still this
    // boot's, so the same endpoint the panel uses re-registers all three — the
    // panel has no Add of its own, by design.
    for (const slug of [ "one", "two", "three" ]) {
      const res = await bp.evaluate(async ([dir, as]) => {
        const body = new URLSearchParams({ path: dir, as, token: MANAGE_TOKEN });
        const r = await fetch(MANAGE_ROOT + "registry/add", {
          method: "POST",
          headers: { accept: "application/json", "content-type": "application/x-www-form-urlencoded" },
          body: body.toString(),
        });
        return r.ok;
      }, [ path.join(panelDir, slug), slug ]);
      expect(res, `restored @${slug}`).toBe(true);
    }
  });
});
