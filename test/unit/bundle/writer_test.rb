# frozen_string_literal: true

require "test_helper"
require "okf"

class OKF::Bundle::WriterTest < OKF::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("okf-materializer-test")
  end

  teardown do
    FileUtils.rm_rf(@tmpdir)
  end

  test "writes nested concept paths and produces a valid bundle" do
    bundle_path = File.join(@tmpdir, "knowledge", "sales")

    OKF::Bundle::Writer.call(
      bundle_path: bundle_path,
      concepts: [
        concept(path: "tables/orders.md", type: "BigQuery Table", title: "Orders"),
        concept(path: "references/vendor/contracts/api.md", type: "API Reference", title: "Vendor API")
      ],
      index_files: { "index.md" => "# Sales Catalog\n" },
      log_files: { "log.md" => "## 2026-06-26\n\nInitial publish.\n" }
    )

    assert_path_exists File.join(bundle_path, "tables/orders.md")
    assert_path_exists File.join(bundle_path, "references/vendor/contracts/api.md")
    assert OKF::Bundle::Folder.load(bundle_path).validate.valid?
  end

  test "writes YAML frontmatter and markdown body" do
    bundle_path = File.join(@tmpdir, "bundle")

    OKF::Bundle::Writer.call(
      bundle_path: bundle_path,
      concepts: [ concept(path: "tables/orders.md", type: "BigQuery Table", title: "Orders", body: "# Orders\n") ]
    )

    content = File.read(File.join(bundle_path, "tables/orders.md"))
    assert_match(/\A---\n/, content)
    assert_match(/type: BigQuery Table/, content)
    assert_match(/title: Orders/, content)
    assert_match(/# Orders\n\z/, content)
  end

  test "accepts OKF::Concept objects, not just hashes" do
    bundle_path = File.join(@tmpdir, "bundle")

    OKF::Bundle::Writer.call(
      bundle_path: bundle_path,
      concepts: [
        OKF::Concept.new(
          path: "tables/orders.md",
          frontmatter: { "type" => "BigQuery Table", "title" => "Orders" },
          body: "# Orders\n"
        )
      ]
    )

    reloaded = OKF::Bundle::Folder.load(bundle_path)
    assert reloaded.validate.valid?
    assert_equal "BigQuery Table", reloaded.concepts.first.type
  end

  test "refuses unsafe paths" do
    bundle_path = File.join(@tmpdir, "bundle")

    assert_raises(OKF::Path::Error) do
      OKF::Bundle::Writer.call(bundle_path: bundle_path, concepts: [ concept(path: "../orders.md") ])
    end
  end

  test "fails on existing non-empty target by default" do
    bundle_path = File.join(@tmpdir, "bundle")
    FileUtils.mkdir_p(bundle_path)
    File.write(File.join(bundle_path, "existing.md"), "already here")

    assert_raises(OKF::Bundle::Writer::AlreadyExistsError) do
      OKF::Bundle::Writer.call(bundle_path: bundle_path, concepts: [ concept(path: "tables/orders.md") ])
    end

    assert_equal "already here", File.read(File.join(bundle_path, "existing.md"))
  end

  test "overwrite replaces existing bundle after validating replacement" do
    bundle_path = File.join(@tmpdir, "bundle")
    OKF::Bundle::Writer.call(bundle_path: bundle_path, concepts: [ concept(path: "old.md", title: "Old") ])

    OKF::Bundle::Writer.call(
      bundle_path: bundle_path,
      concepts: [ concept(path: "new.md", title: "New") ],
      overwrite: true
    )

    refute_path_exists File.join(bundle_path, "old.md")
    assert_path_exists File.join(bundle_path, "new.md")
    assert OKF::Bundle::Folder.load(bundle_path).validate.valid?
  end

  test "concurrently materializes different bundle paths" do
    paths = 4.times.map { |i| File.join(@tmpdir, "bundle-#{i}") }

    threads = paths.each_with_index.map do |path, index|
      Thread.new do
        OKF::Bundle::Writer.call(
          bundle_path: path,
          concepts: [ concept(path: "records/#{index}.md", title: "Record #{index}") ]
        )
      end
    end
    threads.each(&:join)

    paths.each_with_index do |path, index|
      assert_path_exists File.join(path, "records/#{index}.md")
      assert OKF::Bundle::Folder.load(path).validate.valid?
    end
  end

  test "concurrently materializes same bundle path without partial output" do
    bundle_path = File.join(@tmpdir, "bundle")
    successes = Queue.new
    failures = Queue.new

    threads = 2.times.map do |index|
      Thread.new do
        begin
          OKF::Bundle::Writer.call(
            bundle_path: bundle_path,
            concepts: [ concept(path: "records/#{index}.md", title: "Record #{index}") ]
          )
          successes << index
        rescue OKF::Bundle::Writer::AlreadyExistsError
          failures << index
        end
      end
    end
    threads.each(&:join)

    assert_equal 1, successes.size
    assert_equal 1, failures.size
    assert OKF::Bundle::Folder.load(bundle_path).validate.valid?
    assert_equal 1, Dir.glob(File.join(bundle_path, "records/*.md")).size
  end

  private

  def concept(path:, type: "Guide", title: "Example", body: "Body\n")
    {
      path: path,
      frontmatter: {
        "type" => type,
        "title" => title,
        "description" => "Description"
      },
      body: body
    }
  end
end
