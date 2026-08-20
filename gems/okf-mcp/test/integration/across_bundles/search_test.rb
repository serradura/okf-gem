# frozen_string_literal: true

require_relative "../mcp_integration_case"

module AcrossBundles
  class SearchTest < MCPIntegrationCase
    # search is the only tool that takes a *set*, and it used to say so in the
    # argument's name — `bundles` against the nine others' `bundle`. The
    # plural's signal only ever arrived after a failed call, because the SDK
    # rejects an unknown property before any okf sentence can be written: a
    # host that had just called dirs(bundle:) got back "object property at
    # `/bundle` is a disallowed additional property" and no hint. One name for
    # the identity slot on every tool is the kernel's own convention too —
    # `okf search <dir|@slug…>` and `okf lint <dir|@slug>` are the same slot.
    test "the identity argument is `bundle` here, exactly as on the other nine tools" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))

      one = call_tool!(server, "search", terms: [ "invoices" ], bundle: "knowledge")
      assert_equal %w[knowledge], one["bundles"].map { |row| row["slug"] }

      many = call_tool!(server, "search", terms: [ "invoices" ], bundle: %w[knowledge notes])
      assert_equal %w[knowledge notes], many["bundles"].map { |row| row["slug"] }
    end

    test "the plural is gone, not aliased — one name, or it is two things to keep working" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))
      result = call_tool(server, "search", terms: [ "invoices" ], bundles: "knowledge")

      assert result.error?, "`bundles` must not survive as a second spelling"
      assert_match(/bundles/, result.text)
    end

    test "an array of slugs merges into one labeled ranking" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))
      data = call_tool!(server, "search", terms: [ "invoices" ], bundle: %w[knowledge notes])

      assert_equal %w[knowledge notes], data["bundles"].map { |row| row["slug"] }
      labels = data["results"].map { |row| row["bundle"] }.uniq.sort
      assert_equal %w[knowledge notes], labels
    end

    test "\"*\" and omitting `bundle` both mean every bundle" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))
      starred = call_tool!(server, "search", terms: [ "invoices" ], bundle: "*")
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
        data = call_tool!(mcp_server, "search", terms: [ "invoices" ], bundle: "docs")
        assert_equal %w[knowledge notes], data["bundles"].map { |row| row["slug"] }
      end
    end

    test "a group and its member dedupe by path" do
      with_registry("knowledge", "notes") do |registry|
        registry.set_group("docs", %w[knowledge notes])
        data = call_tool!(mcp_server, "search", terms: [ "invoices" ], bundle: %w[knowledge docs])
        assert_equal %w[knowledge notes], data["bundles"].map { |row| row["slug"] }, "knowledge is searched once"
      end
    end

    test "\"*\" skips a vanished bundle and says so; naming it fails hard" do
      dir = scratch_bundle("goner")
      with_registry("knowledge") do |registry|
        registry.add(dir)
        FileUtils.rm_rf(dir)
        server = mcp_server

        data = call_tool!(server, "search", terms: [ "invoices" ], bundle: "*")
        assert_equal [ "knowledge" ], data["bundles"].map { |row| row["slug"] }
        assert_equal [ "goner" ], data["skipped"]

        named = call_tool(server, "search", terms: [ "invoices" ], bundle: "goner")
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

        data = call_tool!(mcp_server, "search", terms: [ "invoices" ], bundle: "docs")
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

        result = call_tool(server, "search", terms: [ "invoices" ], bundle: "docs")
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
    test "an empty bundle list names the argument, never the disk" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))
      result = call_tool(server, "search", terms: [ "billing" ], bundle: [])
      assert result.error?
      refute_match(/missing on disk/, result.text)
    end

    test "an unknown name among several is a tool error, not a partial answer" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))
      result = call_tool(server, "search", terms: [ "x" ], bundle: %w[knowledge nope])
      assert result.error?
      assert_match(/unknown bundle "nope"/, result.text)
    end

    # A `dir` refusal has to be a fact about the *searched set*, not about each
    # bundle in turn. `services` exists in knowledge and not in notes, which is
    # the ordinary cross-bundle case and must answer, not refuse.
    test "a dir only one searched bundle has still filters, and does not refuse" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))
      data = call_tool!(server, "search", terms: [ "billing" ], dir: "services")

      assert_equal %w[knowledge], data["results"].map { |row| row["bundle"] }.uniq
      assert_equal [ "services/billing" ], data["results"].map { |row| row["id"] }
    end

    test "a dir no searched bundle has is refused, naming what was asked" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))
      result = call_tool(server, "search", terms: [ "billing" ], dir: "servicez")

      assert result.error?
      assert_match(/no directory "servicez"/, result.text)
    end
  end
end
