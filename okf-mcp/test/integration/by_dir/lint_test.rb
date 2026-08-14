# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  class LintTest < MCPIntegrationCase
    test "the curation report: stats, findings, and a visible total" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "lint", bundle: "knowledge")

      assert_equal "knowledge", data["bundle"]
      assert_equal 4, data.dig("stats", "concepts")
      assert_equal data["findings"].length, data["total"]
      unlinked = data["findings"].select { |row| row["check"] == "unlinked" }
      assert_equal [ "services/search.md" ], unlinked.map { |row| row["path"] }
    end

    test "only and except select by check id" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "lint", bundle: "knowledge", only: [ "unlinked" ])
      assert_equal [ "unlinked" ], data["findings"].map { |row| row["check"] }.uniq

      data = call_tool!(server, "lint", bundle: "knowledge", except: [ "unlinked" ])
      refute_includes data["findings"].map { |row| row["check"] }, "unlinked"
    end

    test "an unknown check id is a tool error naming the checks" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "lint", bundle: "knowledge", only: [ "rot" ])
      assert result.error?
      assert_match(/unknown check\(s\): rot/, result.text)
    end

    test "min_body flags stubs" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "lint", bundle: "knowledge", min_body: 10_000)
      stubs = data["findings"].select { |row| row["check"] == "stub" }
      assert_equal 4, stubs.length, "every body is shorter than 10k characters"
    end

    test "stale_after takes a duration or an ISO date" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "lint", bundle: "knowledge", stale_after: "1d", only: [ "stale" ])
      assert_equal 4, data["findings"].length, "every fixture timestamp is older than a day"

      data = call_tool!(server, "lint", bundle: "knowledge", stale_after: "2026-06-22", only: [ "stale" ])
      stale = data["findings"].map { |row| row["path"] }
      assert_includes stale, "services/search.md"
      refute_includes stale, "decisions/ledger.md", "timestamped after the cutoff"
    end

    test "an invalid stale_after is a tool error naming the accepted shapes" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "lint", bundle: "knowledge", stale_after: "soonish")
      assert result.error?
      assert_match(/invalid stale_after "soonish"/, result.text)
    end

    test "stale_after reads the same date grammar the CLI does" do
      # `okf lint --stale-after 20260101` exits 2; Date.iso8601 accepts the
      # basic and week forms, so this shell answered *about the same bundle*
      # with a cutoff its own CLI refuses to compute. One grammar, or the two
      # tools disagree about what is stale.
      server = mcp_server(fixture("knowledge"))

      %w[20260101 2026-W01-1].each do |spelling|
        result = call_tool(server, "lint", bundle: "knowledge", stale_after: spelling)

        assert result.error?, "stale_after #{spelling}: accepted here, refused by the CLI"
        assert_match(/invalid stale_after #{Regexp.escape(spelling.inspect)}/, result.text)
      end

      # The other half of one grammar: a cutoff is a moment, and the value an
      # agent has to hand is a concept's own `generated.at`. Refusing that is
      # the mirror-image drift — a hard tool error on the most natural input.
      moment = call_tool!(server, "lint", bundle: "knowledge", stale_after: "2026-06-22T00:00:00Z", only: [ "stale" ])
      day = call_tool!(server, "lint", bundle: "knowledge", stale_after: "2026-06-22", only: [ "stale" ])

      assert_equal day["findings"], moment["findings"], "the time of day is reduced away"
    end

    # The folder lens *is* the unlinked check, so the check-selection and
    # threshold options have nothing to act on. Silently ignoring them let a
    # caller read the full listing as though its filter had been applied.
    test "group folder refuses the options it cannot honour" do
      server = mcp_server(fixture("knowledge"))
      %i[only except min_body stale_after].each do |option|
        value = case option
                when :only, :except then [ "stale" ]
                when :min_body then 100
                else "90d"
                end
        result = call_tool(server, "lint", bundle: "knowledge", group: "folder", option => value)
        assert result.error?, "lint(group: \"folder\", #{option}: …) answered as if the option applied"
        assert_match(/folder/, result.text)
      end
    end

    test "group folder answers with the unlinked files by folder" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "lint", bundle: "knowledge", group: "folder")

      assert_equal "folder", data["group"]
      assert_equal 1, data["total"]
      assert_equal [ { "id" => "services/search", "title" => "Search", "dir" => "services" } ], data["files"]
    end
    test "the shell supplies the clock, so a declared expiry actually reports (§5.5)" do
      # The pure linter runs no clock check unless handed today: — the CLI
      # passes Date.today, and this shell is the layer that owns clock
      # resolution here. Without it, lint(only: ["expired"]) answered healthy
      # over a bundle full of passed expiries.
      server = mcp_server(fixture("expiring"))
      data = call_tool!(server, "lint", bundle: "expiring", only: [ "expired" ])

      assert_equal 1, data["total"]
      assert_equal "expired", data["findings"].first["check"]
      assert_equal "2000-01-01", data["findings"].first["metric"]["stale_after"]
      assert data["healthy"], "expired is info; it reports, it does not gate"
      assert_empty data["stats"]["skipped_checks"], "the clock arrived, so nothing was silently skipped"
    end
  end
end
