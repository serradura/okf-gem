import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { repoRoot, bundleDir, staticPage } from "./paths.js";

// Bake the static page the `static` project loads over file://. Rendering it
// here rather than committing it keeps the suite honest: every run tests the
// template as it is on disk right now, not a copy that went stale.
export default function globalSetup() {
  fs.mkdirSync(path.dirname(staticPage), { recursive: true });
  execFileSync(
    "ruby",
    [ "-Ilib", "exe/okf", "render", bundleDir, "-o", staticPage, "-t", "Checkout Platform" ],
    { cwd: repoRoot, stdio: [ "ignore", "ignore", "inherit" ] }
  );
}
