import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { repoRoot, bundleDir, staticPage, hostileDir, hostilePage, workspaceHome, workspaceDir, treeDir, treePage, manytagsDir, manytagsPage } from "./paths.js";

// Bake the static page the `static` project loads over file://. Rendering it
// here rather than committing it keeps the suite honest: every run tests the
// template as it is on disk right now, not a copy that went stale.
export default function globalSetup() {
  fs.mkdirSync(path.dirname(staticPage), { recursive: true });
  render(bundleDir, staticPage, "Checkout Platform");
  render(hostileDir, hostilePage, "Hostile Bundle");
  render(treeDir, treePage, "Tree Fixture");
  render(manytagsDir, manytagsPage, "Many Tags");
  seedWorkspace();
}

// The registry the workspace server manages: two copies of the bundle fixture,
// registered into a $OKF_HOME of its own. Rebuilt from scratch every run — the
// specs that drive the manager's forms rename and remove entries, and a run
// that inherited the last one's leftovers would pass or fail on history.
function seedWorkspace() {
  fs.rmSync(workspaceHome, { recursive: true, force: true });
  fs.rmSync(workspaceDir, { recursive: true, force: true });
  fs.mkdirSync(workspaceHome, { recursive: true });
  for (const name of [ "alpha", "beta" ]) {
    const dest = path.join(workspaceDir, name);
    fs.cpSync(bundleDir, dest, { recursive: true });
    okf([ "registry", "set", dest, "--as", name ], { OKF_HOME: workspaceHome });
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
