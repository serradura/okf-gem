# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByRegistry
  class ListBundlesTest < MCPIntegrationCase
    test "serves the registered bundles and names the registry file" do
      with_registry("knowledge", "notes") do |registry|
        server = mcp_server
        data = call_tool!(server, "list_bundles")

        assert_equal registry.path, data["registry_source"]
        assert_equal %w[knowledge notes], data["bundles"].map { |row| row["slug"] }
        assert_equal "knowledge", data["default"], "the first registered entry is the default"
      end
    end

    test "an explicit slug from `as` is the served name" do
      registry = OKF::Registry.load
      registry.add(fixture("knowledge"), as: "handbook")
      server = mcp_server
      assert_equal [ "handbook" ], call_tool!(server, "list_bundles")["bundles"].map { |row| row["slug"] }
    end

    test "a registered directory that vanished is reported missing, not dropped" do
      dir = scratch_bundle("goner")
      with_registry("knowledge") do |registry|
        registry.add(dir)
        FileUtils.rm_rf(dir)

        server = mcp_server
        rows = call_tool!(server, "list_bundles")["bundles"]
        goner = rows.find { |row| row["slug"] == "goner" }
        assert goner["missing"]
        refute goner.key?("concepts"), "no counts for a directory that is not there"
        refute rows.find { |row| row["slug"] == "knowledge" }.key?("missing")
      end
    end

    test "groups are listed beside the bundles" do
      with_registry("knowledge", "notes") do |registry|
        registry.set_group("docs", %w[knowledge notes])
        server = mcp_server
        data = call_tool!(server, "list_bundles")
        assert_equal [ { "slug" => "docs", "members" => %w[knowledge notes], "resolved" => 2, "link" => nil } ], data["groups"]
      end
    end

    test "a project-local registry wins while cwd is in its tree" do
      with_registry("knowledge") do
        project = File.join(@out_dir, "project")
        FileUtils.mkdir_p(project)
        local = OKF::Registry.new(File.join(project, ".okf-registry.json"), relative_base: project)
        local.add(fixture("notes"))

        in_dir(project) do
          data = call_tool!(mcp_server, "list_bundles")
          assert_equal [ "notes" ], data["bundles"].map { |row| row["slug"] }
          # realpath both sides: discovery walks up from the *resolved* cwd, so
          # on macOS the found path spells /private/var where mktmpdir said /var.
          assert_equal File.realpath(local.path), File.realpath(data["registry_source"])
        end
      end
    end

    test "OKF_NO_DISCOVERY forces the global registry from inside a local tree" do
      with_registry("knowledge") do |registry|
        project = File.join(@out_dir, "project")
        FileUtils.mkdir_p(project)
        OKF::Registry.new(File.join(project, ".okf-registry.json"), relative_base: project).add(fixture("notes"))

        was = Dir.pwd
        begin
          Dir.chdir(project) # OKF_NO_DISCOVERY=1 is the suite's hermetic default
          data = call_tool!(mcp_server, "list_bundles")
          assert_equal [ "knowledge" ], data["bundles"].map { |row| row["slug"] }
          assert_equal registry.path, data["registry_source"]
        ensure
          Dir.chdir(was)
        end
      end
    end
  end
end
