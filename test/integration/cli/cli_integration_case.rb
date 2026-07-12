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

  Result = Struct.new(:status, :out, :err)

  setup { @out_dir = Dir.mktmpdir("okf-integration") }
  teardown { FileUtils.rm_rf(@out_dir) }

  private

  def fixture(name)
    File.join(BUNDLES, name)
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
