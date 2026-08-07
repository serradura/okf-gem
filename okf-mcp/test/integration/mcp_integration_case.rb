# frozen_string_literal: true

require "test_helper"
require "okf/mcp/server"
require "json"

# Shared base for the per-tool integration tests. Each drives the real
# MCP::Server definition through real JSON-RPC frames — the exact strings a
# transport feeds `handle_json` — asserting on the tool result the way a host
# sees it: `isError`, the content text, the parsed payload. The transports
# themselves are proven end-to-end in cli_test.rb (a spawned exe over stdio)
# and http_test.rb (WEBrick on a real socket); everything else runs in-process
# so the integration coverage report counts it.
#
# This file is not named *_test.rb, so the test task loads it only via the
# require_relative in each tool file, never as a suite of its own.
class MCPIntegrationCase < OKF::TestCase
  BUNDLES = File.expand_path("fixtures", __dir__)

  # Common closure: a bundle only one group uses lives under that group; one
  # several groups share stays in the shared fixtures/.
  GROUP_FIXTURES = {
    "ByDir" => File.expand_path("by_dir/fixtures", __dir__),
    "ByRegistry" => File.expand_path("by_registry/fixtures", __dir__),
    "AcrossBundles" => File.expand_path("across_bundles/fixtures", __dir__)
  }.freeze

  # One tool call as the host reads it: the error flag, the raw content text,
  # and the payload parsed from it (nil when the text is not JSON — read_concept
  # returns markdown).
  Result = Struct.new(:error?, :text, :data)

  # $OKF_HOME and cwd are the two levers on the kernel registry, so isolation
  # is not something a test opts into: point $OKF_HOME at a scratch dir and
  # chdir into a scratch dir with no local .okf-registry.json above it, with
  # OKF_NO_DISCOVERY=1 as belt to the chdir's braces. A discovery test opts
  # *out* via #in_dir.
  setup do
    @out_dir = Dir.mktmpdir("okf-mcp-integration")
    @home = Dir.mktmpdir("okf-mcp-home")
    @cwd_dir = Dir.mktmpdir("okf-mcp-cwd")
    @okf_home_was = ENV.fetch("OKF_HOME", nil)
    @no_discovery_was = ENV.fetch("OKF_NO_DISCOVERY", nil)
    @cwd_was = Dir.pwd
    ENV["OKF_HOME"] = @home
    ENV["OKF_NO_DISCOVERY"] = "1"
    Dir.chdir(@cwd_dir)
    @rpc_id = 0
  end

  teardown do
    Dir.chdir(@cwd_was)
    @okf_home_was.nil? ? ENV.delete("OKF_HOME") : ENV["OKF_HOME"] = @okf_home_was
    @no_discovery_was.nil? ? ENV.delete("OKF_NO_DISCOVERY") : ENV["OKF_NO_DISCOVERY"] = @no_discovery_was
    FileUtils.rm_rf(@out_dir)
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@cwd_dir)
  end

  private

  def fixture(name)
    local = group_fixtures && File.join(group_fixtures, name)
    return local if local && File.directory?(local)

    File.join(BUNDLES, name)
  end

  def group_fixtures
    GROUP_FIXTURES[self.class.name.split("::").first]
  end

  # Boot the one server definition over argv-style roots (dirs and @refs), or
  # over the scratch $OKF_HOME registry when none are given — then run the real
  # initialize handshake so every later frame happens on an initialized server.
  def mcp_server(*args, engine: nil)
    registry = args.empty? ? OKF::MCP::Registry.from_kernel : OKF::MCP::Registry.from_argv(args)
    server = OKF::MCP::Server.build(registry, engine: engine || OKF::MCP::MemoryBackend.new)
    handshake(server)
    server
  end

  def handshake(server)
    response = rpc(server, "initialize",
      protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "okf-mcp-test", version: "0" })
    raise "handshake failed: #{response.inspect}" unless response["result"]

    server.handle_json(JSON.generate(jsonrpc: "2.0", method: "notifications/initialized"))
    response["result"]
  end

  # One raw JSON-RPC exchange, string in and parsed response out.
  def rpc(server, method, params = {})
    @rpc_id += 1
    request = { jsonrpc: "2.0", id: @rpc_id, method: method, params: params }
    JSON.parse(server.handle_json(JSON.generate(request)))
  end

  def call_tool(server, name, arguments = {})
    response = rpc(server, "tools/call", name: name, arguments: arguments)
    result = response.fetch("result") { raise "protocol error: #{response.inspect}" }
    text = result.fetch("content").first&.fetch("text")
    data = begin
      JSON.parse(text)
    rescue JSON::ParserError, TypeError
      nil
    end
    Result.new(result["isError"] ? true : false, text, data)
  end

  # A tool call that must succeed, returning the parsed payload.
  def call_tool!(server, name, arguments = {})
    result = call_tool(server, name, arguments)
    raise "tool #{name} errored: #{result.text}" if result.error?

    result.data
  end

  # Seed the scratch $OKF_HOME registry with fixture bundles, in the order
  # given — the first is the default. Returns the kernel registry so a test
  # can group or rename before booting.
  def with_registry(*names)
    registry = OKF::Registry.load
    names.each { |name| registry.add(fixture(name)) }
    yield registry
  end

  # A one-concept bundle under @out_dir — a directory a test is free to delete.
  # The committed fixtures cannot serve here: proving what a tool does when a
  # registered directory vanishes needs a bundle that *can* vanish, and a
  # fixture that deletes itself is not a fixture.
  def scratch_bundle(name)
    dir = File.join(@out_dir, name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "note.md"), "---\ntype: Note\ntitle: Scratch Note\n---\n\nA scratch concept.\n")
    dir
  end

  # Run the block from +dir+ as cwd with discovery *on* — how a test proves the
  # project-local .okf-registry.json wins while you stand in its tree.
  def in_dir(dir)
    was_cwd = Dir.pwd
    was_flag = ENV.fetch("OKF_NO_DISCOVERY", nil)
    ENV.delete("OKF_NO_DISCOVERY")
    Dir.chdir(dir)
    yield
  ensure
    Dir.chdir(was_cwd)
    was_flag.nil? ? ENV.delete("OKF_NO_DISCOVERY") : ENV["OKF_NO_DISCOVERY"] = was_flag
  end

  # The scan engine's score, by definition: the summed weight of the fields
  # that matched — how a test tells which engine answered, since the routing is
  # deliberately silent.
  def weight_sum(matched)
    matched.map { |field| OKF::Bundle::Search::WEIGHTS[field] }.reduce(0, :+)
  end

  def read_utf8(path)
    File.read(path, encoding: "UTF-8")
  end
end
