# frozen_string_literal: true

require "test_helper"
require "okf/mcp/http"

# The Stream adapter's one liveness contract: #close belongs to shutdown, so
# it must never wait on a peer. A stalled listen client — alive, not reading,
# TCP send buffer full — blocks the keepalive's write indefinitely with no
# EPIPE to raise, and a close that queues behind that write turns one wedged
# peer into a server that only dies to SIGKILL.
class OKF::MCP::HTTPStreamTest < OKF::TestCase
  # The stalled peer: every write parks until the test releases it.
  class StalledWire
    def initialize
      @gate = Queue.new
    end

    def write(_data)
      @gate.pop
    end

    def release
      @gate << true
    end
  end

  class NullWire
    def write(_data); end
  end

  test "close never waits behind a stalled peer's write" do
    wire = StalledWire.new
    stream = OKF::MCP::HTTP::Stream.new(wire)
    writer = Thread.new do
      stream.write("data: ping\n\n")
    rescue IOError
      nil
    end
    Thread.pass until writer.status == "sleep"

    closer = Thread.new { stream.close }
    unless closer.join(2)
      writer.kill
      closer.kill
      flunk "Stream#close blocked behind a stalled peer's write"
    end

    waiter = Thread.new { stream.wait }
    assert waiter.join(2), "wait did not return after close"
  ensure
    wire.release
    writer&.join(2)
  end

  test "a write after close is refused, not sent" do
    stream = OKF::MCP::HTTP::Stream.new(NullWire.new)
    stream.close
    assert_raises(IOError) { stream.write("data: late\n\n") }
  end

  # A supervisor sends exactly one signal, so a listen registering in the
  # microseconds around the transport's close must not park forever: once the
  # ledger's latch has tripped, admission closes the stream on the spot.
  test "a stream admitted after close_all is closed instantly, never parked" do
    streams = OKF::MCP::HTTP::Streams.new
    streams.close_all

    stream = OKF::MCP::HTTP::Stream.new(NullWire.new)
    streams.admit(stream)
    waiter = Thread.new { stream.wait }
    assert waiter.join(2), "a late-admitted stream parked instead of closing"
  end

  test "close_all closes every admitted stream and discard forgets one" do
    streams = OKF::MCP::HTTP::Streams.new
    kept = OKF::MCP::HTTP::Stream.new(NullWire.new)
    dropped = OKF::MCP::HTTP::Stream.new(NullWire.new)
    streams.admit(kept)
    streams.admit(dropped)
    streams.discard(dropped)
    streams.close_all

    waiter = Thread.new { kept.wait }
    assert waiter.join(2), "an admitted stream survived close_all"
    assert_raises(IOError) { kept.write("data: x\n\n") }
  end
end
