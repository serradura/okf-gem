# frozen_string_literal: true

require "test_helper"
require "okf"

class OKF::Bundle::ReaderTest < OKF::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("okf-reader-test")
    write("tables/orders.md", <<~MD)
      ---
      type: BigQuery Table
      title: Orders
      ---

      # Orders
    MD
    write("references/vendor/api.md", <<~MD)
      ---
      type: API Reference
      ---

      # Vendor API
    MD
    write("index.md", "# Catalog\n")
    write("groups/log.md", "## 2026-06-26\n")
  end

  teardown do
    FileUtils.rm_rf(@tmpdir)
  end

  test "reads the bundle into an OKF::Bundle with an absolute root" do
    bundle = OKF::Bundle::Reader.read(@tmpdir)

    assert_kind_of OKF::Bundle, bundle
    assert_equal File.expand_path(@tmpdir), bundle.root
    assert_equal [ "groups/log.md", "index.md", "references/vendor/api.md", "tables/orders.md" ], bundle.paths
  end

  test "parses nested concept ids from the bundle, skipping reserved files" do
    ids = OKF::Bundle::Reader.read(@tmpdir).concepts.map(&:id)

    assert_equal [ "references/vendor/api", "tables/orders" ], ids
  end

  test "carries frontmatter and body on each concept" do
    concept = OKF::Bundle::Reader.read(@tmpdir).concepts.find { |c| c.id == "tables/orders" }

    assert_equal "tables/orders.md", concept.path
    assert_equal "BigQuery Table", concept.type
    assert_equal "Orders", concept.title
    assert_equal "# Orders\n", concept.body
  end

  test "exposes reserved files through the bundle" do
    bundle = OKF::Bundle::Reader.read(@tmpdir)

    assert_equal [ "index.md" ], bundle.index_files
    assert_equal [ "groups/log.md" ], bundle.log_files
  end

  test "hidden files and hidden directories are excluded, deliberately" do
    # The Unix hidden-file convention, not an accident of the glob: a bundle
    # often lives beside dot-dirs whose markdown is not knowledge — a skill
    # installed under .claude/, templates under .github/ — and reading a
    # project root must not pull those in as concepts. The exclusion is
    # documented in authoring.md; this pin is what keeps it a decision.
    write(".hidden.md", "---\ntype: Note\n---\n\n# Hidden\n")
    write(".hidden_dir/concept.md", "---\ntype: Note\n---\n\n# Nested\n")
    bundle = OKF::Bundle::Reader.read(@tmpdir)

    refute_includes bundle.paths, ".hidden.md"
    assert bundle.paths.none? { |path| path.start_with?(".hidden_dir/") }
    assert_equal [ "groups/log.md", "index.md", "references/vendor/api.md", "tables/orders.md" ], bundle.paths
  end

  test "an empty or missing directory reads as an empty bundle" do
    missing = OKF::Bundle::Reader.read(File.join(@tmpdir, "nope"))

    assert_empty missing.paths
    assert_empty missing.concepts
  end

  test "a concept file that fails to parse lands in unparseable, not raised or dropped" do
    write("broken.md", "no frontmatter here\n")
    bundle = OKF::Bundle::Reader.read(@tmpdir)

    assert_equal [ "references/vendor/api", "tables/orders" ], bundle.concepts.map(&:id)
    assert_equal [ "broken.md" ], bundle.unparseable.map(&:path)
    assert_equal "missing YAML frontmatter", bundle.unparseable.first.error
    assert_includes bundle.paths, "broken.md"
  end

  test "a concept file symlinked out of the root is quarantined, not followed" do
    outside_dir = Dir.mktmpdir("okf-outside")
    begin
      outside = File.join(outside_dir, "secret.md")
      File.write(outside, "---\ntype: Note\ntitle: Secret\n---\n\nSECRET BODY\n")
      File.symlink(outside, File.join(@tmpdir, "escape.md"))
      bundle = OKF::Bundle::Reader.read(@tmpdir)

      refute_includes bundle.concepts.map(&:id), "escape"
      entry = bundle.unparseable.find { |e| e.path == "escape.md" }
      assert entry, "an escaping symlink must be quarantined as unparseable"
      assert_match(/escapes bundle root/, entry.error)
      refute_includes bundle.unparseable.map { |e| e.content.to_s }.join, "SECRET BODY"
    ensure
      FileUtils.rm_rf(outside_dir)
    end
  end

  test "a reserved file symlinked out of the root is quarantined, not read" do
    outside_dir = Dir.mktmpdir("okf-outside")
    begin
      outside = File.join(outside_dir, "passwd")
      File.write(outside, "root:x:0:0:arbitrary outside file\n")
      File.delete(File.join(@tmpdir, "index.md"))
      File.symlink(outside, File.join(@tmpdir, "index.md"))
      bundle = OKF::Bundle::Reader.read(@tmpdir)

      assert_empty bundle.index_files, "an escaping index.md must not be served as reserved content"
      entry = bundle.unparseable.find { |e| e.path == "index.md" }
      assert entry, "an escaping reserved file must be quarantined as unparseable"
      refute_includes bundle.unparseable.map { |e| e.content.to_s }.join, "root:x:0:0"
    ensure
      FileUtils.rm_rf(outside_dir)
    end
  end

  test "a symlink pointing inside the same bundle is followed as normal" do
    write("real/orders.md", "---\ntype: Note\ntitle: Real\n---\n\nInside.\n")
    File.symlink(File.join(@tmpdir, "real", "orders.md"), File.join(@tmpdir, "alias.md"))
    bundle = OKF::Bundle::Reader.read(@tmpdir)

    assert_includes bundle.concepts.map(&:id), "alias"
    refute_includes bundle.unparseable.map(&:path), "alias.md"
  end

  test "a root unreadable at realpath time degrades to unparseable, not a crash" do
    root = File.expand_path(@tmpdir)
    original = File.method(:realpath)
    # The root becomes unresolvable after the glob; the read must still finish,
    # quarantining every file rather than raising the whole bundle down.
    stub = lambda do |path, *rest|
      raise Errno::ENOENT, path if path == root

      original.call(path, *rest)
    end
    File.stub(:realpath, stub) do
      bundle = nil
      assert_silent { bundle = OKF::Bundle::Reader.read(@tmpdir) }
      assert_empty bundle.concepts
      assert_equal bundle.paths.sort, bundle.unparseable.map(&:path).sort
    end
  end

  private

  def write(path, content)
    target = File.join(@tmpdir, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
end
