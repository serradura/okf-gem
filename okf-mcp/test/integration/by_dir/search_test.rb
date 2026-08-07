# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  class SearchTest < MCPIntegrationCase
    test "terms are ANDed and rows carry bundle, matched fields and a snippet" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "invoices" ], bundles: "knowledge")

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
      data = call_tool!(server, "search", terms: %w[invoices backoff], bundles: "knowledge")
      assert_equal [ "services/billing" ], data["results"].map { |row| row["id"] }
    end

    test "type, tag and dir narrow the rows" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "billing" ], bundles: "knowledge", type: "Runbook")
      assert_equal [ "runbooks/billing-restart" ], data["results"].map { |row| row["id"] }

      data = call_tool!(server, "search", terms: [ "billing" ], bundles: "knowledge", tag: "core")
      assert_equal [ "services/billing" ], data["results"].map { |row| row["id"] }

      data = call_tool!(server, "search", terms: [ "billing" ], bundles: "knowledge", dir: "services")
      assert_equal [ "services/billing" ], data["results"].map { |row| row["id"] }
    end

    test "in narrows the searched fields" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "invoices" ], bundles: "knowledge", in: [ "description" ])
      assert_equal [ "services/billing" ], data["results"].map { |row| row["id"] }
    end

    test "limit cuts the rows while total stays honest" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "invoices" ], bundles: "knowledge", limit: 1)
      assert_equal 1, data["results"].length
      assert_operator data["total"], :>, 1
    end

    test "engine index ranks by BM25 and scores as floats" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "invoices" ], bundles: "knowledge", engine: "index")
      billing = data["results"].find { |row| row["id"] == "services/billing" }
      refute_equal weight_sum(billing["matched"]), billing["score"], "BM25, not the scan's weight sum"
    end

    test "fuzzy tolerates a typo and implies the index" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "invoixes" ], bundles: "knowledge", fuzzy: true)
      assert_includes data["results"].map { |row| row["id"] }, "services/billing"
    end

    test "regexp reads terms as patterns on the scan" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "invoi.es" ], bundles: "knowledge", regexp: true)
      assert_includes data["results"].map { |row| row["id"] }, "services/billing"
    end

    test "an invalid pattern is a tool error" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "search", terms: [ "(" ], bundles: "knowledge", regexp: true)
      assert result.error?
      assert_match(/invalid pattern/, result.text)
    end

    test "regexp plus fuzzy is refused naming the conflict" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "search", terms: [ "x" ], bundles: "knowledge", regexp: true, fuzzy: true)
      assert result.error?
      assert_match(/mutually exclusive/, result.text)
    end

    test "engine index plus regexp is refused naming the fix" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "search", terms: [ "x" ], bundles: "knowledge", engine: "index", regexp: true)
      assert result.error?
      assert_match(/cannot answer regexp/, result.text)
    end

    test "engine scan plus fuzzy is refused naming the fix" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "search", terms: [ "x" ], bundles: "knowledge", engine: "scan", fuzzy: true)
      assert result.error?
      assert_match(/cannot answer fuzzy/, result.text)
    end

    test "an unknown engine is refused by the schema, naming the two on offer" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "search", terms: [ "x" ], bundles: "knowledge", engine: "banana")
      assert result.error?
      assert_match(/`\/engine` is not one of: \["scan", "index"\]/, result.text)
    end

    test "an unknown field in `in` is a tool error naming the searchable ones" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "search", terms: [ "x" ], bundles: "knowledge", in: [ "bodies" ])
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

    test "no matches is an empty result with total 0, not an error" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "zeppelin" ], bundles: "knowledge")
      assert_equal 0, data["total"]
      assert_empty data["results"]
    end

    # Nine of the ten tools take `bundle`; only this one takes `bundles`. The
    # near-miss must not widen the answer to every bundle in silence.
    test "a stray singular bundle: is refused, never widened to every bundle" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))
      result = call_tool(server, "search", bundle: "knowledge", terms: [ "invoices" ])
      assert result.error?
      assert_match(/bundle/, result.text)
    end

    # An MCP client filling every declared optional property with an empty
    # default is routine; an empty filter must mean "no filter", as it does in
    # catalog, not "match nothing".
    test "empty-string filters are no filter, matching catalog" do
      server = mcp_server(fixture("knowledge"))
      unfiltered = call_tool!(server, "search", terms: [ "billing" ], bundles: "knowledge")["total"]

      assert_equal unfiltered, call_tool!(server, "search", terms: [ "billing" ], bundles: "knowledge", type: "")["total"]
      assert_equal unfiltered, call_tool!(server, "search", terms: [ "billing" ], bundles: "knowledge", tag: "")["total"]
      assert_equal unfiltered, call_tool!(server, "search", terms: [ "billing" ], bundles: "knowledge", dir: "")["total"]
    end

    test "a dir filter is case-insensitive, as catalog's is" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "search", terms: [ "billing" ], bundles: "knowledge", dir: "Services")
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
  end
end
