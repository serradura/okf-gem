# Decisions

The choices that shape okf-tui, each with the tradeoff it accepted.

* [It Invents No Analysis](invents-no-analysis.md) - Every judgement comes from okf; the negative rule this imposes on any feature request, and what it costs.
* [The Search Facade Coupling](search-facade-coupling.md) - Why search rides Bundle::Search.across, and why that needs a check at boot rather than a rescue.
* [Ruby 2.4 Floor, Inherited](ruby-floor.md) - The floor taken from okf, the 2.5 API that slipped past RuboCop, and why the linter loads conditionally.
* [No Version Ceilings on the Markdown Stack](no-version-ceilings.md) - Pinning kramdown and rouge down to protect the floor broke every Ruby above it.
* [One Door — the Plugin Seam Is the Entry Point](one-door-the-plugin-seam.md) - okf-tui ships no executable and registers as an `okf` command; why one front end rather than two, and why registration must not build anything.
* [The Undeclared Width Dependency](undeclared-width-dependency.md) - Column measurement rests on a gem that arrives through tty-box; why that is accepted, and what fails loudly if it stops.
* [okf Moves, and This Breaks Quietly](okf-capability-drift.md) - Inventing no analysis means okf's evolution is this program's; every drift found so far failed silently, and agreement tests are the only defence that works.
* [It Writes the Registry, Never a Bundle](registry-write-boundary.md) - The line under the TUI's side effects is the registry versus the knowledge — what that admits, and why `registry init` falls outside it.
