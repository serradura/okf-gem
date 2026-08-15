# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  class SearchTest < MCPIntegrationCase
    test "terms are ANDed and rows carry bundle, matched fields and a snippet" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "invoices" ], bundle: "knowledge")

      assert_equal [ "invoices" ], data["query"]
      assert_equal [ { "slug" => "knowledge", "dir" => fixture("knowledge") } ], data["bundles"]
      ids = data["results"].map { |row| row["id"] }
      assert_includes ids, "services/billing"
      assert_equal data["total"], data["results"].length

      billing = data["results"].find { |row| row["id"] == "services/billing" }
      assert_equal "knowledge", billing["bundle"]
      assert_equal "Billing", billing["title"]
      assert_includes billing["matched"], "body"
      refute_empty billing["snippet"]
      assert_equal weight_sum(billing["matched"]), billing["score"], "the scan answers by default"
    end

    test "two terms must both hit" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: %w[invoices backoff], bundle: "knowledge")
      assert_equal [ "services/billing" ], data["results"].map { |row| row["id"] }
    end

    test "type, tag and dir narrow the rows" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "billing" ], bundle: "knowledge", type: "Runbook")
      assert_equal [ "runbooks/billing-restart" ], data["results"].map { |row| row["id"] }

      data = call_tool!(server, "search", terms: [ "billing" ], bundle: "knowledge", tag: "core")
      assert_equal [ "services/billing" ], data["results"].map { |row| row["id"] }

      data = call_tool!(server, "search", terms: [ "billing" ], bundle: "knowledge", dir: "services")
      assert_equal [ "services/billing" ], data["results"].map { |row| row["id"] }
    end

    test "in narrows the searched fields" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "invoices" ], bundle: "knowledge", in: [ "description" ])
      assert_equal [ "services/billing" ], data["results"].map { |row| row["id"] }
    end

    test "limit cuts the rows while total stays honest" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "invoices" ], bundle: "knowledge", limit: 1)
      assert_equal 1, data["results"].length
      assert_operator data["total"], :>, 1
    end

    test "engine index ranks by BM25 and scores as floats" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "invoices" ], bundle: "knowledge", engine: "index")
      billing = data["results"].find { |row| row["id"] == "services/billing" }
      refute_equal weight_sum(billing["matched"]), billing["score"], "BM25, not the scan's weight sum"
    end

    test "fuzzy tolerates a typo and implies the index" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "invoixes" ], bundle: "knowledge", fuzzy: true)
      assert_includes data["results"].map { |row| row["id"] }, "services/billing"
    end

    test "regexp reads terms as patterns on the scan" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "invoi.es" ], bundle: "knowledge", regexp: true)
      assert_includes data["results"].map { |row| row["id"] }, "services/billing"
    end

    test "an invalid pattern is a tool error" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "search", terms: [ "(" ], bundle: "knowledge", regexp: true)
      assert result.error?
      assert_match(/invalid pattern/, result.text)
    end

    test "regexp plus fuzzy is refused naming the conflict" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "search", terms: [ "x" ], bundle: "knowledge", regexp: true, fuzzy: true)
      assert result.error?
      assert_match(/mutually exclusive/, result.text)
    end

    test "engine index plus regexp is refused naming the fix" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "search", terms: [ "x" ], bundle: "knowledge", engine: "index", regexp: true)
      assert result.error?
      assert_match(/cannot answer regexp/, result.text)
    end

    test "engine scan plus fuzzy is refused naming the fix" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "search", terms: [ "x" ], bundle: "knowledge", engine: "scan", fuzzy: true)
      assert result.error?
      assert_match(/cannot answer fuzzy/, result.text)
    end

    test "an unknown engine is refused by the schema, naming the two on offer" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "search", terms: [ "x" ], bundle: "knowledge", engine: "banana")
      assert result.error?
      assert_match(/`\/engine` is not one of: \["scan", "index"\]/, result.text)
    end

    test "an unknown field in `in` is a tool error naming the searchable ones" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "search", terms: [ "x" ], bundle: "knowledge", in: [ "bodies" ])
      assert result.error?
      assert_match(/unknown field\(s\): bodies/, result.text)
    end

    test "a foreign backend answers per bundle, merged by score" do
      server = mcp_server(fixture("knowledge"), engine: stub_engine)
      data = call_tool!(server, "search", terms: [ "anything" ])
      assert_equal %w[stub/one stub/two], data["results"].map { |row| row["id"] }
      assert_equal %w[knowledge knowledge], data["results"].map { |row| row["bundle"] }
    end

    test "a foreign backend is refused the kernel-facade knobs, never silently dropping them" do
      server = mcp_server(fixture("knowledge"), engine: stub_engine)
      result = call_tool(server, "search", terms: [ "x" ], fuzzy: true)
      assert result.error?
      assert_match(/the stub backend does not support engine, fuzzy, regexp or in/, result.text)
    end

    # Which engine ranked a result is not derivable from it. `fuzzy` switches
    # engines on its own and carries the index's tokenizer — and its recall
    # holes — with it, so a caller that asked for typo tolerance and got back
    # rows has no way to know a shattered identifier is why something is
    # missing. The one implicit tell, a float score against the scan's integer
    # count, does not hold: scores are rounded, and a round one reads as either.
    test "the payload names the engine that answered, on every route to it" do
      server = mcp_server(fixture("knowledge"))

      assert_equal "scan", call_tool!(server, "search", terms: [ "invoices" ])["engine"]
      assert_equal "scan", call_tool!(server, "search", terms: [ "invoi.es" ], regexp: true)["engine"]
      assert_equal "index", call_tool!(server, "search", terms: [ "invoices" ], engine: "index")["engine"]
      assert_equal "index", call_tool!(server, "search", terms: [ "invoixes" ], fuzzy: true)["engine"],
        "fuzzy implies the index, and the payload has to say so"
    end

    test "no matches is an empty result with total 0, not an error" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "zeppelin" ], bundle: "knowledge")
      assert_equal 0, data["total"]
      assert_empty data["results"]
    end

    # "no concept matched your terms" and "the directory you filtered by does
    # not exist" are different answers, and only the first one is above. Told
    # apart, because a filter naming nothing is a mistake the caller can fix
    # and an empty result set is not.
    test "a dir that names no directory is a tool error, not zero matches" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "search", terms: [ "billing" ], bundle: "knowledge", dir: "servicez")

      assert result.error?
      assert_match(/no directory "servicez" in bundle "knowledge"/, result.text)
    end

    # This guarded the near-miss while search was the one tool spelling the
    # argument `bundles`: a host that wrote `bundle:` had it ignored as an
    # unknown property and got every bundle back, silently. The asymmetry is
    # gone, so the hazard is now structural rather than guarded — but the
    # invariant underneath it is not about any one spelling. An argument this
    # tool does not know must *narrow nothing and widen nothing*: it must be
    # refused, whichever way the near-miss falls.
    test "an unknown identity argument is refused, never widened to every bundle" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))
      every = call_tool!(server, "search", terms: [ "invoices" ])["total"]

      result = call_tool(server, "search", bundles: "knowledge", terms: [ "invoices" ])
      assert result.error?, "a stray `bundles:` was accepted"
      assert_match(/bundles/, result.text)
      refute_equal every.to_s, result.text, "the near-miss answered as if no bundle had been named"
    end

    # An MCP client filling every declared optional property with an empty
    # default is routine; an empty filter must mean "no filter", as it does in
    # catalog, not "match nothing".
    test "empty-string filters are no filter, matching catalog" do
      server = mcp_server(fixture("knowledge"))
      unfiltered = call_tool!(server, "search", terms: [ "billing" ], bundle: "knowledge")["total"]

      assert_equal unfiltered, call_tool!(server, "search", terms: [ "billing" ], bundle: "knowledge", type: "")["total"]
      assert_equal unfiltered, call_tool!(server, "search", terms: [ "billing" ], bundle: "knowledge", tag: "")["total"]
      assert_equal unfiltered, call_tool!(server, "search", terms: [ "billing" ], bundle: "knowledge", dir: "")["total"]
    end

    test "a dir filter is case-insensitive, as catalog's is" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "billing" ], bundle: "knowledge", dir: "Services")
      assert_equal [ "services/billing" ], data["results"].map { |row| row["id"] }
    end

    test "the head surfaces unparseable files rather than answering as if whole" do
      server = mcp_server(fixture("scrappy"))
      data = call_tool!(server, "search", terms: [ "fine" ])
      assert_equal 1, data["bundles"].first["unparseable"]
    end

    private

    # The okf-sqlite3 seam without okf-sqlite3: an engine that answers the
    # Backend duck type with canned rows, so the foreign-backend branch stays
    # provable until that gem revives.
    def stub_engine
      Class.new do
        def refresh(_root); end

        def search(_root, _terms, _filters)
          [ { id: "stub/two", title: "Two", type: "Note", tags: [], matched: [ "body" ], score: 1.0, snippet: "" },
            { id: "stub/one", title: "One", type: "Note", tags: [], matched: [ "body" ], score: 2.0, snippet: "" } ]
        end

        def catalog(_root, _filters)
          []
        end

        def capabilities
          { name: "stub", ranked: true }
        end
      end.new
    end

    test "search narrows by status and trust, the way catalog and the CLI do" do
      # `catalog` gained both v0.2 filters and `okf search --status/--trust`
      # works, so an agent that learned the vocabulary from either one and
      # brought it here got nothing narrowed. One tool answering differently
      # from the next about one bundle is what RowFilter exists to prevent —
      # and filter_rows already calls it.
      server = mcp_server(fixture("knowledge"))

      wide = call_tool!(server, "search", terms: [ "service" ])
      assert_equal 4, wide["results"].length, "the unnarrowed term reaches every concept"

      reviewed = call_tool!(server, "search", terms: [ "service" ], trust: "human-reviewed")
      assert_equal [ "services/search" ], reviewed["results"].map { |row| row["id"] },
        "of the four, only the human-reviewed one survives"

      accepted = call_tool!(server, "search", terms: [ "billing" ], status: "accepted")
      assert_equal [ "decisions/ledger" ], accepted["results"].map { |row| row["id"] },
        "the effective status narrows the three `billing` matches to one"
    end

    test "fields projects each result row; except is its inverse; the pair refuses" do
      server = mcp_server(fixture("knowledge"))
      projected = call_tool!(server, "search", terms: %w[billing], fields: %w[id score])["results"].first

      assert_equal %w[id score], projected.keys.sort, "only the named keys survive"

      dropped = call_tool!(server, "search", terms: %w[billing], except: %w[snippet])["results"].first
      refute dropped.key?("snippet")
      assert dropped.key?("id")

      both = call_tool(server, "search", terms: %w[billing], fields: %w[id], except: %w[snippet])
      assert both.error?
      assert_match(/mutually exclusive/, both.text)
    end
  end
end
