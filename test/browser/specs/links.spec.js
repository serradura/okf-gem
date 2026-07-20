import { test, expect, clickNode } from "../helpers.js";

// A markdown body link is a GitHub-style relative path, and resolveTarget has
// to turn it into one of four things: a concept, an authored index, the log, or
// a synthesized directory listing — and disable anything that is none of them
// rather than 404 the whole page (ae7a882, ed6c0af). The inspector covers only
// concept→concept elsewhere; these drive the other resolutions, off the "See
// also" block in runbooks/rollback.md.
test.describe("body link resolution (inspector)", () => {
  test.beforeEach(async ({ app }) => {
    await clickNode(app, "runbooks/rollback");
    await expect(app.locator("#side-body #body")).toContainText("See also");
  });

  const seeAlso = (app, text) => app.locator("#side-body #body a", { hasText: text }).first();

  test("a link to index.md opens the authored map in place", async ({ app }) => {
    await seeAlso(app, "root map").click();
    // showDir('.') renders the root index.md — its type badge and its body.
    await expect(app.locator("#side-body .type")).toHaveText("index.md");
    await expect(app.locator("#side-body")).toContainText("The knowledge bundle the browser suite drives");
  });

  test("a link to log.md opens the history in place", async ({ app }) => {
    await seeAlso(app, "update log").click();
    await expect(app.locator("#side-body .type")).toContainText("update log");
    await expect(app.locator("#side-body")).toContainText("Update Log");
  });

  test("a link to a bare directory opens its synthesized listing", async ({ app }) => {
    // datasets/ has no index.md, so the directory resolves to a synthesized
    // listing of the concepts under it — not a 404, not a blank.
    await seeAlso(app, "datasets folder").click();
    await expect(app.locator("#side-body .type")).toContainText("synthesized");
    await expect(app.locator("#side-body")).toContainText("Orders");
    await expect(app.locator("#side-body")).toContainText("Customers");
  });

  test("an unresolvable link is disabled, not followed", async ({ app }) => {
    const dead = seeAlso(app, "not in this bundle");
    await dead.click();
    // The panel stays on rollback — no navigation, no 404 — and the anchor is
    // marked dead with an explanation.
    await expect(app.locator("#side-body .title")).toHaveText("Rollback");
    await expect(dead).toHaveClass(/dead/);
    await expect(dead).toHaveAttribute("title", "not a file in this bundle");
  });
});
