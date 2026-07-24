import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// A read-through disk cache for the CDN libraries the graph page loads.
//
// What this is for: the suite stops needing cdn.jsdelivr.net. Once the cache is
// warm every jsdelivr request is answered from `vendor/`, so a run is immune to
// the CDN being slow, rate-limiting, or down — which is the reason the browser
// job is `continue-on-error` in CI today. Proven, not assumed: with the fetch
// path made fatal (`throw` where `route.fetch()` is) a warm run of 64 cases
// still passes, lazy Mermaid and Panzoom included.
//
// What it is NOT for: speed. It was built to cut the suite's wall clock, on the
// reasoning that Playwright gives each test a fresh context with an empty cache
// and so re-pays ~330ms of boot scripts ×400-odd cases. That reasoning is
// wrong, and measuring it says so. The honest measurement is the controlled
// one — a 34-case subset pinned to a single worker, 28.7s without the cache and
// 29.0s with it, which is the same number twice. (Full-suite wall clock is no
// use for this: three runs of the same 412 cases came in at 3.4m, 3.6m and
// 2.8m, a spread far wider than anything being measured.) Chromium reuses these
// subresources across contexts inside a worker's browser process, so the
// per-boot download the arithmetic assumed was only ever paid once per worker.
// The suite is bound by CPU — ~500% of 5 workers, on Chromium rendering and
// Cytoscape layout — and that is where the CDN wait was already hiding. Do not
// re-derive the speedup from the per-request timings; it is not there.
//
// The cache is keyed on the request URL, not on a hand-written manifest of the
// versions the template pins. That is the whole design: a version bump changes
// the URL, which is a miss, which fetches the new bytes. A manifest would be a
// second copy of the pins that could fall out of step with the template's, and
// then the suite would quietly test the old library forever — the exact failure
// a cache is most likely to hide. Here it cannot happen: nothing lists what the
// page ought to load, so nothing can disagree with what it does load.
//
// Set OKF_NO_VENDOR_CACHE=1 to bypass it entirely and go to the network. That
// is how you check the pins still resolve — a warm cache will happily serve a
// library that jsdelivr has since stopped publishing.
const here = path.dirname(fileURLToPath(import.meta.url));
export const vendorDir = path.join(here, "vendor");

const CDN = /^https:\/\/cdn\.jsdelivr\.net\//;

// The URL's own path, flattened into a filename that keeps its extension so
// Playwright can infer the content type from it. Anything outside this
// character set collapses to a dash, which also means no traversal can survive
// the trip: the result has no slashes and no dots-only segments.
const cacheName = (url) =>
  new URL(url).pathname.replace(/^\/+/, "").replace(/[^A-Za-z0-9._@-]+/g, "-");

// Parallel workers are separate processes racing on the same filenames, so a
// hit must never see a half-written file: write beside the target under a
// pid-unique name and rename, which is atomic within a filesystem. Last writer
// wins and they are all writing the same bytes.
let seq = 0;
function writeAtomic(file, body) {
  const tmp = `${file}.${process.pid}-${seq++}.part`;
  fs.writeFileSync(tmp, body);
  fs.renameSync(tmp, file);
}

// Routes every jsdelivr request in the context through the cache. Installed on
// the context rather than the page so it covers every page a spec opens, and
// so a spec's own page-level route still wins — page routes are matched before
// context routes, which is what keeps the specs that abort or count a CDN
// script working unchanged.
export async function installVendorCache(context) {
  if (process.env.OKF_NO_VENDOR_CACHE) return;

  fs.mkdirSync(vendorDir, { recursive: true });

  await context.route(CDN, async (route) => {
    const file = path.join(vendorDir, cacheName(route.request().url()));

    if (fs.existsSync(file)) return route.fulfill({ path: file });

    const response = await route.fetch();
    const body = await response.body();
    // Only a good response is worth keeping. Caching a 404 or a 503 would turn
    // one bad minute at the CDN into a permanently broken checkout.
    if (response.ok()) writeAtomic(file, body);
    return route.fulfill({ response, body });
  });
}
