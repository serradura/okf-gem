import { defineConfig, devices } from "@playwright/test";
import { gemRoot, bundleDir, staticPage, PORT, hostileDir, HOSTILE_PORT, HUB_PORT,
  panelHome, PANEL_PORT, RO_PORT, treeDir, TREE_PORT, manytagsDir, MANYTAGS_PORT,
  deeppathDir, DEEPPATH_PORT, biggraphDir, BIGGRAPH_PORT, densegraphDir, DENSEGRAPH_PORT } from "./paths.js";

const serve = (dir, port, layout) => ({
  command: `bundle exec ruby -Ilib exe/okf server ${JSON.stringify(dir)} -p ${port}${layout ? ` --layout ${layout}` : ""}`,
  cwd: gemRoot,
  url: `http://127.0.0.1:${port}/`,
  reuseExistingServer: !process.env.CI,
  stdout: "pipe",
  stderr: "pipe",
});

// Two dirs behind one server is hub mode: each bundle mounts at /b/<slug>/ and
// carries the other as a sibling, which is the only way SIBLINGS is populated —
// so the command palette's bundle-switch half only exists here. Ready when the
// mounted bundle answers.
const serveHub = (dirs, port) => ({
  command: `bundle exec ruby -Ilib exe/okf server ${dirs.map((d) => JSON.stringify(d)).join(" ")} -p ${port}`,
  cwd: gemRoot,
  url: `http://127.0.0.1:${port}/b/bundle/`,
  reuseExistingServer: !process.env.CI,
  stdout: "pipe",
  stderr: "pipe",
});

// Zero dirs is the *registry* hub — the only mode whose Bundles panel can change
// anything, because it is the only one with a registry behind it. It gets its
// own $OKF_HOME (seeded in global-setup.js) so a spec that renames an entry
// cannot reach the developer's real one. reuseExistingServer stays off here:
// this server holds registry state in memory and rebuilds it on every write, so
// a leftover process from the last run would answer with the last run's world.
const serveRegistry = (port, home) => ({
  command: `bundle exec ruby -Ilib exe/okf server -p ${port}`,
  cwd: gemRoot,
  env: { ...process.env, OKF_HOME: home },
  url: `http://127.0.0.1:${port}/b/`,
  reuseExistingServer: false,
  stdout: "pipe",
  stderr: "pipe",
});

// `--bind 0.0.0.0` is what makes a hub read-only, and it is still reachable at
// 127.0.0.1 — so this proves the flag's real effect rather than a simulation of
// it. It shares panelHome because it cannot write to it.
const serveReadOnly = (port, home) => ({
  ...serveRegistry(port, home),
  command: `bundle exec ruby -Ilib exe/okf server -p ${port} --bind 0.0.0.0`,
});

// The template renders in two modes and they diverge in one load-bearing way:
// served live it fetches /node, /catalog, /index, /log on demand, while a
// static render bakes the same payloads into EMBED. A spec that passes in one
// proves nothing about the other, so every spec runs in both — that is what
// the two projects are for. `okf render` writes the static page in
// global-setup.js; `webServer` below boots the live one.
export default defineConfig({
  testDir: "./specs",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: 0,
  reporter: process.env.CI ? "line" : [ [ "list" ], [ "html", { open: "never", outputFolder: ".tmp/report" } ] ],
  globalSetup: "./global-setup.js",
  outputDir: "./.tmp/results",

  use: {
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    // OKF_SLOWMO=400 puts a pause between every action so a headed run is
    // watchable — at full speed the browser blurs through a spec too fast to
    // read. Off by default; `rake browser:watch` sets it.
    launchOptions: { slowMo: Number(process.env.OKF_SLOWMO || 0) },
    // OKF_VIDEO=1 records each spec to .tmp/results/. Useful when you want to
    // see a run you were not watching — a CI failure, or the whole suite
    // without sitting through it live.
    video: process.env.OKF_VIDEO ? "on" : "off",
  },

  projects: [
    {
      name: "server",
      use: { ...devices["Desktop Chrome"], baseURL: `http://127.0.0.1:${PORT}/` },
    },
    {
      name: "static",
      use: { ...devices["Desktop Chrome"], baseURL: `file://${staticPage}` },
    },
  ],

  // Two servers: the ordinary fixture every spec runs against, and the hostile
  // bundle sanitization.spec.js points at. `serve()` above goes through
  // bundler rather than a bare `ruby` — `okf server` needs rack and webrick,
  // and a CI setup-ruby with bundler-cache puts them under a BUNDLE_PATH that
  // `ruby -Ilib` would not search.
  webServer: [
    serve(bundleDir, PORT),
    serve(hostileDir, HOSTILE_PORT),
    serve(treeDir, TREE_PORT),
    serve(manytagsDir, MANYTAGS_PORT),
    serve(deeppathDir, DEEPPATH_PORT),
    serve(biggraphDir, BIGGRAPH_PORT),
    // circle, not the default cose: the boot split is layout-independent and a
    // fast deterministic layout keeps 880 edges from dominating the run twice.
    serve(densegraphDir, DENSEGRAPH_PORT, "circle"),
    serveHub([ bundleDir, hostileDir ], HUB_PORT),
    serveRegistry(PANEL_PORT, panelHome),
    serveReadOnly(RO_PORT, panelHome),
  ],
});
