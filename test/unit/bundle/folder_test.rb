# frozen_string_literal: true

require "test_helper"
require "okf"

# OKF::Bundle::Folder — the on-disk bundle handle: load a directory, run the
# analyzers over the pure bundle, materialize an
# in-memory bundle back to disk, and reach a single concept file.
class OKF::Bundle::FolderTest < OKF::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("okf-folder-test")
    write("features/a.md", "---\ntype: Feature\ntitle: Alpha\ndescription: d\n---\n\n[Beta](b.md)\n")
    write("features/b.md", "---\ntype: Feature\ntitle: Beta\ndescription: d\n---\n\nhi\n")
    write("index.md", "---\nokf_version: \"0.1\"\n---\n\n# Root\n")
  end

  teardown do
    FileUtils.rm_rf(@tmpdir)
  end

  test "loads concepts, skipping reserved files" do
    assert_equal [ "features/a", "features/b" ], OKF::Bundle::Folder.load(@tmpdir).concepts.map(&:id).sort
  end

  test "exposes the pure bundle it read from disk" do
    assert_kind_of OKF::Bundle, OKF::Bundle::Folder.load(@tmpdir).bundle
  end

  test "validate delegates to the Validator — a clean bundle is conformant" do
    assert OKF::Bundle::Folder.load(@tmpdir).validate.valid?
  end

  test "validate reports §9.3 structural issues as errors" do
    write("groups/index.md", "---\nokf_version: \"0.1\"\n---\n\n# G\n")

    refute OKF::Bundle::Folder.load(@tmpdir).validate.valid?
  end

  test "lint delegates to the Linter" do
    assert_kind_of OKF::Bundle::Linter::Report, OKF::Bundle::Folder.load(@tmpdir).lint
  end

  test "graph returns the knowledge graph" do
    graph = OKF::Bundle::Folder.load(@tmpdir).graph

    assert_kind_of OKF::Bundle::Graph, graph
    assert_equal [ { source: "features/a", target: "features/b" } ], graph.edges
  end

  test "graph forwards fidelity options (minimal nodes)" do
    graph = OKF::Bundle::Folder.load(@tmpdir).graph(minimal: true)

    assert_equal %i[id title], graph.nodes.first.keys.sort
  end

  test "concept(id) returns a single-file handle for that concept" do
    file = OKF::Bundle::Folder.load(@tmpdir).concept("features/a")

    assert_kind_of OKF::Concept::File, file
    assert_equal "Alpha", file.concept.title
  end

  test "concept(id) returns nil for an unknown id" do
    assert_nil OKF::Bundle::Folder.load(@tmpdir).concept("nope")
  end

  test "name is the parent/dir pair used as the default title" do
    expected = "#{File.basename(File.dirname(@tmpdir))}/#{File.basename(@tmpdir)}"

    assert_equal expected, OKF::Bundle::Folder.load(@tmpdir).name
  end

  test "reload re-reads the directory from disk" do
    folder = OKF::Bundle::Folder.load(@tmpdir)
    assert_equal 2, folder.concepts.size

    write("features/c.md", "---\ntype: Feature\ntitle: Gamma\n---\n\nhi\n")
    assert_equal 2, folder.concepts.size # still the old snapshot
    assert_equal 3, folder.reload.concepts.size
  end

  test "materializes an in-memory bundle to disk, validating first" do
    bundle = OKF::Bundle.new(
      concepts: [ OKF::Concept.new(path: "notes/x.md", frontmatter: { "type" => "Note", "title" => "X" }, body: "# X\n") ],
      reserved: [ OKF::Bundle::Entry.new(path: "index.md", content: "# Catalog\n") ]
    )
    out = File.join(@tmpdir, "exported")

    OKF::Bundle::Folder.new(bundle: bundle, root: out).save

    assert_path_exists File.join(out, "notes/x.md")
    reloaded = OKF::Bundle::Folder.load(out)
    assert reloaded.validate.valid?
    assert_equal [ "notes/x" ], reloaded.concepts.map(&:id)
    assert_equal [ "index.md" ], reloaded.bundle.index_files
  end

  private

  def write(path, content)
    target = File.join(@tmpdir, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
end
