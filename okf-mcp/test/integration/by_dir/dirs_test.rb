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

    test "dir narrows to one branch" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "dirs", bundle: "knowledge", dir: "services")
      assert_equal [ "services" ], data["dirs"].map { |row| row["dir"] }
      assert_equal 4, data["total"], "total stays the whole bundle so the narrowing is visible"
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
