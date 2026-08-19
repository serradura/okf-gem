# frozen_string_literal: true

require "test_helper"
require "rbconfig"

# Loading contract, mirroring the kernel's: `require "okf/mcp"` pulls in the
# registry seam and the backends only. The MCP SDK, WEBrick and the argv
# shell all load on demand — from `okf/mcp/server`, `okf/mcp/http`, or the
# lazy `OKF::MCP.app` — so an embedding app never pays for the protocol
# machinery it does not serve.
class OKF::MCP::LoadingTest < OKF::TestCase
  LIB = File.expand_path("../../lib", __dir__)

  test "require \"okf/mcp\" loads neither the MCP SDK nor WEBrick" do
    assert_equal "light", probe(<<~RUBY)
      require "okf/mcp"
      heavy = defined?(::MCP) || defined?(::WEBrick)
      print(defined?(OKF::MCP::Registry) && !heavy ? "light" : "leaked")
    RUBY
  end

  test "OKF::MCP.app loads the protocol machinery on first call" do
    assert_equal "ok", probe(<<~RUBY)
      require "okf/mcp"
      app = OKF::MCP.app([ #{File.expand_path("../integration/fixtures/knowledge", __dir__).inspect} ])
      print(defined?(::MCP) && app.respond_to?(:call) && !defined?(::WEBrick) ? "ok" : "wrong")
    RUBY
  end

  private

  # A clean interpreter, resolved through bundler so the SDK is loadable when
  # asked for — the in-process suite has already required everything, so only
  # a fresh process can observe what a bare require pulls in.
  def probe(source)
    IO.popen([ RbConfig.ruby, "-rbundler/setup", "-I", LIB, "-e", source ], &:read)
  end
end
