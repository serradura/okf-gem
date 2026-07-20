import { fileURLToPath } from "node:url";
import path from "node:path";

// Shared by playwright.config.js and global-setup.js, so that neither has to
// import the other: the config names the setup by path, and the setup reads
// its paths from here. A config is a place Playwright calls, not a data module
// for other files to pull from.
//
// (This split was first made while chasing an intermittent "did not expect
// test.describe() to be called here". It was not the cause — the cause was the
// shell's working directory, see README — so treat this as structure, not a
// fix for anything.)
const here = path.dirname(fileURLToPath(import.meta.url));

export const repoRoot = path.resolve(here, "..", "..");
export const bundleDir = path.join(here, "fixtures", "bundle");
export const staticPage = path.join(here, ".tmp", "graph.html");
export const PORT = Number(process.env.OKF_TEST_PORT || 8899);
