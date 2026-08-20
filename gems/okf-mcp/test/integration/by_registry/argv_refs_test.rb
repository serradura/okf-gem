# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByRegistry
  # The third spelling of identity: argv @refs — registry slugs named at boot,
  # mixed with plain dirs. The ref grammar is the CLI's: @slug, bare @ for the
  # default, groups fanning out (see across_bundles/search_test).
  class ArgvRefsTest < MCPIntegrationCase
    test "an argv @ref serves the registered bundle under its registered slug" do
      registry = OKF::Registry.load
      registry.add(fixture("knowledge"), as: "handbook")

      server = mcp_server("@handbook")
      data = call_tool!(server, "list_bundles")
      assert_equal [ "handbook" ], data["bundles"].map { |row| row["slug"] }
      assert_equal registry.path, data["registry_source"], "consulting a ref names the registry in the boot payload"
    end

    test "a bare @ serves the registry's default" do
      with_registry("knowledge", "notes") do
        server = mcp_server("@")
        assert_equal [ "knowledge" ], call_tool!(server, "list_bundles")["bundles"].map { |row| row["slug"] }
      end
    end

    test "a registered ref keeps its slug against a same-named plain dir, whatever the argv order" do
      copy = File.join(@out_dir, "knowledge")
      FileUtils.cp_r(fixture("knowledge"), copy)
      OKF::Registry.load.add(fixture("knowledge")) # slug: knowledge

      server = mcp_server(copy, "@knowledge")
      slugs = call_tool!(server, "list_bundles")["bundles"].map { |row| row["slug"] }
      assert_equal %w[knowledge-2 knowledge], slugs
    end
  end
end
