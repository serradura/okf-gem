import { test as base, expect } from "@playwright/test";
import { WORKSPACE_PORT, bundleDir } from "../paths.js";

// The manager with its forms live — the registry-backed hub, which is the only
// mode that has them. The integration suite proves what each POST does to the
// file and to the served set; what only a browser can prove is the part in
// between: that the disclosure opens without shoving the row it belongs to,
// that the form actually posts and comes back with the sentence, and that a
// refusal lands on a page the reader can still use.
//
// Serial, and every spec puts back what it changed. These run against one live
// registry, and a parallel rename would race a parallel remove for the same row.
const WORKSPACE = `http://127.0.0.1:${WORKSPACE_PORT}/b/`;

const test = base.extend({
  ws: async ({ page }, use) => {
    const errors = [];
    let statuses = true;
    page.on("pageerror", (e) => errors.push(String(e)));
    page.on("console", (m) => {
      if (m.type() !== "error") return;
      // A refusal *is* a 400 — the manager comes back with the reason on it
      // rather than redirecting, which is the whole point. Chromium logs the
      // status as a console error, so a spec that expects a refusal opts out of
      // that half of the watch and keeps the half that catches a real throw.
      if (!statuses && /Failed to load resource/.test(m.text())) return;
      errors.push(m.text());
    });
    await page.goto(WORKSPACE);
    page.allowRefusals = () => { statuses = false; };
    await use(page);
    if (errors.length) throw new Error(`page reported ${errors.length} console/page error(s):\n  ${errors.join("\n  ")}`);
  },
});

test.describe.configure({ mode: "serial" });

// One project only, and not for the usual reason. The manager has no static
// counterpart at all — `okf render` bakes one bundle and knows of no set, so
// there is no second mode here to prove anything about. Running it twice would
// only put the two projects on one live registry at the same time, where a
// rename in one races a remove in the other. manager.spec.js covers the page's
// read-only half, and this file owns the writes.
test.skip(() => test.info().project.name !== "server",
  "the workspace manager exists only under a served hub");

const rowFor = (page, slug) => page.locator(".row").filter({ hasText: `@${slug}` });

test.describe("workspace manager — writes", () => {
  test("a loopback server offers the forms, and every one of them is guarded", async ({ ws }) => {
    await expect(ws.locator("form")).not.toHaveCount(0);
    const forms = await ws.locator("form").count();
    await expect(ws.locator('input[name="token"]')).toHaveCount(forms);
  });

  test("the rename disclosure opens over the page, not through the row", async ({ ws }) => {
    const row = rowFor(ws, "alpha");
    const before = await row.boundingBox();

    await row.locator("summary", { hasText: "Rename" }).click();

    await expect(row.locator('input[name="to"]')).toBeVisible();
    const after = await row.boundingBox();
    expect(after.height).toBe(before.height);
    // and the row below has not moved either
    expect((await rowFor(ws, "beta").boundingBox()).y).toBe(before.y + before.height);
  });

  test("renaming an entry reports it and the row comes back renamed", async ({ ws }) => {
    await rowFor(ws, "alpha").locator("summary", { hasText: "Rename" }).click();
    await rowFor(ws, "alpha").locator('input[name="to"]').fill("handbook");
    await rowFor(ws, "alpha").locator('form[action$="registry/rename"] button').click();

    await expect(ws).toHaveURL(/\/b\/\?ok=/);
    await expect(ws.locator(".flash.ok")).toContainText("@alpha is now @handbook");
    await expect(rowFor(ws, "handbook")).toHaveCount(1);
    await expect(rowFor(ws, "handbook").locator(".name")).toHaveAttribute("href", /\/b\/handbook\/$/);

    // put it back, so the next spec starts where this one did
    await rowFor(ws, "handbook").locator("summary", { hasText: "Rename" }).click();
    await rowFor(ws, "handbook").locator('input[name="to"]').fill("alpha");
    await rowFor(ws, "handbook").locator('form[action$="registry/rename"] button').click();
    await expect(rowFor(ws, "alpha")).toHaveCount(1);
  });

  test("making the other bundle default moves the marker and the button", async ({ ws }) => {
    await rowFor(ws, "beta").locator('form[action$="registry/default"] button').click();

    await expect(ws.locator(".flash.ok")).toContainText("@beta is now the bundle this server opens");
    await expect(rowFor(ws, "beta").locator(".def")).toHaveText("default");
    await expect(rowFor(ws, "beta").locator('form[action$="registry/default"]')).toHaveCount(0);
    await expect(rowFor(ws, "alpha").locator('form[action$="registry/default"]')).toHaveCount(1);

    await rowFor(ws, "alpha").locator('form[action$="registry/default"] button').click();
    await expect(rowFor(ws, "alpha").locator(".def")).toHaveText("default");
  });

  test("Remove asks before it acts, and closing the disclosure is the way out", async ({ ws }) => {
    const row = rowFor(ws, "beta");
    await row.locator("summary", { hasText: "Remove" }).click();

    await expect(row.locator(".warn-copy")).toContainText("The folder stays where it is");

    await row.locator("summary", { hasText: "Remove" }).click();
    await expect(row.locator(".warn-copy")).toBeHidden();
    await expect(rowFor(ws, "beta")).toHaveCount(1, "nothing was removed by looking at it");
  });

  test("adding a folder by path puts a whole row on the page, mount and all", async ({ ws }) => {
    // Registering only records where a bundle is, so pointing at the committed
    // fixture writes nothing to it — and the row that comes back is the proof
    // the hub rebuilt, since a stale set could not have counted its concepts.
    await ws.locator("#add-path").fill(bundleDir);
    await ws.locator("#add-as").fill("added");
    await ws.locator('.addbox button[type="submit"]').click();

    await expect(ws.locator(".flash.ok")).toContainText("@added is registered");
    const row = rowFor(ws, "added");
    await expect(row.locator(".name")).toHaveAttribute("href", /\/b\/added\/$/);
    await expect(row.locator(".f-count")).toHaveText("8 concepts");
    await expect(row).toHaveAttribute("data-health", "ok");
  });

  test("removing it takes the row away and leaves the folder alone", async ({ ws }) => {
    const row = rowFor(ws, "added");
    await row.locator("summary", { hasText: "Remove" }).click();
    await row.locator('form[action$="registry/remove"] button').click();

    await expect(ws.locator(".flash.ok")).toContainText("Its folder is untouched");
    await expect(rowFor(ws, "added")).toHaveCount(0);
    // the mount goes with it — the hub rebuilt, it did not merely redraw
    const gone = await ws.request.get(`http://127.0.0.1:${WORKSPACE_PORT}/b/added/`);
    expect(gone.status()).toBe(404);
  });

  test("a path that is not a bundle is refused on the page, and nothing is added", async ({ ws }) => {
    ws.allowRefusals();
    const before = await ws.locator(".row").count();

    await ws.locator("#add-path").fill("/definitely/not/here");
    await ws.locator('.addbox button[type="submit"]').click();

    await expect(ws.locator(".flash.err")).toContainText("not a directory");
    await expect(ws.locator(".row")).toHaveCount(before);
    await expect(ws.locator("#add-path")).toBeVisible("the form is still there to correct");
  });
});
