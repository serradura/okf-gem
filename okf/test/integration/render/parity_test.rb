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

    # `bodies` and `sources` are the two named exceptions to "baked ↔ endpoint
    # parity": neither has a bare endpoint of its own — bodies are served per
    # node, and the server deliberately carries only a source *count* on a
    # catalog row rather than fattening every fetch to serve one view.
    assert_equal %w[catalog index logs bodies sources], bake.keys, "the five baked keys, in order"

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

  test "the bake omits meta, yet the server serves the same fields the static page reads off its catalog row" do
    bake = OKF::Render::Graph.payload(@folder)
    refute_includes bake.keys, :meta, "no meta map is baked — the static page composes it from the catalog row"

    # the raw description the client will render via textContent rides in the baked catalog…
    pinned = bake[:catalog].find { |concept| concept[:id] == "notes/n" }
    assert_equal "a <b>bold</b> claim", pinned[:description]

    # …and the live server answers the same raw string as JSON, one composition
    # client-side for both modes
    get "/node/meta", id: "notes/n"
    assert_equal "a <b>bold</b> claim", JSON.parse(last_response.body).fetch("description")
  end

  test "the baked sources text matches what the Ruby engines index, empty strings included" do
    bake = OKF::Render::Graph.payload(@folder)

    bake[:sources].each_value { |text| assert_kind_of String, text }
    assert_equal @folder.concepts.map(&:id).sort, bake[:sources].keys.sort,
      "every concept bakes a sources string — an undefined getter throws client-side"
  end

  # §5.3's display rule runs in two places by necessity: Ruby, for /node/meta and
  # for every consumer of the library (okf-tui asks Concept#shows_trust?), and JS,
  # for the baked page, which has no Ruby to call. Two spellings of one rule is
  # exactly the shape RowFilter was extracted to end, so this pins them.
  #
  # What it catches: a change to either side alone. The truth table below is the
  # JS expression's semantics, written out; the Ruby is asserted against it, and
  # the JS source against its literal. Change the rule in Ruby and the table
  # fails here, beside the JS text that must move with it.
  SHOWS_TRUST_JS = "const showsTrust=c=>!!(c.trust&&!(c.trust==='unverified'&&!c.generated));"

  SHOWS_TRUST_TABLE = [
    # [ trust, generated declared, claimable? ]
    [ "unverified",        false, false ],  # an untouched v0.1 concept: derived, never claimed
    [ "unverified",        true,  true  ],  # declared `generated` — its unverified is an answer
    [ "machine-confirmed", false, true  ],
    [ "machine-confirmed", true,  true  ],
    [ "human-reviewed",    false, true  ],
    [ "human-reviewed",    true,  true  ],
    [ "",                  true,  false ],  # nothing to claim
    [ nil,                 true,  false ]
  ].freeze

  test "the page's showsTrust and Concept.shows_trust? are one rule" do
    template = File.read(File.expand_path("../../../lib/okf/render/graph/template.html.erb", __dir__))

    assert_includes template, SHOWS_TRUST_JS,
      "the client-side twin moved; the Ruby rule and this literal must move together"

    SHOWS_TRUST_TABLE.each do |tier, generated, expected|
      assert_equal expected, OKF::Concept.shows_trust?(tier, generated),
        "Ruby disagrees with the page for trust=#{tier.inspect} generated=#{generated}"
      assert_equal expected, OKF::Bundle::RowFilter.shows_trust?(trust: tier, generated: generated),
        "the row form disagrees for trust=#{tier.inspect} generated=#{generated}"
    end
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
