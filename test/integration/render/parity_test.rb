# frozen_string_literal: true

require "test_helper"

require "json"
require "rack/test"

require "okf"
require "okf/render/graph"
require "okf/server/app"

# The render/server contract, made executable. One client getter reads
# `EMBED.<key>` from a rendered file OR fetches the matching endpoint from a live
# server — so the baked payload (OKF::Render::Graph.payload) and OKF::Server::App's
# endpoints must expose the same data. They now derive from the same
# OKF::Bundle::Folder methods precisely so the two cannot drift once the static
# renderer no longer lives on the Rack app; this pins that they don't.
class OKF::Render::ParityTest < OKF::TestCase
  include Rack::Test::Methods

  attr_reader :app

  setup do
    @tmpdir = Dir.mktmpdir("okf-parity")
    write("index.md", %(---\nokf_version: "0.1"\n---\n\n# Root\n\n* [Orders](tables/orders.md)\n))
    write("log.md", "# Log\n\n## 2026-07-13\n* **Update**: seeded.\n")
    write("tables/orders.md", "---\ntype: Table\ntitle: Orders\ndescription: the orders table\n---\n\n[Home](../index.md) — the orders body.\n")
    write("notes/n.md", %(---\ntype: Note\ntitle: N\ntags: [x]\ndescription: "a <b>bold</b> claim"\n---\n\nPinned body.\n))
    @folder = OKF::Bundle::Folder.load(@tmpdir)
    @app = OKF::Server::App.new(@folder, title: "Demo")
  end

  teardown { FileUtils.rm_rf(@tmpdir) }

  test "the render bake exposes exactly the data the live endpoints serve" do
    bake = json_norm(OKF::Render::Graph.payload(@folder))

    assert_equal %w[catalog index logs bodies], bake.keys, "the four baked keys, in order"

    # /catalog, /index, /log wrap in an envelope the same arrays the bake carries bare
    assert_equal bake["catalog"], get_json("/catalog")["concepts"], "bake.catalog == GET /catalog"
    assert_equal bake["index"], get_json("/index")["directories"], "bake.index == GET /index"
    assert_equal bake["logs"], get_json("/log")["logs"], "bake.logs == GET /log"

    # /node serves, per id, the very body the bake bakes (a live read equals the
    # boot snapshot while nothing on disk has changed)
    refute_empty bake["bodies"]
    bake["bodies"].each do |id, body|
      get "/node", id: id
      assert_equal body, last_response.body, "bake.bodies[#{id}] == GET /node?id=#{id}"
    end
  end

  test "the bake omits meta, yet the server still serves the /node/meta the static page derives from the catalog" do
    bake = OKF::Render::Graph.payload(@folder)
    refute_includes bake.keys, :meta, "no meta map is baked — the static page derives it from the catalog"

    # the raw description the client will escape rides in the baked catalog…
    pinned = bake[:catalog].find { |concept| concept[:id] == "notes/n" }
    assert_equal "a <b>bold</b> claim", pinned[:description]

    # …and the live server still computes the escaped fragment on demand
    get "/node/meta", id: "notes/n"
    assert_includes last_response.body, "&lt;b&gt;"
    refute_includes last_response.body, "<b>bold</b>"
  end

  private

  def json_norm(obj)
    JSON.parse(JSON.generate(obj))
  end

  def get_json(path)
    get path
    JSON.parse(last_response.body)
  end

  def write(rel, content)
    target = File.join(@tmpdir, rel)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
end
