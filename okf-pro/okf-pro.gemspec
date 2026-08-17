# frozen_string_literal: true

require_relative "lib/okf/pro/version"

Gem::Specification.new do |spec|
  spec.name = "okf-pro"
  spec.version = OKF::Pro::VERSION
  spec.authors = [ "Rodrigo Serradura" ]
  spec.email = [ "rodrigo.serradura@gmail.com" ]

  spec.summary = "A profile of OKF: one opinionated shape of knowledge bundle, and the gates that hold it there. Structure for making things happen."
  spec.description = <<~DESC
    OKF Pro is a profile of OKF (Open Knowledge Format) — "pro" as in profile, the
    term of art for a constrained application of a general format, not as in a paid
    tier; this is Apache 2.0 like the rest of the ecosystem. It turns a bundle into
    a working memory an agent is held to. `okf pro setup` writes the bundle and the governance around
    it — the Claude Code hooks, the pre-commit hook, the CI workflow, the skill —
    and `okf pro hook` runs one gate against one hook event: reconcile before you
    add, keep the board and the work in step, attest what you did not verify, close
    the day with a counted snapshot. The same invariants run again as `okf pro
    audit`, the CI door. Every conformance and curation question is the okf gem's
    to answer; what this gem owns is the policy on top and the contract underneath
    it — blocking checks fail closed, feedback checks fail loud, and no check ever
    fails silent.
  DESC
  spec.homepage = "https://github.com/serradura/okf-gem"
  spec.license = "Apache-2.0"

  # The same floor as okf itself, which takes it from rack: the tool should run
  # on whatever Ruby the OS already ships. That matters more here than anywhere
  # else in this repo — this gem's code runs inside a git hook and a CI step on
  # machines nobody chose, and a gate that cannot start is a gate that is off.
  spec.required_ruby_version = ">= 2.4.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/okf-pro/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # `git ls-files` with `chdir:` into this gem's directory: paths outside the
  # gem are invisible, so only this gem's own development files need rejecting.
  # `.okf/` is deliberately *not* rejected — this gem's own knowledge bundle
  # ships inside it, as okf-tui's does, and `rake okf` validates and lints it
  # along with the project's.
  #
  # Neither is `lib/okf/pro/template/`: it is the scaffold `okf pro setup`
  # writes, so a gem that shipped without it would install a verb that cannot do
  # its job. `test/integration/scaffold_test.rb` compares the generated file list
  # against `spec.files` rather than against a glob, because a glob-vs-glob
  # comparison ignores .gitignore on both sides and would pass in a checkout
  # while the installed gem was short files.
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
  # No executable. This gem's entry point is the `okf pro` verb it registers
  # through the kernel's plugin seam (lib/okf/plugin.rb) — the same call okf-mcp
  # and okf-tui made, and for the same reason: a second binary that only aliased
  # the verb would be one more name to install, document and keep working.
  #
  # It matters more here. The scaffold's `.claude/hooks/run` dispatches to an
  # absolute `okf` resolved once from PATH, and refuses if it cannot identify
  # that binary as the enforcer. A second entry point would be a second thing
  # for that wrapper to recognise, on the one code path where being wrong means
  # a gate waves an edit through.
  spec.require_paths = [ "lib" ]

  # The kernel owns the format, the model, and every conformance and curation
  # answer this gem gates on. A question okf can answer is a question this gem
  # has no business answering twice.
  #
  # The floor is 2.0 and it is a real one — the whole v0.2 §5 vocabulary this
  # gem's policy is written in arrived there:
  #
  #   2.0   Concept#trust_tier / #declared_generated? / #verified — the tiers
  #         the attestation gate reads. Before 2.0 there was no tier at all, so
  #         the "awaiting the owner's read" rule had nothing to ask.
  #   2.0   Linter stats[:skipped_checks] — which checks a clockless lint did
  #         not run. The gate surfaces it rather than reporting healthy over a
  #         silent skip, which is the contract's third clause.
  #   2.0   the `broken_source` check (§5.1), renamed from broken_citation, and
  #         `unattributed_claim` — two of the nine warnings the gate blocks on.
  #   2.0   Bundle#okf_version — what the bundle declares itself to be (§12).
  #
  # RELEASE OBLIGATION: the floor tracks the kernel this gem develops against
  # and may never lag it. `test/unit/gemspec_test.rb` fails the suite the moment
  # okf bumps and this line does not follow; the same PR that bumps okf moves it.
  #
  # The `< 3` ceiling is the same earned exception okf-tui's gemspec argues, and
  # the argument is stronger here: this gem pins a frozen snapshot of okf's
  # `Linter::SEVERITIES`, so an okf major that reclassifies a check would change
  # what the gate blocks on. A ceiling turns that into a resolution failure a
  # maintainer sees, instead of a gate that quietly stopped gating.
  spec.add_dependency "okf", ">= 2.0", "< 3"
end
