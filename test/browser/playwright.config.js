import { defineConfig, devices } from "@playwright/test";
import { repoRoot, bundleDir, staticPage, PORT } from "./paths.js";

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

  webServer: {
    // Through bundler, not a bare `ruby`. `okf server` needs rack and webrick,
    // and a CI setup-ruby with bundler-cache installs them under a BUNDLE_PATH
    // that a bare `ruby -Ilib` would not search. Locally it resolves the same
    // gems either way, so this costs nothing and removes an environment
    // assumption.
    command: `bundle exec ruby -Ilib exe/okf server ${JSON.stringify(bundleDir)} -p ${PORT}`,
    cwd: repoRoot,
    url: `http://127.0.0.1:${PORT}/`,
    reuseExistingServer: !process.env.CI,
    stdout: "pipe",
    stderr: "pipe",
  },
});
