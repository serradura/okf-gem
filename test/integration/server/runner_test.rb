# frozen_string_literal: true

require "test_helper"

require "net/http"
require "uri"

require "okf"
require "okf/server/app"
require "okf/server/runner"

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

  private

  def get(path)
    Net::HTTP.get_response(URI("http://127.0.0.1:#{@port}#{path}"))
  end
end
