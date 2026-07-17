# frozen_string_literal: true

require "test_helper"
require "okf"
require "okf/cli"
require "okf/skill"
require "json"
require "tmpdir"

# Shared base for the per-command CLI integration tests (cli_graph_test.rb,
# cli_validate_test.rb, cli_lint_test.rb, cli_misc_test.rb, cli_skill_test.rb).
# Each drives the real OKF::CLI through the process streams — asserting on captured
# stdout/stderr and the exit code the way a user's terminal sees it — against the
# committed fixture bundles in test/integration/cli/fixtures.
#
# This file is not named *_test.rb, so the test task loads it only via the
# require_relative in each command file, never as a suite of its own.
class CLIIntegrationCase < OKF::TestCase
  BUNDLES = File.expand_path("fixtures", __dir__)

  # Common closure: a bundle only one group uses lives under that group, so it
  # changes when those tests change; one several groups share stays in the
  # shared fixtures/. `fixture` looks in the caller's group first, then shared —
  # so a test says fixture("navigation") without caring which it is.
  GROUP_FIXTURES = {
    "ByDir" => File.expand_path("by_dir/fixtures", __dir__),
    "ByRegistry" => File.expand_path("by_registry/fixtures", __dir__),
    "AcrossBundles" => File.expand_path("across_bundles/fixtures", __dir__)
  }.freeze

  Result = Struct.new(:status, :out, :err)

  setup do
    @out_dir = Dir.mktmpdir("okf-integration")
    @home = Dir.mktmpdir("okf-integration-home")
  end

  teardown do
    FileUtils.rm_rf(@out_dir)
    FileUtils.rm_rf(@home)
  end

  private

  def fixture(name)
    local = group_fixtures && File.join(group_fixtures, name)
    return local if local && File.directory?(local)

    File.join(BUNDLES, name)
  end

  # The fixtures dir belonging to this test's group, or nil at the root (where
  # the bundle-less commands live). Keyed off the namespace, so the folder and
  # the module never drift apart silently.
  def group_fixtures
    GROUP_FIXTURES[self.class.name.split("::").first]
  end

  # Register fixture bundles in the scratch registry and run the block with
  # $OKF_HOME pointing at it, so @refs resolve there and never at the real
  # ~/.okf. Returns whatever the block returns.
  def with_registry(*names)
    names.each { |name| okf("registry", "set", fixture(name), "--home", @home) }
    was = ENV.fetch("OKF_HOME", nil)
    ENV["OKF_HOME"] = @home
    yield
  ensure
    was.nil? ? ENV.delete("OKF_HOME") : ENV["OKF_HOME"] = was
  end

  # `okf server` blocks on a real runner, so the integration tests drive it with
  # an injected one that captures the app instead of listening: every
  # synchronous path (argv parsing, mode selection, the mount table) runs for
  # real, and nothing opens a socket.
  def okf_server(*argv)
    booted = []
    status = nil
    out, err = capture_io do
      cli = OKF::CLI.new(runner: ->(app, host, port) { booted << [ app, host, port ] })
      status = cli.run([ "server", *argv ])
    end
    [ Result.new(status, out, err), booted.first ]
  end

  # The app a booted server handed the runner, unwrapped from the gzip middleware.
  def booted_app(app)
    app.is_a?(Rack::Deflater) ? app.instance_variable_get(:@app) : app
  end

  def json(result)
    JSON.parse(result.out)
  end

  # Read a file the CLI wrote, as UTF-8. Not a formality: the 2.4 Docker check
  # runs with no locale, so Encoding.default_external is US-ASCII, and a plain
  # File.read tags a page containing `·` or `—` as US-ASCII with invalid bytes —
  # which then raises the moment a test matches it. The gem reads its own files
  # with an explicit encoding for the same reason; tests must too.
  def read_utf8(path)
    File.read(path, encoding: "UTF-8")
  end

  # Run the CLI through the process streams, returning status + captured output.
  def okf(*argv)
    status = nil
    out, err = capture_io { status = OKF::CLI.start(argv) }
    Result.new(status, out, err)
  end

  # Run the CLI writing to the live $stdout/$stderr so assert_output can capture
  # it; returns the exit status. (Named `start_cli`, not `run`, so it does not
  # shadow Minitest::Runnable#run.)
  def start_cli(*argv)
    OKF::CLI.start(argv)
  end
end
