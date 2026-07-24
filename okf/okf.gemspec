# frozen_string_literal: true

require_relative "lib/okf/version"

Gem::Specification.new do |spec|
  spec.name = "okf"
  spec.version = OKF::VERSION
  spec.authors = [ "Rodrigo Serradura" ]
  spec.email = [ "rodrigo.serradura@gmail.com" ]

  spec.summary = "The complete Open Knowledge Format toolkit: an agent skill, a CLI and library, ranked search, and a live knowledge graph. 100% local."
  spec.description = <<~DESC
    OKF (Open Knowledge Format) is portable knowledge: Markdown files with YAML
    frontmatter that both humans and agents read from one source. This gem is the
    Ruby-native way to work with it.

    Its companion agent skill authors and curates a bundle. The `okf` command-line
    tool validates the result for v0.1 (§9) conformance, lints its curation
    quality, and answers questions about it: ranked full-text search, and a
    progressive-disclosure map that reads a large bundle a directory at a time
    rather than loading it whole. `okf server` opens it as an interactive
    knowledge graph and `okf render` bakes that same page into one self-contained
    HTML file you can host anywhere. A per-user registry names your bundles, so
    every verb reaches them by @slug from any directory and one search can span
    them all.

    Everything the CLI does also runs in-process through a library API
    (OKF::Bundle and friends), and the graph server is a mountable Rack app. It
    adds no service to your stack: rack, webrick and minifts are the only runtime
    dependencies, and it runs on every Ruby since 2.4.
  DESC
  spec.homepage = "https://github.com/serradura/okf-gem"
  spec.license = "Apache-2.0"

  # The same floor as rack, the gem's core dependency: the server mode should run
  # on whatever Ruby the OS already ships.
  spec.required_ruby_version = ">= 2.4.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/okf/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  #
  # `chdir: __dir__` is what makes this work from a subdirectory of the repo:
  # git lists paths relative to the directory it runs in, so this sees the gem's
  # own tree and nothing above it. Everything at the repo root — .okf/, plugin/,
  # .github/, AGENTS.md, the Dockerfile — is invisible here by construction and
  # needs no reject entry.
  #
  # The rule runs one way only: anything .dockerignore drops from under okf/ has
  # to be rejected here (or gitignored). `git ls-files` reads the *index*, so a
  # file missing from the build context is still listed in spec.files and
  # `gem build` fails on it. The converse does not hold and must not be
  # "restored" — bin/, Gemfile and Rakefile are rejected here and deliberately
  # left in the context, because nothing breaks by shipping them to the builder.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile Rakefile .gitignore test/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = [ "lib" ]

  # The graph server (OKF::Server::App) is a Rack app; `okf server` runs it under
  # WEBrick through the built-in OKF::Server::Runner. WEBrick was unbundled from
  # Ruby in 3.0, so it is explicit; on older Rubies the dependency resolves to a
  # version those Rubies accept.
  spec.add_dependency "rack", ">= 2.2"
  spec.add_dependency "webrick", ">= 1.4"

  # The search engine (OKF::Bundle::Search). minifts is a pure-Ruby port of the
  # JavaScript MiniSearch the browser page already loads, pinned to the same
  # major so a Ruby-built index and the browser's rank identically. Zero runtime
  # dependencies of its own and the same 2.4 floor, so it costs the gem nothing
  # but the code that does the work.
  spec.add_dependency "minifts", "~> 1.0"
end
