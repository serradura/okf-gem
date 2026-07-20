import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { repoRoot, bundleDir, staticPage, hostileDir, hostilePage } from "./paths.js";

// Bake the static page the `static` project loads over file://. Rendering it
// here rather than committing it keeps the suite honest: every run tests the
// template as it is on disk right now, not a copy that went stale.
export default function globalSetup() {
  fs.mkdirSync(path.dirname(staticPage), { recursive: true });
  render(bundleDir, staticPage, "Checkout Platform");
  render(hostileDir, hostilePage, "Hostile Bundle");
}

// Through bundler for the same reason the webServer command is — see
// playwright.config.js.
function render(dir, out, title) {
  execFileSync(
    "bundle",
    [ "exec", "ruby", "-Ilib", "exe/okf", "render", dir, "-o", out, "-t", title ],
    { cwd: repoRoot, stdio: [ "ignore", "ignore", "inherit" ] }
  );
}
