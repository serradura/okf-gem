import { test, expect, sideState, clickNode, visibleNodeIds } from "../helpers.js";

// The inspector is where the two render modes diverge most: served live it
// fetches /node and /node/meta, statically it reads EMBED. Both projects run
// every one of these, which is the point.
test.describe("inspector", () => {
  test("clicking a node opens the panel and fills it", async ({ app }) => {
    await clickNode(app, "services/gateway");
    await expect(app.locator(".graph-body")).toHaveAttribute("data-side", "default");
    await expect(app.locator("#btn-panel")).toHaveAttribute("aria-pressed", "true");
    await expect(app.locator("#side")).toHaveCSS("width", "380px");

    const body = app.locator("#side-body");
    await expect(body).toContainText("Gateway");
    await expect(body).toContainText("Service");
    await expect(body).toContainText("The public edge that terminates TLS");
  });

  test("the panel lists both link directions with their counts", async ({ app }) => {
    // gateway links to billing, deploy, rollback; charter, billing, deploy and
    // rollback link back. Direction is the thing that silently inverts.
    await clickNode(app, "services/gateway");
    const body = app.locator("#side-body");
    // Sentence case in the markup; the caps on screen are text-transform.
    await expect(body).toContainText("Links to3");
    await expect(body).toContainText("Linked from4");
  });

  test("the concept body renders as markdown, not as source", async ({ app }) => {
    await clickNode(app, "services/billing");
    const body = app.locator("#side-body #body");
    await expect(body.locator("a", { hasText: "gateway" }).first()).toBeVisible();
    await expect(body).not.toContainText("](gateway.md)");
  });

  test("a body link navigates to the linked concept in place", async ({ app }) => {
    await clickNode(app, "services/billing");
    await app.locator("#side-body #body a", { hasText: "gateway" }).first().click();
    await expect(app.locator("#side-body")).toContainText("The public edge that terminates TLS");
    // and the graph followed along
    await expect.poll(() => app.evaluate(() => cy.getElementById("services/gateway").hasClass("hl"))).toBe(true);
  });

  test("close hides the panel, the toggle brings it back", async ({ app }) => {
    await clickNode(app, "services/gateway");
    await app.locator("#side-close").click();
    await expect(app.locator(".graph-body")).toHaveAttribute("data-side", "hidden");
    await expect(app.locator("#side")).toHaveCSS("width", "0px");
    await expect(app.locator("#btn-panel")).toHaveAttribute("aria-pressed", "false");

    await app.locator("#btn-panel").click();
    await expect(app.locator(".graph-body")).toHaveAttribute("data-side", "default");
    await expect(app.locator("#side")).toHaveCSS("width", "380px");
  });

  test("widen goes to half the viewport and comes back", async ({ app }) => {
    await clickNode(app, "services/gateway");
    const side = app.locator("#side");

    // The width transitions over .22s, so every read here has to be a
    // retrying one — a bare getComputedStyle lands mid-animation on a number
    // that is neither the old value nor the new.
    await expect(side).toHaveCSS("width", "380px");

    await app.locator("#side-widen").click();
    await expect(app.locator("#side-widen")).toHaveAttribute("aria-pressed", "true");
    await expect(app.locator(".graph-body")).toHaveAttribute("data-side", "wide");
    await expect(side).toHaveCSS("width", "640px"); // 50vw at the 1280px test viewport

    await app.locator("#side-widen").click();
    await expect(app.locator("#side-widen")).toHaveAttribute("aria-pressed", "false");
    await expect(side).toHaveCSS("width", "380px");
  });

  test("the type and tag chips in the panel drive the graph filter", async ({ app }) => {
    await clickNode(app, "services/gateway");
    await app.locator("#side-body [data-focus-type]").first().click();

    // Focusing Service leaves the two services drawn and the rest dimmed.
    await expect.poll(() => visibleNodeIds(app)).toEqual([ "services/billing", "services/gateway" ]);
    await expect(app.locator("#btn-filters .fbadge")).not.toHaveText("0");

    // Clicking the same chip again clears it rather than re-applying.
    await app.locator("#side-body [data-focus-type]").first().click();
    await expect(app.locator("#btn-filters .fbadge")).toHaveText("0");
  });

  test("Escape drops the selection and clears the location hash", async ({ app }) => {
    await clickNode(app, "services/gateway");

    // Wait for the selection to actually land before pressing Escape. `show()`
    // is async, so an immediate Escape clears nothing and the highlight
    // arrives *after* it — the test then fails for a race it created rather
    // than for the behavior it names. This showed up only under a slow,
    // single-worker run, which is what CI looks like.
    await expect.poll(() => app.evaluate(() => cy.elements().filter((e) => e.hasClass("hl")).length)).toBeGreaterThan(0);
    await expect.poll(() => app.evaluate(() => location.hash)).not.toBe("");

    await app.keyboard.press("Escape");

    await expect.poll(() => app.evaluate(() => cy.elements().filter((e) => e.hasClass("hl")).length)).toBe(0);
    await expect.poll(() => app.evaluate(() => location.hash)).toBe("");
  });

  test("selecting a second concept replaces the first", async ({ app }) => {
    await clickNode(app, "services/gateway");
    await expect(app.locator("#side-body")).toContainText("The public edge");
    await clickNode(app, "datasets/orders");
    await expect(app.locator("#side-body")).toContainText("One row per order");
    await expect(app.locator("#side-body")).not.toContainText("The public edge");
  });
});
