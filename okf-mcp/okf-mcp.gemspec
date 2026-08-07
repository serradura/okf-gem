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
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/okf-mcp/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # `git ls-files` with `chdir:` into this gem's directory: paths outside the
  # gem are invisible, so only this gem's own development files need rejecting.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile Rakefile test/ .rubocop.yml .gitignore])
    end
  end
  # No executable. This gem's entry point is the `okf mcp` verb it registers
  # through the kernel's plugin seam (lib/okf/plugin.rb) — a second binary that
  # only aliased it was one more name to install, document and keep working.
  spec.require_paths = [ "lib" ]

  spec.add_dependency "mcp", "~> 1.0"
  # The kernel version that ships Search.prepare/with/across, registry groups
  # and project-local discovery, `dirs`, and the slug grammar this shell rides.
  spec.add_dependency "okf", ">= 1.12"
end
