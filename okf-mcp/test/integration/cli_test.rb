# frozen_string_literal: true

require_relative "mcp_integration_case"
require "okf/mcp/cli"

# The argv shell, in-process: flags, refusals and exit codes, driven straight
# at OKF::MCP::CLI so the coverage report counts them.
#
# Nothing here spawns. There is one entry point — the `okf mcp` verb — and
# cli_plugin_test.rb owns every test that runs it as a real process, so a
# claim about argv is proven once, cheaply, here, and a claim about the
# process is proven once, there.
class CLITest < MCPIntegrationCase
  Result = Struct.new(:status, :out, :err)

  test "--version prints the version and exits 0" do
    result = run_cli("--version")
    assert_equal 0, result.status
    assert_equal OKF::MCP::VERSION, result.out.strip
  end

  test "--help prints usage and exits 0" do
    result = run_cli("--help")
    assert_equal 0, result.status
    assert_match(/usage: okf mcp/, result.out)
    assert_match(/--http/, result.out)
  end

  test "a bad flag is a usage error: exit 2, message and usage on stderr" do
    result = run_cli("--bogus")
    assert_equal 2, result.status
    assert_match(/invalid option: --bogus/, result.err)
    assert_match(/usage: okf mcp/, result.err)
  end

  test "no args and an empty registry is a usage error pointing at okf registry set" do
    result = run_cli
    assert_equal 2, result.status
    assert_match(/no bundles registered — run `okf registry set <dir>`/, result.err)
  end

  test "a nonexistent directory is a usage error" do
    result = run_cli("no/such/dir")
    assert_equal 2, result.status
    assert_match(%r{no such directory: no/such/dir}, result.err)
  end

  test "an unknown ref is a usage error naming the registry file" do
    result = run_cli("@nope")
    assert_equal 2, result.status
    assert_match(/unknown ref @nope/, result.err)
  end

  test "a bare @ with an empty registry is a usage error" do
    result = run_cli("@")
    assert_equal 2, result.status
    assert_match(/no default bundle: the registry is empty/, result.err)
  end

  test "a ref that normalizes to nothing is a bad ref, never a minted name" do
    result = run_cli("@***")
    assert_equal 2, result.status
    assert_match(/unknown ref @\*\*\*/, result.err)
  end

  test "a ref whose registered directory vanished is a usage error at boot" do
    dir = scratch_bundle("goner")
    OKF::Registry.load.add(dir)
    FileUtils.rm_rf(dir)
    result = run_cli("@goner")
    assert_equal 2, result.status
    assert_match(/registered as goner\) is not a directory/, result.err)
  end

  private

  # The CLI in-process, as the kernel's suite drives its own: captured streams,
  # returned status. Nothing here exits — the kernel's exe/okf does that, with
  # the status the verb hands back.
  def run_cli(*argv)
    status = nil
    out, err = capture_io { status = OKF::MCP::CLI.run(argv, out: $stderr) }
    Result.new(status, out, err)
  end
end
