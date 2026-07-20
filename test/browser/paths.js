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

// The hostile bundle gets its own server and its own static page rather than
// joining the main fixture: every count assertion in boot.spec.js and
// filters.spec.js is written against those 8 concepts, and a bundle carrying
// XSS payloads is a different thing to read anyway.
export const hostileDir = path.join(here, "fixtures", "hostile");
export const hostilePage = path.join(here, ".tmp", "hostile.html");
export const HOSTILE_PORT = PORT + 1;
