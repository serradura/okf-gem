# frozen_string_literal: true

require_relative "mcp_integration_case"
require_relative "http_harness"
require "socket"
require "io/wait"

# The modern (SEP-2575) `subscriptions/listen` stream through the real WEBrick
# bridge. The SDK answers listen with a Rack streaming body — a callable that
# writes SSE frames as they happen — so this is the one response shape the
# bridge cannot buffer: these tests read the wire with a raw TCPSocket,
# because Net::HTTP holds a chunked body back until EOF and a stream that
# stays open would read as a hang.
class HTTPListenTest < MCPIntegrationCase
  include HTTPHarness

  MODERN = "2026-07-28"

  test "subscriptions/listen answers a streamed SSE acknowledgement, not a 500" do
    with_http_server do |port|
      socket = listen_socket(port, id: 7, notifications: {})
      begin
        head = read_until(socket, "\r\n\r\n")
        assert_match %r{\AHTTP/1\.\d 200 }, head,
          "the listen stream must open as 200, got:\n#{head}"
        assert_match %r{content-type:\s*text/event-stream}i, head
        assert_match %r{transfer-encoding:\s*chunked}i, head

        frame = read_until(socket, "notifications/subscriptions/acknowledged", buffer: head)
        assert_includes frame, "\"io.modelcontextprotocol/subscriptionId\":7",
          "the acknowledgement correlates the stream to the request id"
      ensure
        socket.close
      end
    end
  end

  # The capabilities declare no listChanged and no subscribe, so there is
  # nothing a listen can be told about — the acknowledgement must honor an
  # empty subset, never echo the asked-for filter back as a promise.
  test "the honored filter is empty — this server's capabilities promise no notifications" do
    with_http_server do |port|
      socket = listen_socket(port, id: 11, notifications: { toolsListChanged: true })
      begin
        frame = read_until(socket, "notifications/subscriptions/acknowledged")
        ack = JSON.parse(frame[/data: (.+)/, 1])
        assert_equal({}, ack.dig("params", "notifications"),
          "an unhonorable filter must be acknowledged as empty, not echoed")
      ensure
        socket.close
      end
    end
  end

  # Pins the teardown order #stop encodes: the transport's close ends each
  # stream with its graceful SubscriptionsListenResult, the parked handler
  # threads return, and only then can WEBrick's shutdown — which *joins* the
  # connection threads — complete instead of hanging on an open stream.
  test "transport close ends an open stream gracefully and shutdown does not hang" do
    with_http_server do |port, app, httpd, thread|
      socket = listen_socket(port, id: 3, notifications: {})
      begin
        seen = read_until(socket, "notifications/subscriptions/acknowledged")
        app.close
        finale = read_until(socket, "\"resultType\":\"complete\"", buffer: seen)
        assert_includes finale, "\"io.modelcontextprotocol/subscriptionId\":3",
          "the closing result correlates back to the listen request"
        httpd.shutdown
        assert thread.join(5), "shutdown hung on an open listen stream"
      ensure
        socket.close
      end
    end
  end

  # The load-bearing assumption behind the whole adapter: a dead peer's EPIPE
  # raises out of a keepalive write into the SDK's cleanup, which frees the
  # stream's slot. If that ever stops being true, the cap fills with ghosts.
  test "listens past the cap are 503 until a dead peer's slot is freed" do
    with_http_server(max_listen_subscriptions: 1, listen_keepalive_interval: 0.2) do |port|
      first = listen_socket(port, id: 21, notifications: {})
      read_until(first, "notifications/subscriptions/acknowledged")

      second = listen_socket(port, id: 22, notifications: {})
      begin
        head = read_until(second, "\r\n\r\n")
        assert_match %r{\AHTTP/1\.\d 503 }, head, "past the cap the answer is 503, got:\n#{head}"
      ensure
        second.close
      end

      # An abrupt close, no goodbye — the keepalive's next write is what
      # notices. Poll until the freed slot admits a fresh listen.
      first.close
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      acked = false
      until acked
        flunk "the dead peer's slot was never freed" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        retry_socket = listen_socket(port, id: 23, notifications: {})
        begin
          head = read_until(retry_socket, "\r\n\r\n")
          if head.include?(" 200 ")
            read_until(retry_socket, "notifications/subscriptions/acknowledged", buffer: head)
            acked = true
          else
            sleep 0.2
          end
        ensure
          retry_socket.close
        end
      end
    end
  end

  private

  # A hand-written modern listen POST, held open. The envelope pair and the
  # Mcp-Method mirror header are what the SEP-2575 path refuses without.
  def listen_socket(port, id:, notifications:)
    body = JSON.generate(
      jsonrpc: "2.0", id: id, method: "subscriptions/listen",
      params: {
        notifications: notifications,
        _meta: {
          "io.modelcontextprotocol/protocolVersion" => MODERN,
          "io.modelcontextprotocol/clientCapabilities" => {}
        }
      }
    )
    socket = TCPSocket.new("127.0.0.1", port)
    socket.write(
      "POST / HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n" \
      "Accept: application/json, text/event-stream\r\n" \
      "MCP-Protocol-Version: #{MODERN}\r\nMcp-Method: subscriptions/listen\r\n" \
      "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
    )
    socket
  end

  # Accumulates reads until the buffer carries +pattern+. Every read is
  # deadline-bounded so an unanswered stream fails the test instead of
  # hanging the suite; EOF returns what arrived, for the assertion to name.
  # Sequential reads on one socket must thread the returned buffer back in
  # via +buffer+ — one readpartial can carry the next frame along with the
  # awaited one, and a fresh buffer would silently drop it.
  def read_until(socket, pattern, timeout: 5, buffer: +"")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until buffer.include?(pattern)
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      flunk "timed out waiting for #{pattern.inspect}; read so far: #{buffer.inspect}" if remaining <= 0
      flunk "stream went quiet waiting for #{pattern.inspect}; read so far: #{buffer.inspect}" unless socket.wait_readable(remaining)
      begin
        buffer << socket.readpartial(4096)
      rescue EOFError
        break
      end
    end
    buffer
  end
end
