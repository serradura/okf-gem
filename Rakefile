# frozen_string_literal: true

require "bundler/gem_tasks"

# rake/testtask (not minitest/test_task) so `rake test` runs on every supported
# Ruby — minitest's own task class needs minitest 5.16+, which needs Ruby 2.6.
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

namespace :test do
  # Integration alone, with its own coverage report. Run this to ask the question
  # the full suite cannot answer: how much of the gem is reachable the way a user
  # reaches it? Unit tests inflate the number by calling classes directly, so the
  # honest figure comes from running this task on its own (OKF_COVERAGE_DIR keeps
  # its report from overwriting the full suite's).
  desc "Run only the integration suite, with an integration-only coverage report"
  Rake::TestTask.new(:integration) do |t|
    t.libs << "test" << "lib"
    t.test_files = FileList["test/integration/**/*_test.rb"]
    t.warning = false
  end

  # The graph page is ~1,300 lines of inline JS and CSS in one ERB template,
  # and the things that break there — a view that returns with a collapsed
  # canvas, a filter that stops composing, the ≤768px block folding the wrong
  # element — are invisible to a string assertion over the rendered HTML. This
  # task drives the real page in a real Chromium: DOM, computed CSS, media
  # queries, and any error the page throws while a spec is running.
  #
  # Deliberately outside the default task. It needs node and a ~120MB Chromium,
  # neither of which belongs on the Ruby 2.4 CI matrix, and the gem itself
  # gains no dependency from it.
  desc "Run the browser suite against the graph page (needs node; `rake browser:setup` first)"
  task :browser do
    dir = File.expand_path("test/browser", __dir__)
    unless File.directory?(File.join(dir, "node_modules"))
      abort "browser suite not installed: run `bundle exec rake browser:setup`"
    end
    Dir.chdir(dir) { sh "npx playwright test" }
  end
end

namespace :browser do
  desc "Install the browser suite's node dependencies and Chromium"
  task :setup do
    Dir.chdir(File.expand_path("test/browser", __dir__)) do
      sh "npm install"
      sh "npx playwright install chromium"
    end
  end

  desc "Open the browser suite's interactive runner (pick specs, watch them drive a real page)"
  task :ui do
    Dir.chdir(File.expand_path("test/browser", __dir__)) { sh "npx playwright test --ui" }
  end

  desc "Show the last browser run's HTML report (traces, screenshots, timings)"
  task :report do
    Dir.chdir(File.expand_path("test/browser", __dir__)) { sh "npx playwright show-report .tmp/report" }
  end
end

# Boot the graph page on the same fixture the browser suite drives, for poking
# at by hand. `rake test:browser` boots its own server on 8899; this one is
# yours to leave running.
desc "Serve the browser suite's fixture bundle at http://127.0.0.1:8808"
task :serve do
  sh "ruby -Ilib exe/okf server test/browser/fixtures/bundle"
end

task "test:integration" => :set_integration_coverage_dir

task :set_integration_coverage_dir do
  ENV["OKF_COVERAGE_DIR"] = "coverage/integration"
  ENV["OKF_COVERAGE_NAME"] = "Integration Tests (alone)"
end

# The Claude Code plugin (plugin/) carries a copy of the canonical skill and the
# gem's version in its manifest. This regenerates both from their sources
# (lib/okf/skill and lib/okf/version.rb); test/plugin/sync_test.rb fails
# whenever they drift, so the "single editable skill copy" constraint stays
# auditable in CI.
namespace :plugin do
  desc "Regenerate plugin/skills/okf from lib/okf/skill and stamp the gem version into plugin.json"
  task :sync do
    require "fileutils"
    require "json"
    require_relative "lib/okf/version"

    dest = File.expand_path("plugin/skills/okf", __dir__)
    FileUtils.rm_rf(dest)
    FileUtils.mkdir_p(dest)
    FileUtils.cp_r(File.join(File.expand_path("lib/okf/skill", __dir__), "."), dest)

    manifest_path = File.expand_path("plugin/.claude-plugin/plugin.json", __dir__)
    manifest = JSON.parse(File.read(manifest_path))
    manifest["version"] = OKF::VERSION
    File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")

    files = Dir.glob(File.join(dest, "**", "*")).count { |path| File.file?(path) }
    puts "plugin/skills/okf synced (#{files} files); plugin.json stamped #{OKF::VERSION}"
  end

  desc "Fail unless plugin.json carries the gem version"
  task :verify do
    require "json"
    require_relative "lib/okf/version"

    manifest = JSON.parse(File.read(File.expand_path("plugin/.claude-plugin/plugin.json", __dir__)))
    unless manifest["version"] == OKF::VERSION
      abort "plugin.json is at #{manifest["version"]} but the gem is #{OKF::VERSION}: run `bundle exec rake plugin:sync`"
    end
  end
end

# The plugin versions with the gem. Guarding `build` (which `release` runs
# first) makes a release with a stale manifest impossible, not just a CI
# failure after the fact.
task build: "plugin:verify"

# RuboCop only installs on newer Rubies (see Gemfile); the default task degrades
# to test-only where it is absent.
begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
  task default: %i[test rubocop]
rescue LoadError
  task default: %i[test]
end
