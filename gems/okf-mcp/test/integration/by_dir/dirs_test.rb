# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  class DirsTest < MCPIntegrationCase
    test "one row per directory with direct count, subtree and subdirs" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "dirs", bundle: "knowledge")

      assert_equal "knowledge", data["bundle"]
      assert_equal 4, data["total"]
      by_dir = data["dirs"].to_h { |row| [ row["dir"], row ] }
      assert_equal %w[. decisions runbooks services], by_dir.keys.sort

      assert_equal 0, by_dir["."]["count"]
      assert_equal 4, by_dir["."]["subtree"]
      assert_equal %w[decisions runbooks services], by_dir["."]["subdirs"].sort
      assert_equal 2, by_dir["services"]["count"]
      assert_equal 2, by_dir["services"]["subtree"]
    end

    # `total` counts what the request matched, here and in every other tool.
    # It used to stay at the whole bundle's directory count so the narrowing
    # was visible — defensible alone, wrong as a set: catalog and search count
    # theirs *after* filtering, so one key answered two questions, and the
    # module's own promise ("every list output is bounded with a visible
    # total") made the larger number read as rows withheld.
    test "dir narrows to one branch, and total counts what matched" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "dirs", bundle: "knowledge", dir: "services")
      assert_equal [ "services" ], data["dirs"].map { |row| row["dir"] }
      assert_equal 1, data["total"]
      assert_equal data["dirs"].length, data["total"], "dirs never truncates, so the two always agree"
    end

    test "depth bounds how far below the start rows go" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "dirs", bundle: "knowledge", depth: 0)
      assert_equal [ "." ], data["dirs"].map { |row| row["dir"] }
    end

    test "an unknown dir is a tool error naming the bundle" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "dirs", bundle: "knowledge", dir: "no-such")
      assert result.error?
      assert_match(/no directory "no-such" in bundle "knowledge"/, result.text)
    end

    # The dir vocabulary must read the same to every tool: catalog has always
    # matched a directory case-insensitively, so the orientation tools cannot
    # answer "no such directory" for a name catalog happily resolves.
    test "a dir is matched case-insensitively, as catalog matches it" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "dirs", bundle: "knowledge", dir: "Services")
      assert_equal [ "services" ], data["dirs"].map { |row| row["dir"] }
    end

    test "\"/\" names the bundle root, as it does everywhere else" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "dirs", bundle: "knowledge", dir: "/")
      assert_includes data["dirs"].map { |row| row["dir"] }, "."
    end

    # The other half of catalog's "a directory literally named root is
    # addressable": here the fold was doubly silent, because `scoped_rows`
    # skips its existence check for the root, so neither the narrowing nor the
    # refusal happened.
    test "a directory literally named root narrows to itself" do
      server = mcp_server(fixture("rooted"))
      data = call_tool!(server, "dirs", bundle: "rooted", dir: "root")
      assert_equal [ "root" ], data["dirs"].map { |row| row["dir"] }
      assert_equal 2, data["dirs"].first["count"]
    end

    # The directory map counts every file kind that makes a directory real: a
    # scoped log.md is read by the `log` tool, so the directory holding it
    # exists — while a directory holding only a file the reader skipped is not
    # one the bundle can answer about, and stays out on both sides.
    test "a directory holding only a scoped log is listed and addressable" do
      server = mcp_server(fixture("journaled"))

      listed = call_tool!(server, "dirs", bundle: "journaled")["dirs"].map { |row| row["dir"] }
      assert_includes listed, "archive"
      refute_includes listed, "drafts", "an unparseable-only directory is not part of the served map"

      narrowed = call_tool!(server, "dirs", bundle: "journaled", dir: "archive")
      assert_equal [ "archive" ], narrowed["dirs"].map { |row| row["dir"] }
      assert_equal 0, narrowed["dirs"].first["count"]
    end

    test "\"root\" in a bundle that has no such directory is refused, not folded" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "dirs", bundle: "knowledge", dir: "root")
      assert result.error?
      assert_match(/no directory "root" in bundle "knowledge"/, result.text)
    end

    # An unrecognized argument must come back as something the model can read
    # and retry, never as a protocol-level -32603 with no message.
    test "an unknown argument is an actionable tool error, not a protocol error" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "dirs", bundle: "knowledge", sort: "title")
      assert result.error?
      assert_match(/sort/, result.text)
    end

    test "an unknown bundle is a tool error listing the known slugs" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))
      result = call_tool(server, "dirs", bundle: "nope")
      assert result.error?
      assert_match(/unknown bundle "nope" — known: knowledge, notes/, result.text)
    end
  end
end
