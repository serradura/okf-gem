# frozen_string_literal: true

require_relative "../cli_integration_case"

# How a project-local registry persists bundle paths (Change 2). A bundle inside
# the registry's own tree is stored *relative to the registry file*, so the file
# is committable and travels with the repo — into a checkout elsewhere, or a
# container mounting it. A bundle outside the tree keeps an absolute path (honest:
# it cannot travel). The global $OKF_HOME registry is unaffected — it stores
# absolute paths, as it always has (proved in cli_registry_set_test).
#
# Every test works from inside a real tree via `in_dir`, since relativization is
# anchored on the discovered registry's directory. Bundle paths are passed
# *relative* (`set docs`), the way a user standing in their project would, so they
# expand against the same cwd the anchor derives from.
module ByRegistry
  class CLIRegistryLocalPathsTest < CLIIntegrationCase
    LOCAL = ".okf-registry.json"

    # A project root carrying an empty local registry.
    def project(name)
      root = File.join(@out_dir, name)
      FileUtils.mkdir_p(root)
      File.write(File.join(root, LOCAL), JSON.generate("bundles" => [], "groups" => []))
      root
    end

    # A one-concept bundle at +root+/+subdir+.
    def bundle_under(root, subdir)
      dir = File.join(root, subdir)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "note.md"), "---\ntype: Note\ntitle: Note\n---\n\nBody.\n")
      dir
    end

    def stored_paths(root)
      JSON.parse(File.read(File.join(root, LOCAL)))["bundles"].map { |row| row["path"] }
    end

    test "a bundle inside the tree is stored relative to the registry file" do
      root = project("proj")
      bundle_under(root, "docs")

      in_dir(root) { okf("registry", "set", "docs") }

      assert_equal [ "docs" ], stored_paths(root), "an inside-tree bundle persists a path relative to the registry"
    end

    test "a bundle in a subdirectory keeps its relative shape, not just its basename" do
      root = project("proj")
      bundle_under(root, "areas/backend")

      in_dir(root) { okf("registry", "set", "areas/backend") }

      assert_equal [ "areas/backend" ], stored_paths(root), "the relative path is the whole path under the registry, not the leaf"
    end

    test "a bundle outside the tree keeps an absolute path" do
      root = project("proj")
      outside = File.join(@out_dir, "outside-bundle")
      FileUtils.mkdir_p(outside)
      File.write(File.join(outside, "note.md"), "---\ntype: Note\ntitle: N\n---\n\nB.\n")

      in_dir(root) { okf("registry", "set", outside) }

      stored = stored_paths(root).first
      assert stored.start_with?("/"), "a bundle the registry cannot reach relatively stays absolute: #{stored}"
      assert_equal File.expand_path(outside), stored
    end

    test "the listing shows a relative-stored bundle at its resolved absolute path" do
      root = project("proj")
      bundle_under(root, "docs")
      in_dir(root) { okf("registry", "set", "docs") }

      row = json(in_dir(root) { okf("registry", "list", "--json") })["bundles"].first

      assert_equal File.realpath(File.join(root, "docs")), row["dir"], "resolution is invisible — the user sees a real absolute path"
    end

    test "a relative-stored bundle resolves after the whole tree moves" do
      root = project("proj")
      bundle_under(root, "docs")
      in_dir(root) { okf("registry", "set", "docs", "--as", "handbook") }

      moved = File.join(@out_dir, "relocated")
      FileUtils.mv(root, moved)

      result = in_dir(moved) { okf("lint", "@handbook") }
      assert_equal 0, result.status, "the relative entry re-anchored on the registry's new location — this is the portability the storage buys"

      row = json(in_dir(moved) { okf("registry", "list", "--json") })["bundles"].first
      assert_equal File.realpath(File.join(moved, "docs")), row["dir"], "and it now resolves under the moved tree"
    end

    test "an absolute inside-tree entry migrates to relative on the next write" do
      root = project("proj")
      docs = bundle_under(root, "docs")
      bundle_under(root, "runbooks")
      # A Change-1-shaped file: an absolute inside-tree path, hand-written.
      File.write(File.join(root, LOCAL), JSON.generate(
        "bundles" => [ { "slug" => "docs", "path" => File.realpath(docs), "title" => "docs" } ], "groups" => []
      ))

      in_dir(root) { okf("registry", "set", "runbooks") } # any write migrates the file

      assert_equal %w[docs runbooks], stored_paths(root),
        "the pre-existing absolute inside-tree path was rewritten relative on the first write after the upgrade"
    end
  end
end
