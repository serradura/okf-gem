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

  # $OKF_HOME is the only lever the CLI offers on the registry, so isolation is
  # not something a test opts into: point it at a scratch dir for *every* test,
  # and the real ~/.okf is unreachable from the suite by construction. A test
  # that never touches the registry simply leaves the scratch one empty.
  setup do
    @out_dir = Dir.mktmpdir("okf-integration")
    @home = Dir.mktmpdir("okf-integration-home")
    @okf_home_was = ENV.fetch("OKF_HOME", nil)
    ENV["OKF_HOME"] = @home
  end

  teardown do
    @okf_home_was.nil? ? ENV.delete("OKF_HOME") : ENV["OKF_HOME"] = @okf_home_was
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

  # Seed the scratch registry with fixture bundles, in the order given — the
  # first is the default. $OKF_HOME already points at it (see setup), so this
  # only registers; naming the block is what marks a test as registry-shaped.
  # Returns whatever the block returns.
  def with_registry(*names)
    names.each { |name| okf("registry", "set", fixture(name)) }
    yield
  end

  # A one-concept bundle under @out_dir — a directory a test is free to delete.
  # The committed fixtures cannot serve here: proving what the CLI does when a
  # registered directory vanishes needs a bundle that *can* vanish, and a
  # fixture that deletes itself is not a fixture.
  def scratch_bundle(name)
    dir = File.join(@out_dir, name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "note.md"), "---\ntype: Note\ntitle: Scratch Note\n---\n\nA scratch concept.\n")
    dir
  end

  # A one-concept bundle under @out_dir whose only concept file cannot be read —
  # the file exists and globs, so the bundle is *on disk*, but File.read raises
  # EACCES. The one shape that separates "the directory is there" from "the
  # reader can use it", which is where the two of them used to disagree.
  def unreadable_bundle(name)
    make_unreadable(scratch_bundle(name))
  end

  # Rot a scratch bundle's concept file in place. Separate from #unreadable_bundle
  # so a test can register the bundle while it is still healthy and lock it after:
  # `registry set` reads the bundle to count its concepts, so a bundle born
  # unreadable never survives its own registration, and a test that dies there
  # proves nothing about what the server does with the entry.
  def make_unreadable(dir)
    File.chmod(0o000, File.join(dir, "note.md"))
    dir
  end

  # The scan engine's score, by definition: the summed weight of the fields that
  # matched. It is how a test tells which engine answered, since the routing is
  # deliberately silent and prints nothing.
  #
  # The score's *class* looks like the easier tell — the scan sums integers, the
  # index returns BM25 floats — and it is wrong: `Integer#round(4)` returns a
  # Float on Ruby 2.4, so a scan row's score is 12.0 there and 12 everywhere
  # else. The floor caught it. Comparing values, not classes, is portable.
  def weight_sum(matched)
    matched.map { |field| OKF::Bundle::Search::WEIGHTS[field] }.reduce(0, :+)
  end

  # chmod cannot deny root, so a permission-shaped test asserts nothing when the
  # suite runs as one — which the Ruby 2.4 Docker check does. Skip rather than
  # pass vacuously: a test that goes green because the world is not the way it
  # says it is certifies nothing.
  def skip_unless_permissions_bite
    skip "running as root — chmod cannot make a file unreadable" if Process.uid.zero?
  end

  # Point $OKF_HOME at a different registry for the block. It is the CLI's only
  # lever, so this is how a test proves two registries stay separate; teardown
  # restores the scratch one either way.
  def with_home(dir)
    was = ENV.fetch("OKF_HOME", nil)
    ENV["OKF_HOME"] = dir
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
  rescue SystemExit => e
    # The CLI *returns* its exit code; `exe/okf` is the only place that exits.
    # A path that calls exit itself takes the whole runner down with it —
    # Minitest lets SystemExit through — truncating the suite into a half-report
    # with no failure named and every later test silently unrun. Name it here so
    # the cause is legible instead of archaeological. The usual culprit is a new
    # OptionParser inheriting the officious --help; see CLI#help_flag.
    flunk "okf #{argv.join(" ")} called exit(#{e.status}) instead of returning a status"
  end

  # Run the CLI writing to the live $stdout/$stderr so assert_output can capture
  # it; returns the exit status. (Named `start_cli`, not `run`, so it does not
  # shadow Minitest::Runnable#run.)
  def start_cli(*argv)
    OKF::CLI.start(argv)
  end
end
