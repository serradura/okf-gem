# frozen_string_literal: true

require "test_helper"
require "okf"

# OKF::Concept as a pure, in-memory value object — constructed straight from data
# (the Rails path) and interrogated without any disk access.
class OKF::ConceptTest < OKF::TestCase
  test "derives id from path and reads typed frontmatter accessors" do
    concept = OKF::Concept.new(
      path: "tables/orders.md",
      frontmatter: { type: "BigQuery Table", title: "Orders", description: "d", tags: [ "sales" ], timestamp: "2026-01-01" },
      body: "# Orders\n"
    )

    assert_equal "tables/orders", concept.id
    assert_equal "BigQuery Table", concept.type
    assert_equal "Orders", concept.title
    assert_equal "d", concept.description
    assert_equal [ "sales" ], concept.tags
    assert_equal "2026-01-01", concept.timestamp
  end

  test "prefers an explicit frontmatter id, falling back to the path when blank" do
    pinned = OKF::Concept.new(path: "tables/orders.md", frontmatter: { "id" => "orders", "type" => "Table" }, body: "x")
    blank = OKF::Concept.new(path: "tables/orders.md", frontmatter: { "id" => "  ", "type" => "Table" }, body: "x")

    assert_equal "orders", pinned.id
    assert_equal "tables/orders", blank.id
  end

  test "extracts cross-links and citations from the body" do
    concept = OKF::Concept.new(
      path: "a.md",
      frontmatter: { "type" => "Note" },
      body: "see [b](/b.md) and [site](https://ex.com)\n\n# Citations\n\n[1] [src](https://ex.com/paper)\n"
    )

    assert_equal [ "/b.md", "https://ex.com", "https://ex.com/paper" ], concept.links
    assert_equal [ "https://ex.com/paper" ], concept.citations
    assert_equal [ "https://ex.com", "https://ex.com/paper" ], concept.external_links
  end

  test "to_markdown round-trips through Frontmatter.parse" do
    concept = OKF::Concept.new(
      path: "a.md",
      frontmatter: { "type" => "Note", "title" => "A" },
      body: "# A\n\nbody\n"
    )

    frontmatter, body = OKF::Markdown::Frontmatter.parse(concept.to_markdown)
    assert_equal "Note", frontmatter["type"]
    assert_equal "A", frontmatter["title"]
    assert_equal "# A\n\nbody\n", body
  end

  test "lint runs the concept-scoped checks only — no orphan/backlog for a lone concept" do
    concept = OKF::Concept.new(path: "a.md", frontmatter: { "type" => "Note" }, body: "x")
    report = concept.lint

    checks = report.findings.map { |f| f[:check] }
    assert_includes checks, :missing_title
    assert_includes checks, :stub
    refute_includes checks, :orphan
    refute_includes checks, :missing_concept
  end

  test "reserved? recognizes index.md and log.md at any depth" do
    assert OKF::Concept.reserved?("index.md")
    assert OKF::Concept.reserved?("sub/log.md")
    refute OKF::Concept.reserved?("sub/note.md")
  end
end
