# frozen_string_literal: true

require_relative "mcp_integration_case"
require "okf/cli"
require "okf/plugin"
require "open3"
require "timeout"

# The entry point: `okf mcp`, registered through the kernel's plugin seam.
# There is no second one — the `exe/okf-mcp` that used to alias this went
# before the first release — so everything a host does starts here.
#
# Two halves, because they prove different things. In-process runs drive the
# kernel's own dispatcher with injected streams — the verb's dispatch and the
# contract that a command writes *nowhere* but the streams it was handed;
# cli_test.rb owns the argv semantics behind it. The spawned runs prove what no
# in-process test can: that discovery finds the plugin file where the seam
# looks for it, that a real process speaks the protocol, and that stdout
# carries JSON-RPC and nothing else once the transport is up.
class CLIPluginTest < MCPIntegrationCase
  OKF_EXE = Gem.bin_path("okf", "okf")
  LIB = File.expand_path("../../lib", __dir__)

  Result = Struct.new(:status, :out, :err)

  test "the verb registers itself into the extension group" do
    command = OKF::CLI.lookup("mcp")
    refute_nil command, "okf/plugin.rb did not register a `mcp` verb"
    assert_equal :extension, command.group
    assert_equal 1, command.help_rows.size
  end

  test "--help prints okf-mcp's usage to the injected stream, exit 0" do
    result = run_okf("mcp", "--help")
    assert_equal 0, result.status
    assert_match(/usage: okf mcp/, result.out)
    assert_match(/--http/, result.out)
    assert_equal "", result.err
  end

  test "--version prints okf-mcp's version, not the kernel's" do
    result = run_okf("mcp", "--version")
    assert_equal 0, result.status
    assert_equal OKF::MCP::VERSION, result.out.strip
  end

  test "a bad flag keeps the usage-error contract through the seam: exit 2 on stderr" do
    result = run_okf("mcp", "--bogus")
    assert_equal 2, result.status
    assert_match(/invalid option: --bogus/, result.err)
    assert_match(/usage: okf mcp/, result.err)
    assert_equal "", result.out
  end

  test "a boot refusal names the directory it could not use" do
    result = run_okf("mcp", "no/such/dir")
    assert_equal 2, result.status
    assert_match(%r{no such directory: no/such/dir}, result.err)
  end

  test "no args and an empty registry points at okf registry set" do
    result = run_okf("mcp")
    assert_equal 2, result.status
    assert_match(/no bundles registered — run `okf registry set <dir>`/, result.err)
  end

  test "okf help lists the verb under installed extensions" do
    result = spawn_okf("help")
    assert_equal 0, result.status
    assert_match(/installed extensions/, result.out)
    assert_match(/^\s+mcp\s+.*serve bundles over the Model Context Protocol$/, result.out)
  end

  # One spawn, the whole round trip: handshake, tool list, a real call, and the
  # purity check on the way out. It is the only end-to-end proof of the
  # transport every host actually uses, so it earns its process.
  test "the verb speaks MCP over stdio, and stdout carries only frames" do
    Timeout.timeout(30) do
      spawn_verb(fixture("knowledge")) do |stdin, stdout, stderr, wait|
        write_frame(stdin, id: 1, method: "initialize",
          params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "0" } })
        # The purity check: the first thing on stdout is a frame, not a boot
        # line, a plugin note, or an okf banner.
        initialize_result = read_frame(stdout).fetch("result")
        assert_equal "okf", initialize_result.dig("serverInfo", "name")
        assert_equal OKF::MCP::VERSION, initialize_result.dig("serverInfo", "version")
        assert_match(/orient\s+with dirs/, initialize_result["instructions"])

        stdin.puts(JSON.generate(jsonrpc: "2.0", method: "notifications/initialized"))

        write_frame(stdin, id: 2, method: "tools/list", params: {})
        names = read_frame(stdout).dig("result", "tools").map { |tool| tool["name"] }
        assert_equal %w[list_bundles dirs index search read_concept catalog log validate lint graph references tags types stats], names

        write_frame(stdin, id: 3, method: "tools/call", params: { name: "dirs", arguments: { bundle: "knowledge" } })
        result = read_frame(stdout).fetch("result")
        refute result["isError"]
        assert_equal 4, JSON.parse(result.dig("content", 0, "text"))["total"]

        # EOF on stdin ends the session; the boot line arrived on stderr, never stdout.
        stdin.close
        assert_equal 0, wait.value.exitstatus
        assert_equal "", stdout.read, "stdout carried something after the last frame"
        assert_match(/okf-mcp #{Regexp.escape(OKF::MCP::VERSION)} — backend: memory — bundles: knowledge \(/, stderr.read)
      end
    end
  end

  # A group is resolved at boot, and one dead member must not take the process
  # down with it — spawned rather than in-process because the note and the boot
  # line are the whole answer, and both go to the real stderr.
  test "a vanished group member is a boot note on stderr, not a fatal" do
    dir = scratch_bundle("goner")
    registry = OKF::Registry.load
    registry.add(fixture("knowledge"))
    registry.add(dir)
    registry.set_group("docs", %w[knowledge goner])
    FileUtils.rm_rf(dir)

    Timeout.timeout(30) do
      spawn_verb("@docs") do |stdin, _stdout, stderr, wait|
        stdin.close
        assert_equal 0, wait.value.exitstatus
        boot = stderr.read
        assert_match(/okf-mcp: skipped goner: .* is gone/, boot)
        assert_match(/bundles: knowledge \(/, boot)
      end
    end
  end

  private

  def spawn_verb(*args, &block)
    Open3.popen3(RbConfig.ruby, "-rbundler/setup", "-I#{LIB}", OKF_EXE, "mcp", *args, &block)
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

  # The kernel's dispatcher in-process, with streams it must not write outside
  # of. `okf mcp` is unknown to the base gem, so this walks the same
  # lookup-miss → load_plugins → lookup path a real run takes.
  def run_okf(*argv)
    out = StringIO.new
    err = StringIO.new
    status = OKF::CLI.new(out: out, err: err).run(argv)
    Result.new(status, out.string, err.string)
  end

  def spawn_okf(*argv)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-rbundler/setup", "-I#{LIB}", OKF_EXE, *argv)
    Result.new(status.exitstatus, stdout, stderr)
  end
end
