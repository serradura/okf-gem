# frozen_string_literal: true

require_relative "cli_integration_case"

# `okf search` end to end: ranked retrieval over the committed fixtures, plus the
# retrieval eval — the progressive-disclosure path (index skeleton → search →
# one body) must answer a question in a small fraction of the bytes the full
# graph dump costs. That ratio is the point of the verb; if it regresses, the
# skill's search playbook stops being true.
class CLISearchTest < CLIIntegrationCase
  test "search ranks a title hit above body mentions and shows where each hit" do
    result = okf("search", fixture("conformant"), "orders")

    assert_equal 0, result.status
    ids = result.out.scan(%r{^\s{2}(\S+)\s{2}}).flatten
    assert_equal "tables/orders", ids.first, "the concept named Orders outranks concepts that mention it"
    assert_match(/tables\/orders\s+Orders\s+·\s+BigQuery Table\s+·\s+title\+id\+tags/, result.out)
    assert_match(/…/, result.out, "body hits carry a bounded context snippet")
  end

  test "search --json is the machine substrate: query, count, ranked matches" do
    result = okf("search", fixture("conformant"), "orders", "--json")

    assert_equal 0, result.status
    data = JSON.parse(result.out)
    assert_equal [ "orders" ], data["query"]
    assert_equal "tables/orders", data["matches"].first["id"]
    assert_operator data["matches"].first["score"], :>, data["matches"].last["score"]
  end

  test "search covers every field the browser page's search reads, plus body" do
    # The server page's catalog haystack is title+description+type+tags+id; the
    # CLI must never search less than the browser (parity), and adds body.
    assert_equal %w[title id tags type description body], OKF::Bundle::Search::FIELDS
  end

  test "retrieval eval: the progressive path answers in a fraction of the dump" do
    bundle_dir = build_wide_bundle(concepts: 30)

    # The question: which concept covers the invoice dedup key?
    orient = okf("index", bundle_dir, "--no-body")
    hits = okf("search", bundle_dir, "dedup", "key", "--json")
    data = JSON.parse(hits.out)
    assert_equal "billing/dedup-key", data["matches"].first["id"], "search finds the answer"

    body = File.read(File.join(bundle_dir, "#{data["matches"].first["id"]}.md"))
    assert_match(/account_id, external_id/, body, "reading only the winning file answers the question")

    progressive = orient.out.bytesize + hits.out.bytesize + body.bytesize
    dump = okf("graph", bundle_dir, "--json").out.bytesize
    assert_operator progressive, :<, dump / 4,
      "index skeleton + search + one body must cost <25% of the full graph dump (got #{progressive} vs #{dump})"
  end

  private

  # A synthetic bundle wide enough for the byte comparison to mean something:
  # `concepts` areas × files with real prose bodies, one of them the needle.
  def build_wide_bundle(concepts:)
    dir = File.join(@out_dir, "wide")
    filler = "This concept describes an ordinary part of the system in unremarkable prose. " * 8
    (1..concepts).each do |i|
      path = File.join(dir, "area#{i % 5}", "concept-#{i}.md")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "---\ntype: Note\ntitle: Concept #{i}\ndescription: Routine notes.\n---\n\n#{filler}\n")
    end
    needle = File.join(dir, "billing", "dedup-key.md")
    FileUtils.mkdir_p(File.dirname(needle))
    File.write(needle, <<~MD)
      ---
      type: Decision
      title: Invoice dedup key
      description: Why retries never double-charge.
      tags: [billing, idempotency]
      ---

      We chose the (account_id, external_id) pair as the dedup key, so a retried
      invoice upserts instead of double-charging.
    MD
    dir
  end
end
