# frozen_string_literal: true

require_relative "../mcp_integration_case"

module AcrossBundles
  class SearchTest < MCPIntegrationCase
    test "an array of slugs merges into one labeled ranking" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))
      data = call_tool!(server, "search", terms: [ "invoices" ], bundles: %w[knowledge notes])

      assert_equal %w[knowledge notes], data["bundles"].map { |row| row["slug"] }
      labels = data["results"].map { |row| row["bundle"] }.uniq.sort
      assert_equal %w[knowledge notes], labels
    end

    test "\"*\" and omitting bundles both mean every bundle" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))
      starred = call_tool!(server, "search", terms: [ "invoices" ], bundles: "*")
      omitted = call_tool!(server, "search", terms: [ "invoices" ])
      assert_equal starred["results"], omitted["results"]
      assert_equal 2, starred["bundles"].length
    end

    test "federated index scores come from one corpus and stay comparable" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))
      data = call_tool!(server, "search", terms: [ "invoices" ], engine: "index")

      scores = data["results"].map { |row| row["score"] }
      assert_equal scores.sort.reverse, scores, "one merged ranking, descending"
      assert(data["results"].map { |row| row["bundle"] }.uniq.length > 1, "both bundles rank in the one list")
    end

    test "a group slug fans out to its member bundles" do
      with_registry("knowledge", "notes") do |registry|
        registry.set_group("docs", %w[knowledge notes])
        data = call_tool!(mcp_server, "search", terms: [ "invoices" ], bundles: "docs")
        assert_equal %w[knowledge notes], data["bundles"].map { |row| row["slug"] }
      end
    end

    test "a group and its member dedupe by path" do
      with_registry("knowledge", "notes") do |registry|
        registry.set_group("docs", %w[knowledge notes])
        data = call_tool!(mcp_server, "search", terms: [ "invoices" ], bundles: %w[knowledge docs])
        assert_equal %w[knowledge notes], data["bundles"].map { |row| row["slug"] }, "knowledge is searched once"
      end
    end

    test "\"*\" skips a vanished bundle and says so; naming it fails hard" do
      dir = scratch_bundle("goner")
      with_registry("knowledge") do |registry|
        registry.add(dir)
        FileUtils.rm_rf(dir)
        server = mcp_server

        data = call_tool!(server, "search", terms: [ "invoices" ], bundles: "*")
        assert_equal [ "knowledge" ], data["bundles"].map { |row| row["slug"] }
        assert_equal [ "goner" ], data["skipped"]

        named = call_tool(server, "search", terms: [ "invoices" ], bundles: "goner")
        assert named.error?
        assert_match(/which is not a directory/, named.text)
      end
    end

    test "a group with a vanished member skips it and says so" do
      dir = scratch_bundle("goner")
      with_registry("knowledge") do |registry|
        registry.add(dir)
        registry.set_group("docs", %w[knowledge goner])
        FileUtils.rm_rf(dir)

        data = call_tool!(mcp_server, "search", terms: [ "invoices" ], bundles: "docs")
        assert_equal [ "knowledge" ], data["bundles"].map { |row| row["slug"] }
        assert_equal [ "goner" ], data["skipped"]
      end
    end

    test "a group ref on argv fans out at boot, each leaf under its registered slug" do
      with_registry("knowledge", "notes") do |registry|
        registry.set_group("docs", %w[knowledge notes])
        server = mcp_server("@docs")
        data = call_tool!(server, "search", terms: [ "invoices" ])
        assert_equal %w[knowledge notes], data["bundles"].map { |row| row["slug"] }
      end
    end

    # The containment rule: argv names the served set, and nothing reached
    # through a *request* may widen it. A group is a registry identity, and in
    # argv mode it fanned out at boot — so at query time a group slug names
    # nothing served, and must not be a second door into the kernel registry.
    # `@knowledge` is what makes this bite: resolving a ref loads the kernel
    # registry at boot, and holding on to it gave a *request* a second door
    # into every bundle the operator did not serve.
    test "argv mode: a group slug cannot reach a bundle that was never served" do
      with_registry("knowledge", "notes") do |registry|
        registry.set_group("docs", %w[knowledge notes])
        server = mcp_server("@knowledge") # only knowledge is served

        result = call_tool(server, "search", terms: [ "invoices" ], bundles: "docs")
        assert result.error?, "a group slug expanded past the argv allowlist"
        refute_match(/notes/, result.text)
      end
    end

    test "argv mode: list_bundles advertises no group it cannot serve" do
      with_registry("knowledge", "notes") do |registry|
        registry.set_group("docs", %w[knowledge notes])
        data = call_tool!(mcp_server("@knowledge"), "list_bundles")

        assert_equal [ "knowledge" ], data["bundles"].map { |row| row["slug"] }
        refute data.key?("groups"), "argv mode advertised a group naming an unserved bundle"
      end
    end

    # The empty list is an argument mistake, and blaming the disk for it sends
    # the agent off diagnosing a broken installation.
    test "an empty bundles list names the argument, never the disk" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))
      result = call_tool(server, "search", terms: [ "billing" ], bundles: [])
      assert result.error?
      refute_match(/missing on disk/, result.text)
    end

    test "an unknown name among several is a tool error, not a partial answer" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))
      result = call_tool(server, "search", terms: [ "x" ], bundles: %w[knowledge nope])
      assert result.error?
      assert_match(/unknown bundle "nope"/, result.text)
    end
  end
end
