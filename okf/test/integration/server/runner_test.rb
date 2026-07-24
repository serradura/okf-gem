# frozen_string_literal: true

require "test_helper"

require "net/http"
require "uri"
require "stringio"
require "zlib"

require "okf"
require "okf/server/app"
require "okf/server/runner"
require "rack/deflater"

# The built-in WEBrick runner over a real socket — the piece `okf server` uses in
# place of a rackup dependency. Boots on an ephemeral port, exercises the
# WEBrick-request → Rack-env → response bridge end to end, then shuts down.
class OKF::Server::RunnerTest < OKF::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("okf-runner-test")
    File.write(
      File.join(@tmpdir, "a.md"),
      "---\ntype: Note\ntitle: A\ndescription: alpha\n---\n\nBody of A.\n"
    )
    app = OKF::Server::App.new(OKF::Bundle::Folder.load(@tmpdir), title: "Runner")
    app = Rack::Deflater.new(app) # the same boot-seam wrap `okf server` applies — exercise the real transport
    @server = OKF::Server::Runner.build(app, host: "127.0.0.1", port: 0)
    @port = @server.listeners.first.addr[1]
    @thread = Thread.new { @server.start }
  end

  teardown do
    @server.shutdown
    @thread.join
    FileUtils.rm_rf(@tmpdir)
  end

  test "serves the app over HTTP: page, node body, query params, and 404s" do
    page = get("/")
    assert_equal "200", page.code
    assert_match %r{text/html}, page["content-type"]
    assert_includes page.body, "<!doctype html"

    node = get("/node?id=a")
    assert_equal "200", node.code
    assert_match %r{text/markdown}, node["content-type"]
    assert_equal "Body of A.", node.body.strip

    assert_equal "404", get("/node?id=ghost").code
    assert_equal "404", get("/nope").code
  end

  # Rack::Deflater rides at the boot seam: a client that accepts gzip gets a
  # gzipped body (losslessly the same page), one that does not gets identity.
  test "gzips the response for a client that accepts it, identity otherwise" do
    plain = get("/", "Accept-Encoding" => "identity")
    assert_equal "200", plain.code
    assert_nil plain["content-encoding"], "a client that declines gzip gets an uncompressed body"

    gz = get("/", "Accept-Encoding" => "gzip")
    assert_equal "200", gz.code
    assert_equal "gzip", gz["content-encoding"] # Net::HTTP reads headers case-insensitively (rack 2 vs 3)
    assert_match(/Accept-Encoding/i, gz["vary"].to_s)

    decoded = Zlib::GzipReader.new(StringIO.new(gz.body)).read
    assert_includes decoded, "<!doctype html"
    assert_equal plain.body.b, decoded.b, "the gzipped body round-trips to the identity page, byte for byte"
  end

  private

  # Setting Accept-Encoding ourselves also turns off Net::HTTP's own transparent
  # decompression, so `gzip` yields the raw compressed bytes to round-trip.
  def get(path, headers = {})
    Net::HTTP.start("127.0.0.1", @port) { |http| http.get(path, headers) }
  end
end
