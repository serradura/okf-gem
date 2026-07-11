# frozen_string_literal: true

require "test_helper"
require "okf"
require "stringio"

class OKF::CLITest < OKF::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("okf-cli-test")
    @out = StringIO.new
    @err = StringIO.new
  end

  teardown do
    FileUtils.rm_rf(@tmpdir)
  end

  test "validate returns 0 and reports conformance for a clean bundle" do
    write("a.md", concept)

    assert_equal 0, invoke("validate", @tmpdir)
    assert_match(/conformant/, @out.string)
  end

  test "validate returns 1 for a non-conformant bundle" do
    write("a.md", "# no frontmatter\n")

    assert_equal 1, invoke("validate", @tmpdir)
    assert_match(/non-conformant/, @out.string)
  end

  test "validate returns 1 for a §9.3 structural violation" do
    write("groups/index.md", "---\nokf_version: \"0.1\"\n---\n\n# G\n") # nested index with frontmatter
    write("a.md", concept)

    assert_equal 1, invoke("validate", @tmpdir)
    assert_match(/non-conformant/, @out.string)
  end

  test "validate --json emits a machine-readable report" do
    write("a.md", concept)

    assert_equal 0, invoke("validate", @tmpdir, "--json")
    report = JSON.parse(@out.string)
    assert_equal true, report["conformant"]
    assert_equal 1, report["counts"]["concepts"]
  end

  # server now starts a blocking server; its served behavior is covered by
  # server/app_test (rack-test). Here we only exercise the synchronous paths, which
  # return before booting.
  test "server rejects an unknown layout without starting a server (exit 2)" do
    write("a.md", concept)

    assert_equal 2, invoke("server", @tmpdir, "--layout", "bogus")
    assert_match(/invalid argument: --layout bogus/, @err.string)
  end

  test "server builds the server app and hands it to the runner (no socket)" do
    write("a.md", concept)
    captured = []
    cli = OKF::CLI.new(out: @out, err: @err, runner: ->(app, host, port) { captured << [ app, host, port ] })

    assert_equal 0, cli.run([ "server", @tmpdir, "--port", "9999", "--bind", "0.0.0.0", "-t", "T" ])
    app, host, port = captured.first
    assert_kind_of OKF::Server::App, app
    assert_equal "0.0.0.0", host
    assert_equal 9999, port
    assert_match(/serving 1 concepts/, @out.string)
  end

  test "graph --minimal emits lean nodes plus type and tag indexes" do
    write("a.md", "---\ntype: Note\ntitle: A\ntags: [x]\n---\n\n[B](b.md)\n")
    write("b.md", concept("B"))

    assert_equal 0, invoke("graph", @tmpdir, "--json", "--minimal")
    data = JSON.parse(@out.string)
    assert_equal %w[id title], data["nodes"].first.keys.sort
    assert data.key?("types")
    assert data.key?("tags")
  end

  test "graph tolerates a malformed concept, skips it, and notes the skip on stderr" do
    write("good.md", concept)
    write("bad.md", "no frontmatter here\n")

    assert_equal 0, invoke("graph", @tmpdir)
    assert_match(/1 concepts/, @out.string)
    assert_match(/skipped 1 file/, @err.string)
  end

  test "graph --json prints nodes and edges" do
    write("a.md", "---\ntype: Note\ntitle: A\ndescription: d\n---\n\n[B](b.md)\n")
    write("b.md", concept("B"))

    assert_equal 0, invoke("graph", @tmpdir, "--json")
    data = JSON.parse(@out.string)
    assert_equal 2, data["nodes"].size
    assert_equal 1, data["edges"].size
  end

  test "loose lists degree-0 files grouped by folder, omitting linked ones" do
    write("hub.md", "---\ntype: Note\ntitle: Hub\n---\n\n[leaf](leaf.md)\n")
    write("leaf.md", concept("Leaf"))
    write("notes/floater.md", concept("Floater")) # no links in or out

    assert_equal 0, invoke("loose", @tmpdir)
    assert_match(%r{Loose files .* \(1\)}, @out.string)
    assert_match(%r{notes/\n\s+floater\.md\s+Floater}, @out.string)
    refute_match(/hub\.md|leaf\.md/, @out.string)
  end

  test "loose --json emits id, title, and dir per file" do
    write("notes/floater.md", concept("Floater"))

    assert_equal 0, invoke("loose", @tmpdir, "--json")
    data = JSON.parse(@out.string)
    assert_equal 1, data["count"]
    assert_equal({ "id" => "notes/floater", "title" => "Floater", "dir" => "notes" }, data["loose"].first)
  end

  test "unknown command returns 2 with usage on stderr" do
    assert_equal 2, invoke("frobnicate")
    assert_match(/unknown command/, @err.string)
  end

  test "a missing directory returns 2" do
    assert_equal 2, invoke("validate", File.join(@tmpdir, "nope"))
    assert_match(/not a directory/, @err.string)
  end

  test "version prints the gem version" do
    assert_equal 0, invoke("--version")
    assert_match(/\A\d+\.\d+\.\d+/, @out.string.strip)
  end

  test "catalog prints concepts by area and --json emits metadata + link degree" do
    build_sample

    assert_equal 0, invoke("catalog", @tmpdir)
    assert_match(%r{Catalog — .*\(3 concepts\)}, @out.string)
    assert_match(%r{features/ \(2\)}, @out.string)

    @out = StringIO.new
    assert_equal 0, invoke("catalog", @tmpdir, "--json")
    data = JSON.parse(@out.string)
    assert_equal 3, data["count"]
    alpha = data["concepts"].find { |concept| concept["id"] == "features/a" }
    assert_equal "features", alpha["area"]
    assert_equal 1, alpha["links_out"]
    assert_equal 1, alpha["links_in"]
  end

  test "files lists filenames by folder and --json emits paths" do
    build_sample

    assert_equal 0, invoke("files", @tmpdir)
    assert_match(%r{Files — .*\(3 files\)}, @out.string)
    assert_match(/a\.md\s+Alpha/, @out.string)

    @out = StringIO.new
    assert_equal 0, invoke("files", @tmpdir, "--json")
    assert_includes JSON.parse(@out.string)["files"].map { |file| file["path"] }, "features/a.md"
  end

  test "tags lists tags by count and --json emits the index" do
    build_sample

    assert_equal 0, invoke("tags", @tmpdir)
    assert_match(%r{Tags — .*\(3 distinct\)}, @out.string)

    @out = StringIO.new
    assert_equal 0, invoke("tags", @tmpdir, "--json")
    top = JSON.parse(@out.string)["tags"].first
    assert_equal "okf", top["tag"]
    assert_equal 2, top["count"]
  end

  test "stats reports rollups and --json emits by_type / by_area" do
    build_sample

    assert_equal 0, invoke("stats", @tmpdir)
    assert_match(/concepts\s+3/, @out.string)
    assert_match(/cross-links\s+2/, @out.string)

    @out = StringIO.new
    assert_equal 0, invoke("stats", @tmpdir, "--json")
    data = JSON.parse(@out.string)
    assert_equal 2, data["areas"]
    assert_equal 2, data["cross_links"]
    assert_equal({ "Feature" => 2, "Mission" => 1 }, data["by_type"])
    assert_equal 2, data["by_area"]["features"]
  end

  private

  def invoke(*argv)
    OKF::CLI.start(argv, out: @out, err: @err)
  end

  def concept(title = "A")
    "---\ntype: Note\ntitle: #{title}\ndescription: d\n---\n\nhi\n"
  end

  # A tiny bundle for the catalog/files/tags/stats views: two areas, three
  # concepts, a two-edge chain (mission → a → b), and shared/unique tags.
  def build_sample
    write("product/mission.md", "---\ntype: Mission\ntitle: Mission\ntags: [m, okf]\n---\n\n[Alpha](/features/a.md)\n")
    write("features/a.md", "---\ntype: Feature\ntitle: Alpha\nstatus: shipped\ntags: [x, okf]\n---\n\n[Beta](/features/b.md)\n")
    write("features/b.md", "---\ntype: Feature\ntitle: Beta\ntags: [x]\n---\n\nleaf\n")
  end

  def write(path, content)
    target = File.join(@tmpdir, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
end
