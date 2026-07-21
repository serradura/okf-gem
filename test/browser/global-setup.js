import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { repoRoot, bundleDir, staticPage, hostileDir, hostilePage, panelHome, panelDir, treeDir, treePage, manytagsDir, manytagsPage, deeppathDir, deeppathPage, biggraphDir, biggraphPage } from "./paths.js";

// Bake the static page the `static` project loads over file://. Rendering it
// here rather than committing it keeps the suite honest: every run tests the
// template as it is on disk right now, not a copy that went stale.
export default function globalSetup() {
  fs.mkdirSync(path.dirname(staticPage), { recursive: true });
  render(bundleDir, staticPage, "Checkout Platform");
  render(hostileDir, hostilePage, "Hostile Bundle");
  render(treeDir, treePage, "Tree Fixture");
  render(manytagsDir, manytagsPage, "Many Tags");
  render(deeppathDir, deeppathPage, "Deep Path");
  render(biggraphDir, biggraphPage, "Big Graph");
  seedPanel();
}

// The Bundles panel's registry: three bundles, so a remove still leaves a list
// and a re-default has somewhere to move to. It gets its own $OKF_HOME and its
// own throwaway copies of a bundle, because these specs *write* — pointing them
// at the committed fixtures would leave a rename behind in the working tree,
// and two files writing one registry from two workers is how an entry goes
// missing. Rebuilt from scratch every run, so nothing passes or fails on
// history.
function seedPanel() {
  fs.rmSync(panelHome, { recursive: true, force: true });
  fs.rmSync(panelDir, { recursive: true, force: true });
  fs.mkdirSync(panelHome, { recursive: true });
  for (const name of [ "one", "two", "three" ]) {
    const dest = path.join(panelDir, name);
    fs.cpSync(bundleDir, dest, { recursive: true });
    okf([ "registry", "set", dest, "--as", name ], { OKF_HOME: panelHome });
  }
}

// Through bundler for the same reason the webServer command is — see
// playwright.config.js.
function render(dir, out, title) {
  okf([ "render", dir, "-o", out, "-t", title ]);
}

function okf(argv, env = {}) {
  execFileSync(
    "bundle",
    [ "exec", "ruby", "-Ilib", "exe/okf", ...argv ],
    { cwd: repoRoot, env: { ...process.env, ...env }, stdio: [ "ignore", "ignore", "inherit" ] }
  );
}
