# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf search` end to end: ranked retrieval over the committed fixtures, plus the
# retrieval eval — the progressive-disclosure path (index skeleton → search →
# one body) must answer a question in a small fraction of the bytes the full
# graph dump costs. That ratio is the point of the verb; if it regresses, the
# skill's search playbook stops being true.
module ByDir
  # Bundles named by path — the plain form every verb accepts.
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

    test "search --pretty implies --json and indents it" do
      result = okf("search", fixture("conformant"), "orders", "--pretty")

      assert_equal 0, result.status
      assert_match(/\n\s+"matches"/, result.out, "--pretty indents without needing --json spelled out")
      assert_equal "tables/orders", JSON.parse(result.out)["matches"].first["id"]
    end

    test "search terms AND together across fields, and zero matches stays advisory" do
      # "sales" hits all three concepts, "customer_id" only one — ANDing must
      # narrow to the intersection, and the terms need not hit the same field.
      assert_equal 3, json(okf("search", fixture("conformant"), "sales", "--json"))["count"]
      narrowed = json(okf("search", fixture("conformant"), "sales", "customer_id", "--json"))
      assert_equal [ "tables/orders" ], narrowed["matches"].map { |row| row["id"] }

      none = okf("search", fixture("conformant"), "orders", "nothing-says-this")
      assert_equal 0, none.status, "an advisory read exits 0 even with nothing to show"
      assert_match(/no matches/, none.out)
    end

    test "search -e treats terms as regexps; an invalid pattern is a usage error" do
      hit = okf("search", fixture("conformant"), "-e", "ord[a-z]+s")
      assert_equal 0, hit.status
      assert_match(%r{tables/orders}, hit.out)

      bad = okf("search", fixture("conformant"), "-e", "[unclosed")
      assert_equal 2, bad.status
      assert_match(/invalid pattern: premature end of char-class/, bad.err)
      assert_empty bad.out, "a usage error leaves stdout clean"
    end

    test "the engine is chosen by what the query needs, not by a flag naming one" do
      # There is no --engine flag: -e requires regexp semantics, which only the
      # scan offers, and a plain search requires nothing, so the index answers.
      # Since the routing is silent, the score is what makes it observable — the
      # scan sums the matched fields' weights, the index ranks by BM25+.
      index = okf("search", fixture("conformant"), "orders", "--json")
      scan = okf("search", fixture("conformant"), "-e", "orders", "--json")

      assert_equal 0, index.status
      assert_equal 0, scan.status

      scanned = json(scan)["matches"].first
      assert_equal weight_sum(scanned["matched"]), scanned["score"], "-e routes to the scan"

      ranked = json(index)["matches"].first
      refute_equal weight_sum(ranked["matched"]), ranked["score"],
        "the default engine ranks by BM25+, which is not the field-weight sum"
    end

    test "routing says nothing at runtime: no note, no engine in the header, no new JSON key" do
      # A `note: using the scan engine` was considered and rejected — someone who
      # typed -e does not need to be told what -e does on every run. An absence
      # nobody pins is an absence that drifts back, so it is pinned here.
      index = okf("search", fixture("conformant"), "orders")
      scan = okf("search", fixture("conformant"), "-e", "orders")

      assert_empty scan.err, "choosing an engine is not a diagnostic"
      assert_empty index.err
      assert_equal index.out.lines.first, scan.out.lines.first,
        "the header names the bundle and the query — never the engine that answered"

      index_json = json(okf("search", fixture("conformant"), "orders", "--json"))
      scan_json = json(okf("search", fixture("conformant"), "-e", "orders", "--json"))
      assert_equal index_json.keys, scan_json.keys, "the envelope is one shape whichever engine answered"
      assert_equal index_json["matches"].first.keys, scan_json["matches"].first.keys,
        "and so is a match row — no engine field, no capability field"
    end

    test "search --in narrows the searched fields; an unknown field lists the real ones" do
      scoped = okf("search", fixture("conformant"), "orders", "--in", "title")
      assert_equal 0, scoped.status
      assert_match(/tables\/orders\s+Orders\s+·\s+BigQuery Table\s+·\s+title$/, scoped.out,
        "only the title hit is credited when the search is scoped to it")
      assert_match(/\(1 of 3 concepts\)/, scoped.out)

      bogus = okf("search", fixture("conformant"), "orders", "--in", "bogus")
      assert_equal 2, bogus.status
      assert_match(/unknown field\(s\): bogus \(searchable: title, id, tags, type, description, body\)/, bogus.err)
    end

    test "search matches whole tokens, not substrings — a mid-word fragment finds nothing" do
      # The index is tokenized, so a term is matched against whole words and their
      # prefixes. "custom" still reaches Customers; "ustomer" no longer does. This
      # is the one recall the engine swap deliberately gives up: an infix.
      prefixed = json(okf("search", fixture("conformant"), "custom", "--json"))
      assert_includes prefixed["matches"].map { |row| row["id"] }, "tables/customers",
        "a prefix of a real token still matches"

      infix = okf("search", fixture("conformant"), "ustomer", "--json")
      assert_equal 0, infix.status, "still an advisory read"
      assert_equal 0, json(infix)["count"], "a mid-token fragment is not a term"
    end

    test "search --fuzzy tolerates a typo; without it the same term finds nothing" do
      exact = okf("search", fixture("conformant"), "custommer", "--json")
      assert_equal 0, json(exact)["count"], "search is exact-by-default, so a typo misses"

      fuzzy = okf("search", fixture("conformant"), "custommer", "--fuzzy", "--json")
      assert_equal 0, fuzzy.status
      assert_includes json(fuzzy)["matches"].map { |row| row["id"] }, "tables/customers",
        "--fuzzy is the opt-in that forgives the typo"
    end

    test "search composes with the shared filters, which narrow the candidates first" do
      scoped = json(okf("search", fixture("conformant"), "orders", "--area", "tables", "--json"))
      assert_equal %w[tables/customers tables/orders], scoped["matches"].map { |row| row["id"] }.sort

      typed = json(okf("search", fixture("conformant"), "orders", "--type", "BigQuery Dataset", "--json"))
      assert_equal [ "datasets/sales" ], typed["matches"].map { |row| row["id"] }

      none = okf("search", fixture("conformant"), "orders", "--tag", "nothing-carries-this", "--json")
      assert_equal 0, none.status, "a filter matching nothing is still an advisory read"
      assert_equal 0, json(none)["count"]
    end

    test "search --fields projects the JSON; --except is its complement and they conflict" do
      lean = json(okf("search", fixture("conformant"), "orders", "--fields", "id,score"))
      assert_equal %w[id score], lean["matches"].first.keys.sort, "--fields implies --json and keeps only what was asked"

      trimmed = json(okf("search", fixture("conformant"), "orders", "--except", "snippet"))
      refute trimmed["matches"].first.key?("snippet")
      assert trimmed["matches"].first.key?("id")

      clash = okf("search", fixture("conformant"), "orders", "--fields", "id", "--except", "score")
      assert_equal 2, clash.status
      assert_match(/mutually exclusive/, clash.err)
    end

    # -- registry mode: the one verb that merges several bundles into one answer.

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

    test "--fields slug is a usage error: a path-named search has no slug to project" do
      # The declared shape is what the typo guard checks against, and it declared
      # slug for both search modes — but only registry mode labels its rows. So
      # the guard passed and the projection selected a key no row carried, giving
      # back one empty object per match under a count that says three.
      result = okf("search", fixture("conformant"), "orders", "--fields", "slug", "--json")

      assert_equal 2, result.status
      assert_match(/^error: unknown field\(s\): slug \(available: id, title, type, area, tags, matched, score, snippet\)$/, result.err)
      assert_empty result.out, "an unprojectable field is a refusal, never an answer shaped like one"
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
end
