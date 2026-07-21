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

// The hub serves the bundle and hostile fixtures together (two dirs → hub mode),
// so /b/bundle/ carries a sibling and the palette's bundle switcher exists.
// Reached by URL directly, so it needs no Playwright project of its own.
export const HUB_PORT = PORT + 2;

// A deliberately nested bundle — charter at the root, then platform/services/*
// and data/warehouse/*, each intermediate dir holding only a subdirectory. It
// gets its own server and static page like the hostile one, for the same
// reason: the file-tree structure branches (a dir with only sub-dirs, folder
// headers showing the last path segment, indentation by depth) have no way in
// through the flat 8-concept fixture, whose count assertions must stay put.
export const treeDir = path.join(here, "fixtures", "tree");
export const treePage = path.join(here, ".tmp", "tree.html");
export const TREE_PORT = PORT + 4;

// A bundle carrying more than forty distinct tags (tag01…tag45), so the filter
// finder's top-40 chip cap has something to hide — unreachable from the main
// fixture's five tags. Own server + static page, same as the others.
export const manytagsDir = path.join(here, "fixtures", "manytags");
export const manytagsPage = path.join(here, ".tmp", "manytags.html");
export const MANYTAGS_PORT = PORT + 5;

// A concept buried five directories deep, so its folder's authored index.md
// carries a path long enough to overflow a tree row — the one arrangement the
// flat and shallow fixtures cannot make, and the tree fixture (which asserts no
// reserved files) must not. Own server + static page, as the rest.
export const deeppathDir = path.join(here, "fixtures", "deeppath");
export const deeppathPage = path.join(here, ".tmp", "deeppath.html");
export const DEEPPATH_PORT = PORT + 6;

// A 100-node ring: cose lays it out as a large circle whose extent runs several
// times the viewport, the one shape that drives the fit-zoom below MIN_ZOOM and
// makes relaxZoom lower the floor. No small fixture can reach that branch. Own
// server + static page, as the rest.
export const biggraphDir = path.join(here, "fixtures", "biggraph");
export const biggraphPage = path.join(here, ".tmp", "biggraph.html");
export const BIGGRAPH_PORT = PORT + 7;

// The Bundles panel's own registry hub. It gets a world of its own for the
// reason every other special fixture here does: its specs *write* — rename,
// re-default, remove — and pointing them at the developer's registry, or at the
// committed fixtures, would leave those writes behind. One registry read-
// modify-written from two workers is a lost entry waiting for a slow afternoon.
export const panelHome = path.join(here, ".tmp", "panelhome");
export const panelDir = path.join(here, ".tmp", "panel");
export const PANEL_PORT = PORT + 8;


// The same registry, served read-only — bound to 0.0.0.0, which is refused
// outright and has no flag that opens it. It shares panelHome deliberately: a
// read-only server cannot write to it, so nothing here can race the panel's
// own specs.
export const RO_PORT = PORT + 9;
