# frozen_string_literal: true

require_relative "mcp_integration_case"
require "okf/mcp/cli"
require "open3"
require "timeout"

# The argv shell: flags and exit codes driven in-process (the coverage report
# counts them), and one true end-to-end run — the spawned exe over stdio, real
# handshake, real frames — proving the transport the hosts actually use.
class CLITest < MCPIntegrationCase
  EXE = File.expand_path("../../exe/okf-mcp", __dir__)

  Result = Struct.new(:status, :out, :err)

  test "--version prints the version and exits 0" do
    result = run_cli("--version")
    assert_equal 0, result.status
    assert_equal OKF::MCP::VERSION, result.out.strip
  end

  test "--help prints usage and exits 0" do
    result = run_cli("--help")
    assert_equal 0, result.status
    assert_match(/usage: okf-mcp/, result.out)
    assert_match(/--http/, result.out)
  end

  test "a bad flag is a usage error: exit 2, message and usage on stderr" do
    result = run_cli("--bogus")
    assert_equal 2, result.status
    assert_match(/invalid option: --bogus/, result.err)
    assert_match(/usage: okf-mcp/, result.err)
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

  test "a vanished group member is a boot note on stderr, not a fatal" do
    dir = scratch_bundle("goner")
    registry = OKF::Registry.load
    registry.add(fixture("knowledge"))
    registry.add(dir)
    registry.set_group("docs", %w[knowledge goner])
    FileUtils.rm_rf(dir)

    Timeout.timeout(30) do
      Open3.popen3(RbConfig.ruby, "-rbundler/setup", "-I#{File.expand_path("../../lib", __dir__)}",
        EXE, "@docs") do |stdin, _stdout, stderr, wait|
        stdin.close
        assert_equal 0, wait.value.exitstatus
        boot = stderr.read
        assert_match(/okf-mcp: skipped goner: .* is gone/, boot)
        assert_match(/bundles: knowledge \(/, boot)
      end
    end
  end

  test "the spawned exe speaks MCP over stdio and announces itself on stderr" do
    Timeout.timeout(30) do
      Open3.popen3(RbConfig.ruby, "-rbundler/setup", "-I#{File.expand_path("../../lib", __dir__)}",
        EXE, fixture("knowledge")) do |stdin, stdout, stderr, wait|
        write_frame(stdin, id: 1, method: "initialize",
          params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "0" } })
        initialize_result = read_frame(stdout).fetch("result")
        assert_equal "okf", initialize_result.dig("serverInfo", "name")
        assert_equal OKF::MCP::VERSION, initialize_result.dig("serverInfo", "version")
        assert_match(/orient\s+with dirs/, initialize_result["instructions"])

        stdin.puts(JSON.generate(jsonrpc: "2.0", method: "notifications/initialized"))

        write_frame(stdin, id: 2, method: "tools/list", params: {})
        names = read_frame(stdout).dig("result", "tools").map { |tool| tool["name"] }
        assert_equal %w[list_bundles dirs index search read_concept catalog log validate lint graph], names

        write_frame(stdin, id: 3, method: "tools/call", params: { name: "dirs", arguments: { bundle: "knowledge" } })
        result = read_frame(stdout).fetch("result")
        refute result["isError"]
        assert_equal 4, JSON.parse(result.dig("content", 0, "text"))["total"]

        # EOF on stdin ends the session; the boot line arrived on stderr, never stdout.
        stdin.close
        assert_equal 0, wait.value.exitstatus
        boot = stderr.read
        assert_match(/okf-mcp #{Regexp.escape(OKF::MCP::VERSION)} — backend: memory — bundles: knowledge \(/, boot)
      end
    end
  end

  private

  # The CLI in-process, as the kernel's suite drives its own: captured streams,
  # returned status — exe/okf-mcp is the only place that exits.
  def run_cli(*argv)
    status = nil
    out, err = capture_io { status = OKF::MCP::CLI.run(argv, out: $stderr) }
    Result.new(status, out, err)
  end

  def write_frame(stdin, payload)
    stdin.puts(JSON.generate({ jsonrpc: "2.0" }.merge(payload)))
    stdin.flush
  end

  def read_frame(stdout)
    line = stdout.gets
    refute_nil line, "the server closed stdout before answering"
    JSON.parse(line)
  end
end
