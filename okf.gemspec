# frozen_string_literal: true

require_relative "lib/okf/version"

Gem::Specification.new do |spec|
  spec.name = "okf"
  spec.version = OKF::VERSION
  spec.authors = [ "Rodrigo Serradura" ]
  spec.email = [ "rodrigo.serradura@gmail.com" ]

  spec.summary = "Read, validate, and serve Open Knowledge Format (OKF) v0.1 bundles."
  spec.description = <<~DESC
    OKF is portable knowledge — Markdown files with YAML frontmatter that both
    humans and agents read. This gem reads OKF bundles, checks them for v0.1 (§9)
    conformance, and serves them as an interactive graph (a mountable Rack app).
    It ships a library API (OKF::Bundle and friends) plus an `okf` command-line
    tool (validate / lint / loose / server / graph / skill).
  DESC
  spec.homepage = "https://github.com/serradura/okf-gem"
  spec.license = "Apache-2.0"

  # The same floor as rack, the gem's core dependency: the server mode should run
  # on whatever Ruby the OS already ships.
  spec.required_ruby_version = ">= 2.4.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile Rakefile .gitignore test/ .github/ .rubocop.yml
                          .claude/ AGENTS.md])
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
end
