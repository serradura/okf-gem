# frozen_string_literal: true

require_relative "lib/okf/mcp/version"

Gem::Specification.new do |spec|
  spec.name = "okf-mcp"
  spec.version = OKF::MCP::VERSION
  spec.authors = [ "Rodrigo Serradura" ]
  spec.email = [ "rodrigo.serradura@gmail.com" ]

  spec.summary = "A Model Context Protocol server for OKF: discover, orient in, search, and read knowledge bundles from any MCP-capable agent."
  spec.description = <<~DESC
    OKF::MCP is a thin Model Context Protocol shell over the okf kernel: it maps
    MCP tool calls onto okf's pure library API so any MCP-capable agent host can
    discover, orient in, search, and read Open Knowledge Format bundles on the
    machine. Bundles are named by the same registry slugs the okf CLI and server
    resolve, search federates across bundles through one shared corpus, and every
    payload is bounded with its truncation visible.
  DESC
  spec.homepage = "https://github.com/serradura/okf-gem"
  spec.license = "Apache-2.0"

  # The floor set by the official `mcp` gem, this shell's core dependency.
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/gems/okf-mcp/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # `git ls-files` with `chdir:` into this gem's directory: paths outside the
  # gem are invisible, so only this gem's own development files need rejecting.
  #
  # `CLAUDE.md` is rejected alongside `AGENTS.md`, and only reads as a stylistic
  # choice: it is one line, `@AGENTS.md`, so shipping it without its target puts
  # a pointer to nothing inside the published gem. The two go together or
  # neither goes. `test/unit/packaging_test.rb` pins that.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile Rakefile test/ .rubocop.yml .gitignore AGENTS.md CLAUDE.md])
    end
  end
  # No executable. This gem's entry point is the `okf mcp` verb it registers
  # through the kernel's plugin seam (lib/okf/plugin.rb) — a second binary that
  # only aliased it was one more name to install, document and keep working.
  spec.require_paths = [ "lib" ]

  # The floor tracks what the suite proves (test/unit/gemspec_test.rb pins
  # it): the listen and modern-path tests exercise the SEP-2575 wire, which
  # 1.0 and 1.1 never served — against them the tests fail, so the floor
  # cannot admit them.
  spec.add_dependency "mcp", "~> 1.2"
  # The kernel version that ships Search.prepare/with/across, registry groups
  # and project-local discovery, `dirs`, `Bundle#directories` (the one source
  # the dir refusal consults), and the slug grammar this shell rides. 1.12
  # lacked #directories, so the old floor admitted a kernel this code raises
  # NoMethodError against.
  # RELEASE OBLIGATION: this floor must move to okf's v0.2 release number in
  # the same PR that bumps okf past 1.13.0 — the shell now reads surfaces
  # published 1.13.0 does not have (Concept.effective_status/fold_tier, the
  # trust catalog column), and against it a status filter raises NameError
  # while a trust filter silently matches nothing. It cannot move earlier:
  # the monorepo resolves this gemspec against the path-sourced okf, whose
  # version is still 1.13.0 until its own release PR. The okf-mcp CHANGELOG's
  # Unreleased section carries the same note where the release notes are cut.
  #
  # A note nothing checks is a note that gets published around, so two guards
  # hold the two halves — and it takes two, because they cover opposite days:
  #   Rakefile#verify_okf_floor  gates `release`, so no release can be cut while
  #     this line still admits okf 1.13.0. That is the window open *today*.
  #   test/unit/gemspec_test.rb  fails the suite if okf bumps and this line
  #     does not follow. That is every day after.
  spec.add_dependency "okf", ">= 2.1", "< 3"
end
