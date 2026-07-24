# frozen_string_literal: true

# The monorepo's Rakefile. It owns no code — it delegates into each gem's own
# bundle, so that a gem stays runnable on its own (`cd okf && bundle exec rake`
# is what CI runs, and what the Ruby 2.4 floor is proven against).
#
# Run it as plain `rake`, not `bundle exec rake`: there is deliberately no root
# Gemfile. The gems here do not share a Ruby floor — okf runs from 2.4, an MCP
# shell would start at 2.7, an FTS5 engine at 3.2 — so a single lockfile could
# never resolve for all of them, and a root bundle would only be a second
# context to keep in sync for no gain.

# Adding a gem to the repo is adding it here.
GEMS = %w[okf].freeze

ROOT = __dir__

# Every delegated command names the bundle it wants outright. Bundler exports
# BUNDLE_GEMFILE into the environment of everything it runs, so a nested
# `bundle exec` inherits the *parent's* Gemfile — which means running this file
# under bundler (or from a shell that wraps `rake` in one) would silently
# resolve every gem's tasks against the wrong bundle. Naming it is what makes
# the delegation correct either way.
def gemfile_env(gem_dir)
  { "BUNDLE_GEMFILE" => File.join(ROOT, gem_dir, "Gemfile") }
end

# Every gem's own bundle, from its own directory.
def each_gem(task)
  GEMS.each do |gem_dir|
    puts "\n== #{gem_dir}: rake #{task} =="
    Dir.chdir(File.join(ROOT, gem_dir)) { sh gemfile_env(gem_dir), "bundle exec rake #{task}" }
  end
end

# The okf CLI straight out of the checkout. `ruby -Ilib exe/okf` stopped being
# expressible from the repo root when the gem moved down a level, and this is
# the spelling that replaces it.
def okf(*argv)
  sh RbConfig.ruby, "-I#{ROOT}/okf/lib", "#{ROOT}/okf/exe/okf", *argv
end

desc "Run every gem's default task (test + rubocop), then lint the repo-level Ruby"
task default: %i[gems rubocop]

desc "Run every gem's default task"
task(:gems) { each_gem("default") }

desc "Run every gem's test suite"
task(:test) { each_gem("test") }

# The repo-level Ruby — this file and the plugin's curation hook — sits outside
# every gem, so no gem's `rake rubocop` reaches it. Run from the root against
# the root config, borrowing okf's bundle for the rubocop binary itself.
# CI runs this as its own job (see .github/workflows/main.yml) because no gem's
# own `rake rubocop` reaches these two files.
#
# It degrades where RuboCop is absent, exactly as the gem's default task does:
# okf/Gemfile only installs it from 2.7 up, so on the old Rubies this would
# otherwise take the root `rake` down with it.
desc "RuboCop the repo-level Ruby (this Rakefile and the plugin hook)"
task :rubocop do
  env = gemfile_env("okf")
  if system(env, "bundle exec rubocop --version", out: File::NULL, err: File::NULL)
    sh env, "bundle exec rubocop"
  else
    puts "rubocop is not installed on this Ruby (okf/Gemfile installs it from 2.7) — skipping the repo-level lint"
  end
end

desc "Validate and lint this repo's own .okf bundle with the checkout's CLI"
task :okf do
  okf "validate", "#{ROOT}/.okf"
  okf "lint", "#{ROOT}/.okf"
end

desc "Serve this repo's own .okf bundle as a graph"
task(:serve) { okf "server", "#{ROOT}/.okf", "--title", "okf-gem" }

# A release is cut from the gem it releases, never from here: `rake release` is
# Bundler's, it reads the gemspec in its working directory, and the version tag
# it pushes is derived from that. Running it at the root would be a mistake with
# a public consequence, so it fails loudly instead of doing nothing.
task :release do
  abort "releases are cut per gem: cd into the gem's directory (e.g. `cd okf`) and run `rake release` there"
end
