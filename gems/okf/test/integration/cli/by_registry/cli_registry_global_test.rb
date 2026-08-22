# frozen_string_literal: true

require_relative "../cli_integration_case"

# `-g/--global` end-to-end — the per-command form of what OKF_NO_DISCOVERY does
# for a whole session: it forces the *global* $OKF_HOME registry even while a
# project-local one is in force. Every registry subcommand takes it except
# `init`, whose whole job is to create a local file.
#
# Discovery has to be live for any of this to mean anything, so each test runs
# through `in_dir` (which chdirs into a tree carrying a local registry and clears
# the suppression flag the base class sets).
module ByRegistry
  class CLIRegistryGlobalTest < CLIIntegrationCase
    LOCAL = ".okf-registry.json"

    # A directory carrying a local registry holding just the minimal fixture, so
    # "which registry answered?" has a visibly different answer either way.
    def seed_local(name)
      dir = File.join(@out_dir, name)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, LOCAL), JSON.generate("bundles" => [], "groups" => []))
      in_dir(dir) { okf("registry", "set", fixture("minimal")) }
      dir
    end

    test "list -g reads the global registry from inside a local one's tree" do
      okf("registry", "set", fixture("conformant")) # global
      tree = seed_local("proj")

      local = in_dir(tree) { okf("registry", "list") }
      global = in_dir(tree) { okf("registry", "list", "-g") }

      assert_match(/^\* minimal/, local.out, "without the flag the local registry still wins")
      assert_equal 0, global.status
      assert_match(/^\* conformant/, global.out)
      refute_match(/minimal/, global.out, "-g replaces the local registry, it does not merge it")
    end

    test "list -g names the file it read, so which registry answered is never a guess" do
      okf("registry", "set", fixture("conformant"))
      tree = seed_local("named")

      out = in_dir(tree) { okf("registry", "list", "-g") }.out

      assert_match(/^registry: #{Regexp.escape(File.join(@home, "registry.json"))}$/, out)
    end

    test "set -g writes the global registry while a local one is in force" do
      tree = seed_local("writes")

      result = in_dir(tree) { okf("registry", "set", fixture("conformant"), "-g") }

      assert_equal 0, result.status
      global = JSON.parse(File.read(File.join(@home, "registry.json")))
      assert_equal %w[conformant], global["bundles"].map { |row| row["slug"] }
      local = JSON.parse(File.read(File.join(tree, LOCAL)))
      assert_equal %w[minimal], local["bundles"].map { |row| row["slug"] },
        "the local registry is untouched by a -g write"
    end

    test "--global is the long form, and reaches del, default, rename and group too" do
      okf("registry", "set", fixture("conformant"))
      okf("registry", "set", fixture("minimal"))
      tree = seed_local("verbs")

      in_dir(tree) do
        assert_equal 0, okf("registry", "default", "@minimal", "--global").status
        assert_equal 0, okf("registry", "rename", "@minimal", "small", "--global").status
        assert_equal 0, okf("registry", "group", "both", "@small", "@conformant", "--global").status
        assert_equal 0, okf("registry", "ungroup", "both", "@conformant", "--global").status
        assert_equal 0, okf("registry", "del", "@small", "--global").status
      end

      global = JSON.parse(File.read(File.join(@home, "registry.json")))
      assert_equal %w[conformant], global["bundles"].map { |row| row["slug"] }
      assert_equal [], global["groups"], "ungrouping the last member deleted the group, globally"
    end

    test "init refuses -g: its whole job is to create a local file" do
      result = okf("registry", "init", "-g")

      assert_equal 2, result.status
      assert_match(/invalid option/, result.err)
    end

    test "-g outside any local registry is simply the registry you were already on" do
      okf("registry", "set", fixture("conformant"))

      assert_equal okf("registry", "list").out, okf("registry", "list", "-g").out.sub(/\Aregistry: .*\n/, "")
    end
  end
end
