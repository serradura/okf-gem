import { defineConfig, devices } from "@playwright/test";
import { repoRoot, bundleDir, staticPage, PORT, hostileDir, HOSTILE_PORT } from "./paths.js";

const serve = (dir, port) => ({
  command: `bundle exec ruby -Ilib exe/okf server ${JSON.stringify(dir)} -p ${port}`,
  cwd: repoRoot,
  url: `http://127.0.0.1:${port}/`,
  reuseExistingServer: !process.env.CI,
  stdout: "pipe",
  stderr: "pipe",
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
  webServer: [ serve(bundleDir, PORT), serve(hostileDir, HOSTILE_PORT) ],
});
