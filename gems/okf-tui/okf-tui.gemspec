# frozen_string_literal: true

require_relative "lib/okf/tui/version"

Gem::Specification.new do |spec|
  spec.name = "okf-tui"
  spec.version = OKF::TUI::VERSION
  spec.authors = [ "Rodrigo Serradura" ]
  spec.email = [ "rodrigo.serradura@gmail.com" ]

  spec.summary = "A terminal UI for Open Knowledge Format bundles: read one, switch between many, search across all of them."
  spec.description = <<~DESC
    okf-tui is a full-screen terminal UI over OKF (Open Knowledge Format) bundles.
    It reads a bundle in the order the spec intends — index.md, log.md, then each
    directory — renders concept bodies as markdown, and finds within them. It
    browses and configures the per-user bundle registry, switches the active
    bundle, and searches every bundle in scope through one shared index, so the
    scores compare between them. It shows each bundle's standing (conformance and
    curation) wherever the bundle is named, and its knowledge graph as a set of
    facets to narrow by or follow into the file. It invents no analysis: the okf
    gem's pure core answers every question on screen.
  DESC
  spec.homepage = "https://github.com/serradura/okf"
  spec.license = "Apache-2.0"

  # The same floor as okf itself, which takes it from rack: the tool should run
  # on whatever Ruby the OS already ships. Every dependency below is pinned to a
  # line that still accepts it — see AGENTS.md for which pins exist only for this.
  spec.required_ruby_version = ">= 2.4.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/gems/okf-tui/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # `git ls-files` with `chdir:` into this gem's directory: paths outside the
  # gem are invisible, so only this gem's own development files need rejecting.
  # `.okf/` is deliberately *not* rejected: this gem's own knowledge bundle ships
  # inside it, so an installed okf-tui carries a real bundle to open — its own —
  # without a checkout. It is validated and lint-clean, which the repo's
  # `rake okf` covers along with the project's.
  #
  # `CLAUDE.md` is rejected alongside `AGENTS.md`, and only reads as a stylistic
  # choice: it is one line, `@AGENTS.md`, so shipping it without its target puts
  # a pointer to nothing inside the published gem. The two go together or
  # neither goes. `test/unit/packaging_test.rb` pins that.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile Rakefile .gitignore test/ .rubocop.yml AGENTS.md CLAUDE.md])
    end
  end
  # No executable. This gem's entry point is the `okf tui` verb it registers
  # through the kernel's plugin seam (lib/okf/plugin.rb) — a second binary that
  # only aliased it was one more name to install, document and keep working,
  # and a second door is a second argument grammar waiting to drift. There was
  # an `exe/okf-tui` that did nothing but call the same `CLI.run`, and it went
  # before the first release, while removing a name still cost nobody anything.
  # okf-mcp made the same call for the same reason.
  spec.require_paths = [ "lib" ]

  # The whole point: okf owns the format, the model, and every analysis this
  # renders. A question the TUI cannot answer by asking okf is a question it has
  # no business answering.
  #
  # The floor is a real one, not a formality. Every screen here answers with
  # something okf added after 1.9, and against an older one each fails *silently*
  # rather than loudly — which is the whole reason the floor is stated rather than
  # left to chance:
  #
  #   1.10  OKF::CLI.register and CLI::Command — the seam `okf tui` is registered
  #         through, and the ref grammar OKF::TUI::Refs inherits.
  #   1.10  Bundle#hubs — the inbound ranking, with the dirs each hub's links come
  #         from, on the health view.
  #   1.11  Bundle::Search.prepare/.with — the held corpus. Without it every query
  #         rebuilt the whole cross-bundle index: 392 ms per search against 12 ms.
  #   1.12  Registry groups (#groups_listing, #expand, #group?) and Registry#reopen;
  #         project-local registry discovery via Registry.load(cwd:).
  #   1.12  Bundle#skeleton — the directory traffic and cohesion figures.
  #   1.12  the catalog's `area` key became `top_dir`. Reading the old name returned
  #         nil for every row, so a bundle of six directories reported one.
  #   1.13  Bundle#directories — "which directories does this bundle have?", asked
  #         of the bundle rather than re-derived from a catalog that cannot see an
  #         intermediate or a log-only directory.
  #   2.0   the catalog's §5 columns — generated_at / generated_by / generated,
  #         trust, status, stale_after, sources — which browse renders, the graph
  #         facets on, and health counts. The `timestamp` column they replace was
  #         removed, so reading the old name is not a fallback, it is nothing.
  #   2.0   Bundle#okf_version — what the bundle declares itself to be (§12).
  #         Without it the health view states a version from a literal, which is
  #         how it told every reader "v0.1" for a release.
  #   2.0   Bundle::RowFilter — .matches? for the status and trust facets (so the
  #         two folds that make them non-trivial are okf's), .under_dir? for the
  #         dir rule this used to keep a byte-identical copy of, and .shows_trust?
  #         for whether a derived tier is one to claim at all.
  #   2.0   Linter stats[:skipped_checks], [:trust] and [:status] — the checks a
  #         clockless lint did not run, and the two distributions okf's own lint
  #         headlines. Health reports the first rather than giving a verdict over
  #         it, and shows the second.
  #
  # RELEASE OBLIGATION: the floor tracks the kernel this gem develops against and
  # may never lag it — a lagging floor admits an okf whose renamed surfaces this
  # code reads as nil rather than raising. `test/unit/gemspec_test.rb` fails the
  # suite the moment okf bumps and this line does not follow; the same PR that
  # bumps okf moves it.
  #
  # It is lagging *now*, and knowingly. The bundles view reads `Registry#links_listing`
  # and the `link` key on listing and group rows, which published okf 2.1.1 does
  # not have: against it a linked bundle is simply never marked read-only and the
  # four config keys stop refusing — nil, not a raise, which is the exact failure
  # the paragraph above describes. It cannot move earlier, because the monorepo
  # resolves the path-sourced okf whose version.rb still says 2.1.1 and a leading
  # floor fails resolution outright. The CHANGELOG's Unreleased section carries
  # the same note where the release notes are cut.
  #
  # The `< 3` ceiling is the one exception to "no ceilings for the floor's sake"
  # (AGENTS.md constraint 3), and it is earned rather than borrowed from the
  # sibling: an okf major is precisely where the silent drift this gem keeps
  # hitting comes from — `area` → `top_dir` in 1.12 and `timestamp` →
  # `generated_at` in 2.0 each broke a screen with a green suite either side of
  # it. Neither raised. A ceiling is what turns the next one into a resolution
  # failure a maintainer sees instead of a wrong number a reader believes.
  #
  # OKF::TUI.search_capable? and .spec_capable? still check at boot, because a
  # requirement binds resolution and cannot stop a second okf sitting ahead of
  # the intended one on the load path.
  spec.add_dependency "okf", ">= 2.1.1", "< 3"

  # The TTY toolkit, one gem per job and no more. All of these declare >= 2.0,
  # so none of them is what would raise the floor.
  spec.add_dependency "pastel", "~> 0.8"       # colour, and the enabled? flag the layout reads
  spec.add_dependency "tty-box", "~> 0.7"      # the framed panes
  spec.add_dependency "tty-cursor", "~> 0.7"   # positioning for the full-screen repaint
  spec.add_dependency "tty-markdown", "~> 0.7" # concept bodies, rendered
  spec.add_dependency "tty-reader", "~> 0.9"   # the raw keypress loop
  spec.add_dependency "tty-screen", "~> 0.8"   # terminal size

  # No ceilings on kramdown and rouge, deliberately. Their newest lines need a
  # Ruby newer than this gem's floor (kramdown 2.5 wants 2.5, rouge 4 wants 2.7),
  # but they declare that themselves — so resolution already picks the newest
  # line each Ruby accepts: kramdown 2.4 and rouge 3 on the floor, the current
  # ones everywhere else. Pinning the old lines for everyone was the first
  # attempt, and it broke on modern Ruby, where kramdown 2.4 calls a CGI method
  # that no longer exists.
  spec.add_dependency "kramdown", ">= 2.3"
  spec.add_dependency "rouge", ">= 3.14"
end
