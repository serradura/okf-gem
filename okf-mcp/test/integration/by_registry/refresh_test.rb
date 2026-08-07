# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByRegistry
  # The identity map follows the registry file, on exactly the rule the
  # residency layer already applies to bundle contents: re-read when the
  # fingerprint moves, otherwise don't touch the disk.
  #
  # It used to be a boot snapshot. Three of the four ways that went wrong were
  # loud (an unknown slug names what it knows), but the fourth was not: an entry
  # repointed at a new directory kept serving the old one under the current
  # slug — a silent wrong answer, which is the shape this gem refuses
  # everywhere else.
  class RefreshTest < MCPIntegrationCase
    test "a bundle registered after boot is served" do
      registry = OKF::Registry.load
      registry.add(fixture("knowledge"))
      server = mcp_server
      assert_equal %w[knowledge], call_tool!(server, "list_bundles")["bundles"].map { |row| row["slug"] }

      registry.add(fixture("notes"))

      assert_equal %w[knowledge notes], call_tool!(server, "list_bundles")["bundles"].map { |row| row["slug"] }
      refute call_tool(server, "dirs", bundle: "notes").error?, "the new bundle is not queryable"
    end

    # The one that was silently wrong.
    test "an entry repointed at another directory serves the new one" do
      registry = OKF::Registry.load
      registry.add(fixture("knowledge"))
      server = mcp_server
      assert_equal 4, call_tool!(server, "dirs", bundle: "knowledge")["total"]

      moved = File.join(@out_dir, "knowledge")
      FileUtils.cp_r(fixture("notes"), moved)
      registry.remove("knowledge")
      registry.add(moved, as: "knowledge")

      row = call_tool!(server, "list_bundles")["bundles"].first
      assert_equal File.realpath(moved), File.realpath(row["root"])
      assert_equal 1, call_tool!(server, "dirs", bundle: "knowledge")["total"],
        "still answering from the directory the slug used to point at"
    end

    test "a bundle removed from the registry stops being served" do
      registry = OKF::Registry.load
      registry.add(fixture("knowledge"))
      registry.add(fixture("notes"))
      server = mcp_server
      refute call_tool(server, "dirs", bundle: "notes").error?

      registry.remove("notes")

      result = call_tool(server, "dirs", bundle: "notes")
      assert result.error?
      assert_match(/unknown bundle "notes" — known: knowledge/, result.text)
    end

    test "a rename takes effect under the new slug" do
      registry = OKF::Registry.load
      registry.add(fixture("knowledge"))
      server = mcp_server

      registry.rename("knowledge", "handbook")

      assert_equal %w[handbook], call_tool!(server, "list_bundles")["bundles"].map { |row| row["slug"] }
      assert call_tool(server, "dirs", bundle: "knowledge").error?, "the old slug still resolves"
    end

    # The resource list is derived from the same identity map, so it has to
    # move with it. It was computed once in `build` and handed to the SDK as a
    # fixed array, which put the two out of step the moment the registry moved:
    # a bundle registered afterwards never appeared, and a removed one stayed
    # advertised until a read of the very URI we published failed with "unknown
    # bundle". Nothing declares `listChanged`, so a host cannot be told either.
    test "the resource list follows the registry, as the served set does" do
      registry = OKF::Registry.load
      registry.add(fixture("knowledge"))
      server = mcp_server
      assert_equal %w[okf://knowledge], resource_uris(server)

      registry.add(fixture("notes"))
      assert_equal %w[okf://knowledge okf://notes], resource_uris(server)

      registry.remove("knowledge")
      assert_equal %w[okf://notes], resource_uris(server)
    end

    # Listed implies readable, which is the property the boot snapshot broke:
    # every URI the server advertises has to answer, not just the ones that
    # were registered when the process started.
    test "a bundle registered after boot is readable at the URI now advertised" do
      OKF::Registry.load.add(fixture("knowledge"))
      server = mcp_server
      OKF::Registry.load.add(fixture("notes"))

      assert_includes resource_uris(server), "okf://notes"
      contents = rpc(server, "resources/read", uri: "okf://notes").dig("result", "contents")
      assert_equal read_utf8(File.join(fixture("notes"), "index.md")), contents.first["text"]
    end

    # The stamp is a claim about a file the instance has *already read*, so it
    # must never be taken after that read: a write landing in between is
    # recorded as already-seen — entries from before it, fingerprint from after
    # — and refresh! then sees nothing to do until some *further* write moves
    # the fingerprint again. refresh! itself stats before it reopens and is
    # fine; only the boot path had the order backwards.
    #
    # Simulated deterministically, because the real window is sub-millisecond:
    # write in the gap the race lives in — after `from_kernel` has read the file
    # and before anything stamps it — then restore the stat the boot would have
    # taken. A rename between two nine-character slugs is size-neutral, so
    # `utime` puts the whole fingerprint back, which is precisely the state the
    # race leaves behind: a file that has moved and a stat that cannot tell.
    #
    # The boot is spelled out rather than taken from #mcp_server because the gap
    # is the subject: the first request stamps (every one prunes the residency
    # through the registry), so the write has to land before it.
    test "a write landing during boot is not recorded as already-seen" do
      OKF::Registry.load.add(fixture("knowledge"))
      path = OKF::Registry.path
      booted = File.stat(path)

      registry = OKF::MCP::Registry.from_kernel

      OKF::Registry.load.rename("knowledge", "reference")
      File.utime(booted.atime, booted.mtime, path)
      assert_equal booted.size, File.stat(path).size, "the simulated write moved the fingerprint"

      server = OKF::MCP::Server.build(registry, engine: OKF::MCP::MemoryBackend.new)
      handshake(server)
      assert_equal %w[reference], call_tool!(server, "list_bundles")["bundles"].map { |row| row["slug"] }
    end

    # The containment property, restated as a *consequence of the shape* rather
    # than a flag: argv mode never carried the kernel registry, so there is
    # nothing to re-read and nothing that can widen the served set afterwards.
    test "argv mode does not follow the registry — the served set stays closed" do
      registry = OKF::Registry.load
      registry.add(fixture("knowledge"))
      server = mcp_server(fixture("knowledge"))

      registry.add(fixture("notes"))

      assert_equal %w[knowledge], call_tool!(server, "list_bundles")["bundles"].map { |row| row["slug"] }
      assert call_tool(server, "dirs", bundle: "notes").error?,
        "a bundle argv never named became reachable"
    end

    # The fingerprint has to actually gate the work, or this is just a re-parse
    # per call wearing a stat.
    test "an unchanged registry file is not re-read" do
      OKF::Registry.load.add(fixture("knowledge"))
      server = mcp_server
      call_tool!(server, "list_bundles")

      reopens = 0
      OKF::Registry.prepend(Module.new do
        define_method(:reopen) { reopens += 1; super() }
      end)
      3.times { call_tool!(server, "list_bundles") }

      assert_equal 0, reopens, "the file was re-parsed with nothing changed"
    end

    # A registry that cannot be read must not take down a server that already
    # has a working set — and must recover on its own when the file comes back.
    test "an unreadable registry keeps the last good set, and recovers" do
      registry = OKF::Registry.load
      registry.add(fixture("knowledge"))
      server = mcp_server
      assert_equal %w[knowledge], call_tool!(server, "list_bundles")["bundles"].map { |row| row["slug"] }

      File.write(registry.path, "{ not json")
      assert_equal %w[knowledge], call_tool!(server, "list_bundles")["bundles"].map { |row| row["slug"] },
        "a malformed file emptied the served set instead of holding the last good one"

      File.delete(registry.path)
      assert_equal %w[knowledge], call_tool!(server, "list_bundles")["bundles"].map { |row| row["slug"] },
        "a deleted file emptied the served set"

      OKF::Registry.load.add(fixture("notes"))
      assert_equal %w[notes], call_tool!(server, "list_bundles")["bundles"].map { |row| row["slug"] },
        "the server never picked the registry back up"
    end

    private

    def resource_uris(server)
      rpc(server, "resources/list").dig("result", "resources").map { |row| row["uri"] }
    end
  end
end
