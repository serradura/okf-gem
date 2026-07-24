# frozen_string_literal: true

require_relative "../cli_integration_case"

# Discovery end-to-end — a project-local .okf-registry.json on the path up from
# cwd is *the* registry while you stand in its tree, in place of the global
# $OKF_HOME one. Its presence is the whole state; no flag turns it on. These are
# the scenarios the per-subcommand files cannot reach, because the base class
# suppresses discovery for every other test (OKF_NO_DISCOVERY=1 + a scratch cwd);
# each test here opts back in with `in_dir`, which chdirs into a real tree and
# clears the flag.
#
# The global $OKF_HOME registry stays pinned at the scratch home throughout, so
# "local replaces global" is proved against a global that genuinely holds
# something else.
module ByRegistry
  class CLIRegistryDiscoveryTest < CLIIntegrationCase
    LOCAL = ".okf-registry.json"

    # A directory carrying an (empty) local registry, ready for `in_dir`.
    def seed_local(name)
      dir = File.join(@out_dir, name)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, LOCAL), JSON.generate("bundles" => [], "groups" => []))
      dir
    end

    test "a tree with no local registry falls through to the global one" do
      okf("registry", "set", fixture("conformant")) # writes global (discovery off)
      clean = File.join(@out_dir, "no-local")
      FileUtils.mkdir_p(clean)

      out = in_dir(clean) { okf("registry", "list") }.out

      assert_match(/^\* conformant/, out, "no local file up the tree ⇒ the global registry answers")
      refute_match(/^registry:/, out, "the global registry wears no header")
    end

    test "a discovered local registry replaces the global one" do
      okf("registry", "set", fixture("conformant")) # global holds conformant
      tree = seed_local("proj")

      in_dir(tree) { okf("registry", "set", fixture("minimal")) } # writes local
      listed = in_dir(tree) { okf("registry", "list") }

      assert_equal 0, listed.status
      assert_match(/^\* minimal/, listed.out, "the local registry's own bundle is what shows")
      refute_match(/conformant/, listed.out, "the global registry is not consulted while a local one is in play")
    end

    test "an empty local registry replaces the global one — it does not merge it" do
      okf("registry", "set", fixture("conformant")) # global is non-empty
      tree = seed_local("empty-proj")

      out = in_dir(tree) { okf("registry", "list") }.out

      assert_match(/^registry: \.\/#{Regexp.escape(LOCAL)}$/, out, "the local header names the file in play")
      assert_match(/no bundles registered/, out, "empty local means empty — the global bundles do not bleed through")
      refute_match(/conformant/, out)
    end

    test "discovery walks up from a subdirectory to the nearest local registry" do
      tree = seed_local("deep")
      nested = File.join(tree, "a", "b", "c")
      FileUtils.mkdir_p(nested)
      in_dir(tree) { okf("registry", "set", fixture("conformant")) }

      listed = in_dir(nested) { okf("registry", "list") }

      assert_equal 0, listed.status
      assert_match(/^\* conformant/, listed.out, "a walk up several levels finds the registry at the root of the tree")
    end

    test "the nearest local registry wins when two sit on the path" do
      outer = seed_local("outer")
      inner = File.join(outer, "inner")
      FileUtils.mkdir_p(inner)
      File.write(File.join(inner, LOCAL), JSON.generate("bundles" => [], "groups" => []))

      in_dir(outer) { okf("registry", "set", fixture("conformant")) } # outer holds conformant
      in_dir(inner) { okf("registry", "set", fixture("minimal")) }    # inner holds minimal

      from_inner = in_dir(inner) { okf("registry", "list") }.out

      assert_match(/^\* minimal/, from_inner, "the nearer (inner) registry is the one that answers")
      refute_match(/conformant/, from_inner, "the outer one is shadowed, not merged")
    end

    test "a .okf-registry.json that is a directory is skipped, not treated as a registry" do
      okf("registry", "set", fixture("conformant")) # global fallback target
      tree = File.join(@out_dir, "trap")
      FileUtils.mkdir_p(File.join(tree, LOCAL)) # the name, but a directory

      out = in_dir(tree) { okf("registry", "list") }.out

      assert_match(/^\* conformant/, out, "only a regular file counts; the walk passes the directory and lands on global")
    end

    test "OKF_NO_DISCOVERY forces the global registry even with a local one under cwd" do
      okf("registry", "set", fixture("conformant")) # global
      File.write(File.join(Dir.pwd, LOCAL), JSON.generate(
        "bundles" => [ { "slug" => "localonly", "path" => fixture("minimal"), "title" => "t" } ], "groups" => []
      ))

      # The suite's default state: chdir'd here, OKF_NO_DISCOVERY=1 still set.
      out = okf("registry", "list").out

      assert_match(/^\* conformant/, out, "the escape hatch pins the global registry")
      refute_match(/localonly/, out)
    end

    test "a set inside a local tree writes the local file, never the global one" do
      tree = seed_local("writes")

      in_dir(tree) { okf("registry", "set", fixture("conformant")) }

      local = JSON.parse(File.read(File.join(tree, LOCAL)))
      assert_equal [ "conformant" ], local["bundles"].map { |row| row["slug"] }, "the write landed in the local registry"
      refute_path_exists File.join(@home, "registry.json"), "the global $OKF_HOME registry was never touched"
    end

    test "an @ref resolves through the discovered local registry" do
      tree = seed_local("refs")
      in_dir(tree) { okf("registry", "set", fixture("conformant"), "--as", "handbook") }

      result = in_dir(tree) { okf("lint", "@handbook") }

      assert_equal 0, result.status, "the ref-verb resolved @handbook through the local registry"
    end

    test "an @ref present only in the global registry is unknown while a local one is active" do
      okf("registry", "set", fixture("conformant"), "--as", "handbook") # global only
      tree = seed_local("shadow")

      result = in_dir(tree) { okf("lint", "@handbook") }

      assert_equal 2, result.status, "local replaces global, so a global-only ref does not resolve"
      local_path = File.realpath(File.join(tree, LOCAL))
      assert_match(/not a registered bundle: @handbook in #{Regexp.escape(local_path)}/, result.err,
        "the error names the local registry it actually consulted")
    end

    test "the human header and the JSON envelope both name the discovered local file" do
      tree = seed_local("named")
      in_dir(tree) { okf("registry", "set", fixture("conformant")) }

      human = in_dir(tree) { okf("registry", "list") }
      payload = json(in_dir(tree) { okf("registry", "list", "--json") })

      assert_match(/^registry: \.\/#{Regexp.escape(LOCAL)}$/, human.out, "cwd == the registry's dir ⇒ the ./ form")
      assert_equal File.realpath(File.join(tree, LOCAL)), payload["registry"], "the JSON names the resolved local path"
    end

    test "a malformed local registry is a usage error naming the local file" do
      tree = File.join(@out_dir, "broken")
      FileUtils.mkdir_p(tree)
      File.write(File.join(tree, LOCAL), "{ not json")

      result = in_dir(tree) { okf("registry", "list") }

      assert_equal 2, result.status
      assert_match(/malformed registry at #{Regexp.escape(File.realpath(File.join(tree, LOCAL)))}/, result.err,
        "the discovered file's own path is what the error names, so the fix is unambiguous")
    end

    test "the header shows an absolute path when discovery walked up to an ancestor" do
      tree = seed_local("ancestor")
      nested = File.join(tree, "sub")
      FileUtils.mkdir_p(nested)
      in_dir(tree) { okf("registry", "set", fixture("conformant")) }

      out = in_dir(nested) { okf("registry", "list") }.out

      assert_match(/^registry: #{Regexp.escape(File.realpath(File.join(tree, LOCAL)))}$/, out,
        "from a subdirectory the ./ form would mislead, so the header goes absolute")
    end
  end
end
