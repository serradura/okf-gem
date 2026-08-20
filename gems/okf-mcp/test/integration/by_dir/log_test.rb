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

    # The size bound has to hold on the structured path too. §7 fixes no
    # heading level, so a whole history under one `## ` heading is conformant;
    # it splits into exactly one entry and came back whole — the unbounded
    # read surviving a second time, this time behind a `total: 1` that read
    # as bounded.
    test "a huge log under a single `## ` heading is cut by size, and `limit` scales the cap" do
      dir = File.join(@out_dir, "monolithic")
      FileUtils.cp_r(fixture("knowledge"), dir)
      body = "One heading, endless history. " * 1_000
      File.write(File.join(dir, "log.md"), "# Update Log

## History

#{body}")
      server = mcp_server(dir)

      root = call_tool!(server, "log", bundle: "monolithic")["logs"].first
      assert_equal 1, root["total"]
      assert_equal 1, root["returned"]
      assert root["truncated"], "the whole file came back under a bound that claimed to hold"
      assert_operator root["content"].length, :<, body.length

      raised = call_tool!(server, "log", bundle: "monolithic", limit: 20)["logs"].first
      refute raised["truncated"], "a raised limit covers the whole file"
      assert_match(/endless history\. $/, raised["content"])
    end

    # A structured log with no entries yet — a scaffolded title and nothing
    # else — holds zero entries and must say zero. Counting the bare title as
    # one entry told an agent checking history before trusting knowledge that
    # there is history where there is none; only content the split cannot
    # divide is an indivisible entry, and a title is not content.
    test "a log holding only its title reports zero entries" do
      dir = File.join(@out_dir, "scaffolded")
      FileUtils.cp_r(fixture("knowledge"), dir)
      File.write(File.join(dir, "log.md"), "# Update Log

")
      server = mcp_server(dir)

      root = call_tool!(server, "log", bundle: "scaffolded")["logs"].first
      assert_equal 0, root["total"]
      assert_equal 0, root["returned"]
      assert_match(/# Update Log/, root["content"], "the title still names the scope")
    end

    # The budget's unit is the promise: it is announced as bytes, sized from a
    # byte measurement, and exists to give an agent host a context-cost bound.
    # Enforcing it with String#length counted characters, so a multibyte log
    # sailed past the cap at up to 4x the announced bytes — silently, since
    # `truncated` never fired either.
    test "the budget is enforced in bytes, so a multibyte log cannot slip the cap" do
      dir = File.join(@out_dir, "dashed")
      FileUtils.cp_r(fixture("knowledge"), dir)
      File.write(File.join(dir, "log.md"), "# Update Log\n\n## 2026-08-01\n\n#{"\u2014" * 4_000}\n")
      server = mcp_server(dir)

      root = call_tool!(server, "log", bundle: "dashed", limit: 1)["logs"].first
      assert root["truncated"], "12,000 bytes of em-dashes passed a 4,500-byte budget unannounced"
      assert_operator root["content"].bytesize, :<=, OKF::MCP::Server::LOG_BUDGET
      assert root["content"].valid_encoding?, "the byte cut may not shear a character in half"
    end

    # `returned` is defined as "how many came back". Counting it before the
    # byte cut claimed entries whose very headings the cut removed — an agent
    # checking history counts an entry it never received, and paging keyed on
    # returned == limit believes it already saw everything.
    test "`returned` counts the entries that actually survived the byte cut" do
      dir = File.join(@out_dir, "verbose")
      FileUtils.cp_r(fixture("knowledge"), dir)
      entries = (1..3).map { |n| "## 2026-08-0#{n}\n\n#{"entry #{n} prose. " * 500}\n" }.reverse.join("\n")
      File.write(File.join(dir, "log.md"), "# Update Log\n\n#{entries}")
      server = mcp_server(dir)

      root = call_tool!(server, "log", bundle: "verbose", limit: 3)["logs"].first
      assert root["truncated"]
      assert_equal 3, root["total"]
      assert_operator root["returned"], :<, 3, "the third entry was wholly cut and still counted as returned"
      assert_equal root["content"].scan(/^## /).length, root["returned"],
        "`returned` and the headings actually present must agree"
    end

    # The zero check anchored the title at byte 0, so a scaffolded log whose
    # title sits after a blank line was counted as one entry — the same false
    # history the check exists to refuse, one whitespace over.
    test "a scaffolded title behind a leading blank line still counts zero" do
      dir = File.join(@out_dir, "padded")
      FileUtils.cp_r(fixture("knowledge"), dir)
      File.write(File.join(dir, "log.md"), "\n# Update Log\n\n")
      server = mcp_server(dir)

      root = call_tool!(server, "log", bundle: "padded")["logs"].first
      assert_equal 0, root["total"]
      assert_equal 0, root["returned"]
    end

    # The zero-entry rows used to be hand-built literals that skipped the
    # budget entirely; every row goes through the same sizing now, so even the
    # pathological title-only monster is bounded.
    test "even a title-only log is held to the budget" do
      dir = File.join(@out_dir, "titled")
      FileUtils.cp_r(fixture("knowledge"), dir)
      File.write(File.join(dir, "log.md"), "# Update Log#{" padding" * 3_000}\n\n")
      server = mcp_server(dir)

      root = call_tool!(server, "log", bundle: "titled")["logs"].first
      assert_equal 0, root["total"]
      assert root["truncated"], "a 24,000-byte title line came back whole"
      assert_operator root["content"].bytesize, :<=, OKF::MCP::Server::LOG_BUDGET * 3
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
