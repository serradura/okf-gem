# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  class LogTest < MCPIntegrationCase
    test "every log.md, root scope first, content live from disk" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "log", bundle: "knowledge")

      assert_equal 3, data["total"], "entries, not files: two in the root log and one in runbooks/"
      assert_equal 2, data["files"]
      assert_equal %w[log.md runbooks/log.md], data["logs"].map { |row| row["path"] }
      assert_equal %w[. runbooks], data["logs"].map { |row| row["dir"] }
      assert_match(/ledger decision/, data["logs"].first["content"])
    end

    # The bound the other nine tools already had. A log is the file that grows
    # without limit and never gets curated, so it is the one read view whose
    # cost is unrelated to the question asked: this repo's own log.md answers
    # "what changed recently" with 119,863 bytes, most of it last quarter.
    # `total` counting *files* made that look bounded when nothing was.
    test "the newest entries only: total counts entries, and the oldest are cut" do
      server = mcp_server(fixture("chronicled"))
      data = call_tool!(server, "log", bundle: "chronicled")

      assert_equal 8, data["total"], "total counts date-grouped entries across every log file"
      assert_equal 2, data["files"], "the file count keeps its own key"

      root = data["logs"].first
      assert_equal 6, root["total"], "the entries this file holds"
      assert_equal 3, root["returned"], "the entries it handed over"
      assert_match(/Sixth entry/, root["content"])
      assert_match(/Fourth entry/, root["content"])
      refute_match(/Third entry/, root["content"], "the fourth-newest entry is past the default bound")
      refute_match(/First entry/, root["content"])
      assert_match(/\A# Update Log/, root["content"], "the file's own heading survives the cut")
    end

    test "a log shorter than the bound is returned whole, and says so" do
      server = mcp_server(fixture("chronicled"))
      ops = call_tool!(server, "log", bundle: "chronicled")["logs"].last

      assert_equal "ops/log.md", ops["path"]
      assert_equal 2, ops["total"]
      assert_equal 2, ops["returned"]
      assert_match(/Created the ops scope/, ops["content"], "nothing is cut when nothing exceeds the bound")
    end

    test "limit raises the bound, and the cut is visible either way" do
      server = mcp_server(fixture("chronicled"))
      whole = call_tool!(server, "log", bundle: "chronicled", limit: 6)["logs"].first

      assert_equal 6, whole["returned"]
      assert_match(/First entry/, whole["content"])

      one = call_tool!(server, "log", bundle: "chronicled", limit: 1)["logs"].first
      assert_equal 1, one["returned"]
      assert_equal 6, one["total"], "total is the count before the cut"
      refute_match(/Fifth entry/, one["content"])
    end

    # A log the split cannot divide is not an empty log. It came back whole
    # under `total: 0, returned: 0`, so the one unbounded read on this surface
    # survived the fix that was meant to close it — and reported itself as
    # holding nothing, which is the same false comfort as a `total` that
    # counted files. One indivisible entry is what it is, so that is what it
    # counts as.
    test "a log with no `## ` headings counts as the one entry it is" do
      dir = File.join(@out_dir, "undated")
      FileUtils.cp_r(fixture("knowledge"), dir)
      File.write(File.join(dir, "log.md"), "# Update Log\n\nProse, no date headings at all.\n")
      server = mcp_server(dir)
      root = call_tool!(server, "log", bundle: "undated")["logs"].first

      assert_equal 1, root["total"]
      assert_equal 1, root["returned"]
      refute root["truncated"], "it is well under the bound"
      assert_match(/Prose, no date headings/, root["content"], "an unstructured log is still readable")
    end

    # A conformant §7 log: "a flat list of date-grouped entries" fixes no
    # heading level, so `###` is legal and the splitter still cannot use it.
    test "a committed log grouped under `###` is bounded, not emptied" do
      server = mcp_server(fixture("unstructured"))
      data = call_tool!(server, "log", bundle: "unstructured")

      assert_equal 1, data["total"]
      root = data["logs"].first
      assert_equal 1, root["total"]
      assert_match(/2026-07-29/, root["content"])
    end

    # The half a byte-free bound cannot give: an indivisible log that is *big*.
    # The format offers no boundary to cut on here, so the cut is by size and
    # `truncated` announces it — a bound the reader cannot see is not a bound.
    test "an oversized unstructured log is cut, says so, and `limit` raises the cap" do
      dir = File.join(@out_dir, "sprawling")
      FileUtils.cp_r(fixture("knowledge"), dir)
      body = "Undated prose that never stops. " * 1_000
      File.write(File.join(dir, "log.md"), "# Update Log\n\n#{body}")
      server = mcp_server(dir)

      root = call_tool!(server, "log", bundle: "sprawling")["logs"].first
      assert root["truncated"], "the whole file came back under a bound that claimed to hold"
      assert_equal 1, root["total"]
      assert_operator root["content"].length, :<, body.length

      raised = call_tool!(server, "log", bundle: "sprawling", limit: 5)["logs"].first
      assert_operator raised["content"].length, :>, root["content"].length,
        "`limit` could not reach this path at all"
    end

    test "a just-appended entry shows without a reboot" do
      dir = File.join(@out_dir, "logged")
      FileUtils.cp_r(fixture("knowledge"), dir)
      server = mcp_server(dir)

      File.open(File.join(dir, "log.md"), "a") { |f| f.puts "\n## 2026-07-24\n* **Update**: Appended mid-session." }
      data = call_tool!(server, "log", bundle: "logged")
      assert_match(/Appended mid-session/, data["logs"].first["content"])
    end
  end
end
