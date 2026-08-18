# frozen_string_literal: true

require "okf/mcp/http"
require "net/http"

# The shared boot and wire helpers for the HTTP-transport tests — one copy,
# included by http_test.rb, http_listen_test.rb and http_modern_test.rb, so
# the three surfaces cannot drift apart in how they compose the bridge.
# Lives beside the tests that need WEBrick loaded, never in the shared case:
# the in-process tool tests must not pay for the transport.
module HTTPHarness
  private

  # The composition #serve performs, on an ephemeral port a test can own:
  # the wired transport, the WEBrick bridge, a thread to run it.
  # +listen_options+ reach the SDK through app_for — the cap tests shrink
  # `max_listen_subscriptions:` and `listen_keepalive_interval:` to test
  # scale through the real option seam.
  def with_http_server(**listen_options)
    registry = OKF::MCP::Registry.from_argv([ fixture("knowledge") ])
    server = OKF::MCP::Server.build(registry, engine: OKF::MCP::MemoryBackend.new)
    app = OKF::MCP::HTTP.app_for(server, bind: "127.0.0.1", **listen_options)
    httpd = OKF::MCP::HTTP.build(app, bind: "127.0.0.1", port: 0)
    thread = Thread.new { httpd.start }
    port = httpd.listeners.first.addr[1]
    begin
      yield port, app, httpd, thread
    ensure
      # stop closes the transport before WEBrick: open listen streams end and
      # their parked handler threads return, so shutdown's join can finish.
      # The bounded join with a kill fallback keeps a wedged accept loop from
      # hanging the whole suite and swallowing the assertion that failed.
      OKF::MCP::HTTP.stop(httpd, app)
      thread.kill unless thread.join(5)
    end
  end

  # A Hash payload is encoded; a String is sent as-is, which is how the
  # oversized-body test gets bytes past the JSON generator. +headers+ adds or
  # overrides — the modern-path tests carry their mirror headers through it.
  def post(port, payload, host: nil, path: "/", headers: {})
    http = Net::HTTP.new("127.0.0.1", port)
    http.open_timeout = 10
    http.read_timeout = 10
    request = Net::HTTP::Post.new(path, "Content-Type" => "application/json",
      "Accept" => "application/json, text/event-stream")
    request["Host"] = host if host
    headers.each { |name, value| request[name] = value }
    request.body = payload.is_a?(String) ? payload : JSON.generate(payload)
    http.request(request)
  end
end
