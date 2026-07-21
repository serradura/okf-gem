import { hostilePage, HOSTILE_PORT } from "../paths.js";
import { test as base, expect, bootGraph } from "../helpers.js";

// The two XSS defenses AGENTS.md calls load-bearing, asserted for the first
// time. Until this file existed, the only checks were that the string
// `DOMPurify` appears in the emitted page and that it is a function at boot —
// both of which a render path that skipped the sanitizer passes cleanly.
//
// This runs against fixtures/hostile: a bundle that is perfectly conformant
// OKF and is trying to execute script in the page rendering it. It gets its
// own page and its own server because every count assertion in the other
// specs is written against the 8-concept fixture.
//
// The flags are set on `window` by the payloads themselves, so an assertion
// here is not "the markup looks clean" — it is "the script did not run".
const FLAGS = [
  "__xssInline", "__xssImg", "__xssSvg", "__xssFrame",
  "__xssClick", "__xssHover", "__xssHref", "__xssForm", "__xssTitle", "__xssTag",
];

const test = base.extend({
  hostile: async ({ page }, use, testInfo) => {
    const url = testInfo.project.name === "static"
      ? `file://${hostilePage}`
      : `http://127.0.0.1:${HOSTILE_PORT}/`;

    await page.addInitScript(() => {
      try { localStorage.setItem("okf-hello", "1"); } catch (e) {}
    });
    await page.goto(url);
    await bootGraph(page);
    await use(page);
  },
});

const firedFlags = (page, flags) =>
  page.evaluate((names) => names.filter((n) => window[n] !== undefined), flags);

test.describe("body sanitization", () => {
  test("a concept body's scripts are stripped and the prose survives", async ({ hostile }) => {
    await hostile.evaluate(() => cy.getElementById("payload").emit("tap"));

    // The prose assertion is load-bearing: without it, a body that failed to
    // render at all would pass every "no script ran" check below and look
    // like a working sanitizer.
    await expect(hostile.locator("#side-body #body")).toContainText("SAFE-MARKER-9F3A");

    expect(await firedFlags(hostile, FLAGS)).toEqual([]);
    await expect(hostile.locator("#side-body #body script")).toHaveCount(0);
    await expect(hostile.locator("#side-body #body iframe")).toHaveCount(0);
  });

  test("event-handler attributes do not survive into the DOM", async ({ hostile }) => {
    await hostile.evaluate(() => cy.getElementById("payload").emit("tap"));
    await expect(hostile.locator("#side-body #body")).toContainText("SAFE-MARKER-9F3A");

    // Present-but-inert is not good enough: an onerror that DOMPurify left on
    // the element fires the moment anything re-parents or re-renders it.
    expect(await hostile.evaluate(() => {
      const el = document.querySelector("#side-body #body");
      return [ ...el.querySelectorAll("*") ]
        .flatMap((n) => [ ...n.attributes ].map((a) => a.name))
        .filter((name) => name.startsWith("on"));
    })).toEqual([]);
  });

  test("javascript: URLs are stripped from links", async ({ hostile }) => {
    await hostile.evaluate(() => cy.getElementById("payload").emit("tap"));
    await expect(hostile.locator("#side-body #body")).toContainText("SAFE-MARKER-9F3A");

    expect(await hostile.evaluate(() =>
      [ ...document.querySelectorAll("#side-body #body [href],#side-body #body [src],#side-body #body [action]") ]
        .flatMap((n) => [ n.getAttribute("href"), n.getAttribute("src"), n.getAttribute("action") ])
        .filter((v) => v && v.toLowerCase().replace(/\s/g, "").startsWith("javascript:"))
    )).toEqual([]);
  });

  test("the same body is sanitized in the files reader, not only the inspector", async ({ hostile }) => {
    // A second render path reaches #fp-body. A sanitizer wired into one and
    // not the other is exactly the regression this pair exists to catch.
    await hostile.locator('.rail-item[data-view="files"]').click();
    await hostile.locator(".file", { hasText: "payload.md" }).first().click();
    await expect(hostile.locator("#fp-body")).toContainText("SAFE-MARKER-9F3A");

    expect(await firedFlags(hostile, FLAGS)).toEqual([]);
    await expect(hostile.locator("#fp-body script")).toHaveCount(0);
  });
});

test.describe("inlined data escaping", () => {
  test("a </script> in a concept title cannot close the payload script", async ({ hostile }) => {
    // json_for_script escapes `<`, so the title below stays inside its own
    // <script> block. If it did not, the page would not have booted at all —
    // which bootGraph already proved — but the flag is the direct assertion.
    expect(await firedFlags(hostile, [ "__xssTitle" ])).toEqual([]);
    expect(await hostile.evaluate(() => Object.keys(byId).length)).toBe(2);
  });

  test("a quote in a tag cannot break out of the attribute it is written into", async ({ hostile }) => {
    // esc() escapes quotes as well as angle brackets because it feeds
    // attributes: `data-focus-tag="${esc(t)}"`. The fixture's tag is the
    // classic breakout, `evil"onmouseover="…`.
    await hostile.evaluate(() => cy.getElementById("attributes").emit("tap"));
    await expect(hostile.locator("#side-body")).toContainText("apostrophes");

    const handlers = await hostile.evaluate(() =>
      [ ...document.querySelectorAll("#side-body *") ]
        .flatMap((n) => [ ...n.attributes ].map((a) => a.name))
        .filter((name) => name.startsWith("on"))
    );
    expect(handlers).toEqual([]);

    await hostile.locator("#side-body [data-focus-tag]").first().hover();
    expect(await firedFlags(hostile, [ "__xssTag" ])).toEqual([]);
  });

  test("the title renders as text, with its markup visible rather than parsed", async ({ hostile }) => {
    await hostile.evaluate(() => cy.getElementById("attributes").emit("tap"));
    // The literal characters are what a reader should see — proof it went
    // through a text path and not an HTML one.
    await expect(hostile.locator("#side-body .title")).toContainText("</script>");
    expect(await firedFlags(hostile, FLAGS)).toEqual([]);
  });
});
