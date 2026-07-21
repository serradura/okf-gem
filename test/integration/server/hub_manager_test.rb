# frozen_string_literal: true

require "test_helper"

require "rack/test"

require "okf"
require "okf/registry"
require "okf/server/hub"

# The hub's /b/ page — the browser counterpart of the TUI's bundles view. It was
# a bare list of links; it is now the bundles manager, which means every fact
# a person needs to choose between bundles has to be *on* it: how big each one
# is, which one `/` opens, whether it is healthy, and whether its folder is
# still there at all.
#
# The registry is what makes the last of those possible. A hub built from a
# registry knows about entries it could not host; one built from bare
# directories (`okf server ./a ./b`) has no registry to report on, and says so
# by offering nothing to manage.
class OKF::Server::HubManagerTest < OKF::TestCase
  include Rack::Test::Methods

  attr_reader :app

  setup do
    @root = Dir.mktmpdir("okf-hub-manager-test")
    @home = File.join(@root, "home")
    FileUtils.mkdir_p(@home)
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "each row carries the count, the mount link and the default marker" do
    registry_hub("orders" => :ok, "notes" => :ok)

    get "/b/"

    assert_equal 200, last_response.status
    assert_includes last_response.body, %(href="/b/orders/")
    assert_includes last_response.body, %(href="/b/notes/")
    assert_includes last_response.body, "@orders", "the slug is shown as the ref you can type"
    assert_match(/1 concept\b/, last_response.body)
    assert_match(/class="def"[^>]*>default</, last_response.body)
    refute_includes last_response.body, "http://", "the manager makes no external requests"
  end

  test "a conformant, well-curated bundle reads as ok" do
    registry_hub("orders" => :ok)

    get "/b/"

    assert_match(/data-health="ok"/, last_response.body)
    assert_includes last_response.body, "no problems"
  end

  test "a bundle with lint warnings reads as needing attention, not as broken" do
    # validate and lint stay separate (§9): curation findings are never
    # conformance errors, so a thin concept is a warning and the row stays open.
    registry_hub("thin" => :warn)

    get "/b/"

    assert_match(/data-health="warn"/, last_response.body)
    assert_match(/\d+ warnings?/, last_response.body)
    assert_includes last_response.body, %(href="/b/thin/"), "a warned bundle is still readable"
  end

  test "a non-conformant bundle reads as an error" do
    registry_hub("broken" => :error)

    get "/b/"

    assert_match(/data-health="error"/, last_response.body)
    assert_match(/\d+ errors?/, last_response.body)
  end

  test "colour is never the only channel — every verdict carries its word" do
    registry_hub("orders" => :ok, "thin" => :warn, "broken" => :error)

    get "/b/"

    %w[ok warn error].each do |verdict|
      assert_match(/data-health="#{verdict}"/, last_response.body)
    end
    assert_match(/<span class="hv-word">/, last_response.body, "the verdict is spelled out beside its colour")
  end

  test "a registered entry whose folder is gone is listed, muted, and explained" do
    registry_hub("orders" => :ok, "ghost" => :gone)

    get "/b/"

    assert_includes last_response.body, "ghost"
    assert_match(/data-health="missing"/, last_response.body)
    assert_includes last_response.body, "folder is gone"
    refute_includes last_response.body, %(href="/b/ghost/"), "a bundle the hub cannot host is not a link"
  end

  test "an ephemeral hub lists its bundles and offers nothing to manage" do
    # `okf server ./a ./b` has no registry, so there is no entry to rename,
    # remove or make default — the same thing the TUI says when it has no
    # registry to change.
    @app = OKF::Server::Hub.new([ hosted("orders", :ok) ])

    get "/b/"

    assert_equal 200, last_response.status
    assert_includes last_response.body, %(href="/b/orders/")
    assert_match(/data-health="ok"/, last_response.body)
    assert_includes last_response.body, "not registered"
  end

  test "the manager reflects the registry file as it is now, not as it booted" do
    registry_hub("orders" => :ok)

    OKF::Registry.load(home: @home).rename("orders", "sales")

    get "/b/"
    assert_includes last_response.body, "@sales", "the file is the source of truth; a refresh shows an edit"
  end

  test "under a mounted prefix every link stays inside it" do
    registry_hub("orders" => :ok)

    get "/b/", {}, "SCRIPT_NAME" => "/kb"

    assert_includes last_response.body, %(href="/kb/b/orders/")
    refute_includes last_response.body, %(href="/b/orders/")
  end

  private

  # A hub booted the way `okf server` boots one from the registry: every entry
  # whose directory is readable becomes a hosted bundle, the rest are known to
  # the registry and to nobody else.
  def registry_hub(shapes)
    registry = OKF::Registry.load(home: @home)
    bundles = shapes.map do |slug, shape|
      dir = make_bundle(slug, shape)
      registry.add(dir, as: slug)
      shape == :gone ? nil : OKF::Server::Hub::Bundle.new(slug, OKF::Bundle::Folder.load(dir), slug.capitalize)
    end
    shapes.each_key { |slug| FileUtils.rm_rf(File.join(@root, slug)) if shapes[slug] == :gone }
    @app = OKF::Server::Hub.new(bundles.compact, registry: OKF::Registry.load(home: @home))
  end

  def hosted(slug, shape)
    OKF::Server::Hub::Bundle.new(slug, OKF::Bundle::Folder.load(make_bundle(slug, shape)), slug.capitalize)
  end

  # The four shapes the manager has to tell apart. `:gone` is a real bundle at
  # registration time whose directory is deleted afterwards — the only way to
  # build a registry entry that points nowhere, and a branch no committed
  # fixture can reach.
  #
  # Every shape gets the same index.md listing its one concept, so the concept
  # is the only variable. Without it a lone concept is an orphan, and *every*
  # bundle here would lint as a warning — including the one whose whole job is
  # to be the healthy row.
  def make_bundle(slug, shape)
    dir = File.join(@root, slug)
    FileUtils.mkdir_p(dir)
    # The :warn shape's index points at a concept that is not there — a
    # curation finding, never a conformance error, which is exactly the side of
    # the validate/lint line this row has to land on.
    entries = shape == :warn ? "* [A](a.md)\n* [Gone](gone.md)\n" : "* [A](a.md)\n"
    File.write(File.join(dir, "index.md"), "---\nokf_version: \"0.1\"\n---\n\n# #{slug}\n\n#{entries}")
    File.write(File.join(dir, "a.md"), concept_for(shape))
    dir
  end

  def concept_for(shape)
    return "---\ntitle: No Type\n---\n\nA concept with no type is not conformant.\n" if shape == :error

    "---\ntype: Note\ntitle: A\ndescription: A well described concept.\n---\n\n" \
      "#{"A body long enough that the linter has nothing to say about it. " * 8}\n"
  end
end
