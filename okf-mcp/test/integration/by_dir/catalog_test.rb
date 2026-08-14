# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  class CatalogTest < MCPIntegrationCase
    test "per-concept metadata with link degrees, sorted by id" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "catalog", bundle: "knowledge")

      assert_equal 4, data["total"]
      assert_equal %w[decisions/ledger runbooks/billing-restart services/billing services/search],
        data["concepts"].map { |row| row["id"] }

      billing = data["concepts"].find { |row| row["id"] == "services/billing" }
      assert_equal "Service", billing["type"]
      assert_equal %w[payments core], billing["tags"]
      assert_equal "active", billing["status"]
      assert_equal 2, billing["links_out"]
      assert_equal 2, billing["links_in"]
    end

    test "type, tag, dir and status narrow the rows" do
      server = mcp_server(fixture("knowledge"))

      data = call_tool!(server, "catalog", bundle: "knowledge", type: "Decision")
      assert_equal [ "decisions/ledger" ], data["concepts"].map { |row| row["id"] }
      assert_equal 1, data["total"]

      data = call_tool!(server, "catalog", bundle: "knowledge", tag: "oncall")
      assert_equal [ "runbooks/billing-restart" ], data["concepts"].map { |row| row["id"] }

      data = call_tool!(server, "catalog", bundle: "knowledge", dir: "services")
      assert_equal %w[services/billing services/search], data["concepts"].map { |row| row["id"] }

      data = call_tool!(server, "catalog", bundle: "knowledge", status: "accepted")
      assert_equal [ "decisions/ledger" ], data["concepts"].map { |row| row["id"] }
    end

    test "limit and offset slice while total stays the full count" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "catalog", bundle: "knowledge", limit: 2, offset: 1)
      assert_equal 4, data["total"]
      assert_equal %w[runbooks/billing-restart services/billing], data["concepts"].map { |row| row["id"] }

      beyond = call_tool!(server, "catalog", bundle: "knowledge", offset: 10)
      assert_equal 4, beyond["total"]
      assert_empty beyond["concepts"]
    end

    test "fields projects each row down to the named keys" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "catalog", bundle: "knowledge", fields: %w[id type])
      data["concepts"].each { |row| assert_equal %w[id type], row.keys }
    end

    # The bundle root has three spellings and they must all mean the same
    # thing — and the same thing the other tools mean by them.
    test "\"/\", \"\" and \".\" all name the bundle root" do
      server = mcp_server(fixture("notes"))
      direct = call_tool!(server, "catalog", bundle: "notes", dir: ".")["total"]
      assert_equal 2, direct

      assert_equal direct, call_tool!(server, "catalog", bundle: "notes", dir: "/")["total"]
      assert_equal direct, call_tool!(server, "catalog", bundle: "notes", dir: "")["total"]
    end

    # "root" is *not* a fourth spelling. The CLI accepts it because a shell
    # needs no quoting for it, which is the whole of its rationale there; a
    # JSON argument has no such problem, and no `dir` description here ever
    # advertised it. Folding it cost a bundle that has a real `root/`
    # directory the ability to name it — silently, answering for the bundle
    # root instead.
    test "a directory literally named root is addressable" do
      server = mcp_server(fixture("rooted"))

      inside = call_tool!(server, "catalog", bundle: "rooted", dir: "root")
      assert_equal 2, inside["total"]
      assert_equal %w[root/handbook root/policy], inside["concepts"].map { |row| row["id"] }

      at_root = call_tool!(server, "catalog", bundle: "rooted", dir: ".")
      assert_equal [ "charter" ], at_root["concepts"].map { |row| row["id"] }
    end

    # `dirs` has always refused a directory the bundle does not have; catalog
    # answered `total: 0` and exit 0 for the same value. An empty answer that
    # reads like a real one is the failure this project refuses everywhere else,
    # and it is worst here: `root` is the spelling the CLI and the skill both
    # teach, so an agent asks catalog for the bundle root, is told zero, and
    # reports that the bundle root is empty.
    test "a dir that names no directory is a tool error, as it is for dirs" do
      server = mcp_server(fixture("knowledge"))

      %w[runbookz root].each do |missing|
        result = call_tool(server, "catalog", bundle: "knowledge", dir: missing)
        assert result.error?, "catalog answered for a directory that does not exist: #{missing}"
        assert_match(/no directory #{Regexp.escape(missing.inspect)} in bundle "knowledge"/, result.text)
      end
    end

    # One source for "does this bundle have directory X?", on both sides of the
    # refusal: catalog's check and the dirs view must agree, or the refusal's
    # own advice — "orient with dirs" — points at a tool that contradicts it.
    # A scoped-log directory is real (zero concepts, honestly); an
    # unparseable-only one is still refused, but not with "no directory" — the
    # directory is standing right there on disk, and calling it nonexistent
    # sends the caller to re-spell a name that was correct. The refusal names
    # what actually happened: the reader skipped every file it holds.
    test "catalog and dirs agree about log-only and unparseable-only directories" do
      server = mcp_server(fixture("journaled"))

      archived = call_tool!(server, "catalog", bundle: "journaled", dir: "archive")
      assert_equal 0, archived["total"], "a real directory with no concepts is a real zero"

      result = call_tool(server, "catalog", bundle: "journaled", dir: "drafts")
      assert result.error?, "catalog answered for a directory dirs refuses to list"
      assert_match(/directory "drafts".*holds only files the reader could not parse/, result.text)
      assert_match(/validate/, result.text, "the fix is repairing the files, and the message must point there")
    end

    # The other half of the same rule: a directory that exists and holds no
    # concepts directly is a real zero, and must not be refused.
    test "a real directory with no concepts of its own answers zero, not an error" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "catalog", bundle: "knowledge", dir: ".")
      assert_equal 0, data["total"], "knowledge keeps every concept in a subdirectory"
    end

    test "surfaces unparseable files rather than answering as if whole" do
      server = mcp_server(fixture("scrappy"))
      data = call_tool!(server, "catalog", bundle: "scrappy")
      assert_equal 1, data["total"]
      assert_equal 1, data["unparseable"]
    end

    test "an unknown field is a tool error naming the row keys" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "catalog", bundle: "knowledge", fields: [ "body" ])
      assert result.error?
      assert_match(/unknown field\(s\): body/, result.text)
    end
    # ── the v0.2 columns and filters (okf targets v0.2 now) ─────────────────

    test "the row carries the v0.2 columns and the retired timestamp is a loud unknown" do
      server = mcp_server(fixture("knowledge"))

      data = call_tool!(server, "catalog", bundle: "knowledge", fields: %w[id trust generated_at generated])
      data["concepts"].each { |row| assert_equal %w[generated generated_at id trust], row.keys.sort }

      error = assert_raises(RuntimeError) { call_tool!(server, "catalog", bundle: "knowledge", fields: %w[timestamp]) }
      assert_match(/unknown field\(s\): timestamp/, error.message)
    end

    test "status narrows on the effective value — absent reads stable (§5.4)" do
      server = mcp_server(fixture("notes"))
      total = call_tool!(server, "catalog", bundle: "notes")["total"]

      assert_operator total, :>, 0
      assert_equal total, call_tool!(server, "catalog", bundle: "notes", status: "stable")["total"],
        "no note declares a status, and the CLI's --status stable matches them all — the MCP shell must agree"
    end

    test "trust narrows the rows, folding either tier spelling" do
      server = mcp_server(fixture("knowledge"))

      reviewed = call_tool!(server, "catalog", bundle: "knowledge", trust: "human-reviewed")
      assert_equal [ "services/search" ], reviewed["concepts"].map { |row| row["id"] }
      assert_equal reviewed["total"],
        call_tool!(server, "catalog", bundle: "knowledge", trust: "human_reviewed")["total"]

      assert_equal 3, call_tool!(server, "catalog", bundle: "knowledge", trust: "unverified")["total"]
    end
    test "CATALOG_FIELDS names exactly the keys a row actually carries" do
      # The vocabulary is a hand copy of okf's row shape across a gem seam —
      # the next key added to Bundle#catalog would ship visible in unprojected
      # rows yet refused by `fields:` as unknown, with neither suite red.
      server = mcp_server(fixture("knowledge"))
      row = call_tool!(server, "catalog", bundle: "knowledge")["concepts"].first

      assert_equal OKF::MCP::Server::CATALOG_FIELDS.sort, row.keys.map(&:to_s).sort
    end

    test "except drops the named keys — the inverse projection fields already had" do
      server = mcp_server(fixture("knowledge"))
      row = call_tool!(server, "catalog", bundle: "knowledge", except: %w[description tags])["concepts"].first

      refute row.key?("description")
      refute row.key?("tags")
      assert row.key?("id")
    end

    test "fields and except are mutually exclusive, and except checks the vocabulary too" do
      server = mcp_server(fixture("knowledge"))
      both = call_tool(server, "catalog", bundle: "knowledge", fields: %w[id], except: %w[tags])
      typo = call_tool(server, "catalog", bundle: "knowledge", except: %w[timestamp])

      assert both.error?
      assert_match(/mutually exclusive/, both.text)
      assert typo.error?
      assert_match(/unknown field/, typo.text)
    end
  end
end
