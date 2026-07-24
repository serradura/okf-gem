# frozen_string_literal: true

require "test_helper"
require "okf"

class OKF::Bundle::LinterTest < OKF::TestCase
  setup { @tmpdir = Dir.mktmpdir("okf-linter-test") }
  teardown { FileUtils.rm_rf(@tmpdir) }

  # ── Reachability ───────────────────────────────────────────────────────────

  test "orphan flags concepts with no inbound link and absent from every index" do
    write("hub.md", fm(title: "Hub") + "See [leaf](leaf.md).\n")
    write("leaf.md", fm(title: "Leaf") + "body\n")
    write("lonely.md", fm(title: "Lonely") + "body\n")

    # leaf is reachable (inbound from hub); hub and lonely are not.
    assert_equal %w[hub.md lonely.md], paths(:orphan)
  end

  test "orphan is silenced by an index.md listing" do
    write("index.md", "# Root\n\n* [A](a.md)\n")
    write("a.md", fm(title: "A") + "body\n")

    assert_empty checks(:orphan)
  end

  test "not_in_index flags a direct child of an indexed dir that the index omits" do
    write("index.md", "# Root\n\n* [Listed](listed.md)\n")
    write("listed.md", fm(title: "Listed") + "See [unlisted](unlisted.md).\n")
    write("unlisted.md", fm(title: "Unlisted") + "body\n")

    assert_equal %w[unlisted.md], paths(:not_in_index)
  end

  test "not_in_index ignores dirs without an index" do
    write("index.md", "# Root\n\n* [Sub](sub/)\n") # links the subdir, not a concept
    write("sub/a.md", fm(title: "A") + "body\n")   # sub/ has no index.md

    assert_empty checks(:not_in_index)
  end

  test "disconnected_component reports a multi-concept island, not singletons" do
    write("a.md", fm(title: "A") + "[b](b.md)\n")
    write("b.md", fm(title: "B") + "[a](a.md)\n")
    write("c.md", fm(title: "C") + "[d](d.md)\n")
    write("d.md", fm(title: "D") + "[c](c.md)\n")

    islands = checks(:disconnected_component)
    assert_equal 1, islands.size
    assert_equal 2, islands.first[:metric][:size]
  end

  test "unlinked flags a degree-0 concept even when an index lists it (unlike orphan)" do
    write("index.md", "# Root\n\n* [Loose](loose.md)\n")
    write("loose.md", fm(title: "Loose") + "no links, in or out\n")

    assert_empty checks(:orphan), "an index listing makes it reachable — not an orphan"
    assert_equal %w[loose.md], paths(:unlinked), "but listed ≠ linked — it still floats"
  end

  test "unlinked ignores a concept that has any cross-link, in or out" do
    write("a.md", fm(title: "A") + "[b](b.md)\n") # links out
    write("b.md", fm(title: "B") + "hi\n") # linked from a

    assert_empty checks(:unlinked)
  end

  # ── Backlog ─────────────────────────────────────────────────────────────────

  test "missing_concept is demand-ranked and counts raw references (no graph dedup)" do
    write("a.md", fm(title: "A") + "[z](/zebra.md) [z](/zebra.md) [a](/apple.md)\n")

    ranked = checks(:missing_concept)
    assert_equal %w[zebra.md apple.md], ranked.map { |f| f[:path] } # zebra (2) outranks apple (1)
    assert_equal 2, ranked.first[:metric][:references]
    assert_equal [ "a" ], ranked.first[:metric][:sources]
  end

  test "missing_concept ignores external links and links inside fences" do
    write("a.md", fm(title: "A") + "[ext](https://e.com/x.md)\n\n```\n[fenced](/ghost.md)\n```\n")

    assert_empty checks(:missing_concept)
  end

  test "broken_index_entry flags an index link to a missing concept" do
    write("index.md", "# Root\n\n* [Gone](gone.md)\n* [Here](here.md)\n")
    write("here.md", fm(title: "Here") + "body\n")

    entry = checks(:broken_index_entry).first
    assert_equal "index.md", entry[:path]
    assert_equal "gone.md", entry[:metric][:target]
  end

  # ── Completeness ────────────────────────────────────────────────────────────

  test "stub flags short bodies and honors min_body" do
    write("s.md", fm(title: "S") + "hi\n")
    write("big.md", fm(title: "Big") + ("x" * 100) + "\n")

    assert_equal %w[s.md], paths(:stub)
    assert_empty checks(:stub, min_body: 1)
  end

  test "missing_title, missing_description, and missing_timestamp fire per field" do
    write("notitle.md", fm(title: nil) + "a reasonably long body to avoid the stub check\n")
    write("nodesc.md", fm(title: "X", description: nil) + "a reasonably long body to avoid the stub check\n")

    assert_equal %w[notitle.md], paths(:missing_title)
    assert_equal %w[nodesc.md], paths(:missing_description)
    assert_equal %w[nodesc.md notitle.md], paths(:missing_timestamp) # neither has a timestamp
  end

  # ── Freshness ───────────────────────────────────────────────────────────────

  test "stale uses the injected cutoff and never raises on a bad timestamp" do
    write("old.md", fm(title: "Old", timestamp: "2000-01-01") + "a body long enough to skip stub\n")
    write("new.md", fm(title: "New", timestamp: "2030-01-01") + "a body long enough to skip stub\n")
    write("bad.md", fm(title: "Bad", timestamp: "whenever") + "a body long enough to skip stub\n")

    cutoff = Time.iso8601("2015-01-01T00:00:00Z")
    assert_equal %w[old.md], paths(:stale, stale_before: cutoff)
    assert_empty checks(:stale) # disabled without a cutoff
  end

  # ── Provenance ──────────────────────────────────────────────────────────────

  test "uncited_external flags external claims without a Citations section" do
    write("uncited.md", fm(title: "U") + "backed by [src](https://e.com/x) and nothing more\n")
    write("cited.md", fm(title: "C") + "backed by [src](https://e.com/x)\n\n# Citations\n\n[1] [src](https://e.com/x)\n")

    assert_equal %w[uncited.md], paths(:uncited_external)
  end

  test "broken_citation flags a bundle-relative citation to a missing page" do
    write("c.md", fm(title: "C") + "a claim\n\n# Citations\n\n[1] [ref](/nope.md)\n")

    assert_equal %w[c.md], paths(:broken_citation)
  end

  # ── Hygiene ─────────────────────────────────────────────────────────────────

  test "duplicate_title groups concepts sharing a normalized title" do
    write("a.md", fm(title: "Shared") + "a body long enough to skip stub\n")
    write("b.md", fm(title: "shared") + "a body long enough to skip stub\n") # case-insensitive
    write("c.md", fm(title: "Unique") + "a body long enough to skip stub\n")

    dup = checks(:duplicate_title)
    assert_equal 1, dup.size
    assert_equal %w[a b], dup.first[:metric][:concepts]
  end

  test "reference definitions: unused is info, undefined is warn, fenced uses ignored" do
    write("a.md", fm(title: "A") + "a body long enough to skip stub\n")
    write("b.md", fm(title: "B") + "a body long enough to skip stub\n")
    write("r.md", fm(title: "R") +
      "A [use][u] and a [dangle][ghost].\n\n```\n[fenced][unused]\n```\n\n[u]: /a.md\n[unused]: /b.md\n")

    assert_equal [ "unused" ], checks(:unused_reference_def).map { |f| f[:metric][:label] }
    assert_equal [ "ghost" ], checks(:undefined_reference).map { |f| f[:metric][:label] }
  end

  test "self_link flags a concept that links to itself" do
    write("me.md", fm(title: "Me") + "See [me](me.md) for more of the same, at length here.\n")

    assert_equal %w[me.md], paths(:self_link)
  end

  # ── Selection, health, stats, shape ─────────────────────────────────────────

  test "only and except select which checks run" do
    write("lonely.md", fm(title: "L") + "hi\n") # orphan + stub + missing_timestamp

    assert_equal [ :orphan ], report(only: [ :orphan ]).findings.map { |f| f[:check] }.uniq
    refute_includes report(except: [ :stub ]).findings.map { |f| f[:check] }, :stub
  end

  test "a well-curated bundle is healthy" do
    write("index.md", "# Root\n\n* [A](a.md)\n* [B](b.md)\n")
    write("a.md", fm(title: "A", timestamp: "2026-01-01") + ("links to [b](b.md) " * 5) + "\n")
    write("b.md", fm(title: "B", timestamp: "2026-01-01") + ("points to [a](a.md) " * 5) + "\n")

    assert report.healthy?, report.warnings.inspect
  end

  test "stats summarize the bundle" do
    write("index.md", "# Root\n\n* [A](a.md)\n")
    write("a.md", fm(title: "A") + "[b](b.md)\n")
    write("b.md", fm(title: "B", type: "Metric") + "body\n")

    stats = report.stats
    assert_equal 2, stats[:concepts]
    assert_equal 1, stats[:edges]
    assert_equal({ "Note" => 1, "Metric" => 1 }, stats[:types])
    assert_equal [ { id: "b", in_degree: 1 } ], stats[:hubs]
  end

  test "findings are well-formed and the report is JSON-able" do
    write("lonely.md", fm(title: "L") + "hi\n")
    result = report

    result.findings.each do |finding|
      assert_includes %i[warn info], finding[:severity]
      %i[check path message metric].each { |key| assert finding.key?(key), "finding missing #{key}" }
    end
    assert_nothing_raised { JSON.generate(result.to_h) }
  end

  private

  def report(**options)
    OKF::Bundle::Linter.call(OKF::Bundle::Reader.read(@tmpdir), **options)
  end

  def checks(name, **options)
    report(**options).findings.select { |finding| finding[:check] == name }
  end

  def paths(name, **options)
    checks(name, **options).map { |finding| finding[:path] }.sort
  end

  def fm(title: "T", type: "Note", description: "d", timestamp: nil)
    lines = [ "type: #{type}" ]
    lines << "title: #{title}" unless title.nil?
    lines << "description: #{description}" unless description.nil?
    lines << "timestamp: #{timestamp}" unless timestamp.nil?
    "---\n#{lines.join("\n")}\n---\n\n"
  end

  def write(path, content)
    target = File.join(@tmpdir, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
end
