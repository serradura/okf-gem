# frozen_string_literal: true

require_relative "../cli_integration_case"

# The project-local registry's filename — `.okf.json`, with the older
# `.okf-registry.json` still discovered so no committed registry breaks.
#
# Both names are looked for in *each* directory on the way up, so the "nearest
# one wins" rule keeps its shape: a `.okf.json` two levels down still beats a
# `.okf-registry.json` at the root. Within one directory the new name wins.
#
# The deprecation note is the `registry` umbrella's alone. It is the one verb
# whose subject *is* the registry file, and it is not run in a loop or a pipe —
# `lint` and `search` are, and a note there is noise people redirect away.
module ByRegistry
  class CLIRegistryFilenameTest < CLIIntegrationCase
    SHORT = ".okf.json"
    LEGACY = ".okf-registry.json"

    # A project directory carrying a local registry under +name+, with one
    # fixture registered in it. Written by hand rather than through `registry
    # set`, so the filename under test is the only thing that decides discovery.
    def project(name, slug: "conformant")
      dir = File.join(@out_dir, "proj-#{name.delete(".")}")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, name), JSON.pretty_generate(
        "bundles" => [ { "slug" => slug, "path" => fixture(slug), "title" => slug } ],
        "groups" => [], "links" => []
      ))
      dir
    end

    test "a .okf.json is discovered, and the listing names it" do
      dir = project(SHORT)

      result = in_dir(dir) { okf("registry", "list") }

      assert_equal 0, result.status
      assert_match(/^registry: \.\/#{Regexp.escape(SHORT)}$/, result.out,
        "the short name is the local registry, discovered exactly as the long one was")
      assert_match(/^\* conformant/, result.out)
    end

    test "a .okf-registry.json is still discovered — no committed registry breaks" do
      dir = project(LEGACY)

      result = in_dir(dir) { okf("registry", "list") }

      assert_equal 0, result.status
      assert_match(/^\* conformant/, result.out, "the old name keeps resolving its bundles")
    end

    test "the old name earns a note on stderr, naming the one move that retires it" do
      dir = project(LEGACY)

      result = in_dir(dir) { okf("registry", "list") }

      assert_match(/#{Regexp.escape(LEGACY)} is the old name/, result.err)
      assert_match(/#{Regexp.escape(SHORT)}/, result.err, "the note has to say what to rename it to")
    end

    test "the short name is silent — there is nothing to deprecate" do
      dir = project(SHORT)

      result = in_dir(dir) { okf("registry", "list") }

      assert_empty result.err, "a note on the current name is pure noise"
    end

    test "only the registry umbrella notes it — lint and search stay quiet" do
      dir = project(LEGACY)

      lint, search = in_dir(dir) { [ okf("lint", "@conformant"), okf("search", "@conformant", "concept") ] }

      refute_match(/old name/, lint.err, "lint runs in CI and in loops; a note there is noise")
      refute_match(/old name/, search.err, "search is piped into other things")
    end

    test "a directory holding both names reads the short one, and says which it ignored" do
      dir = project(SHORT)
      File.write(File.join(dir, LEGACY), JSON.pretty_generate(
        "bundles" => [ { "slug" => "minimal", "path" => fixture("minimal"), "title" => "minimal" } ],
        "groups" => [], "links" => []
      ))

      result = in_dir(dir) { okf("registry", "list") }

      assert_match(/^\* conformant/, result.out, "the short name wins within a directory")
      refute_match(/minimal/, result.out, "and the legacy file is not merged into it")
      assert_match(/#{Regexp.escape(LEGACY)}/, result.err,
        "reading one while the other sits there unread is a silent wrong answer unless it is said")
    end

    test "nearest still wins across directories, whichever name each carries" do
      root = project(LEGACY)
      nested = File.join(root, "sub")
      FileUtils.mkdir_p(nested)
      File.write(File.join(nested, SHORT), JSON.pretty_generate(
        "bundles" => [ { "slug" => "minimal", "path" => fixture("minimal"), "title" => "minimal" } ],
        "groups" => [], "links" => []
      ))

      result = in_dir(nested) { okf("registry", "list") }

      assert_match(/^\* minimal/, result.out, "the nearer file wins, and the two names are checked per directory")
      refute_match(/conformant/, result.out)
    end

    test "init writes the short name" do
      dir = File.join(@out_dir, "fresh")
      FileUtils.mkdir_p(dir)

      result = in_dir(dir) { okf("registry", "init") }

      assert_equal 0, result.status
      assert_equal "initialized ./#{SHORT}\n", result.out
      assert File.file?(File.join(dir, SHORT)), "init creates the name it now advertises"
    end

    test "init refuses when either name is already there" do
      legacy = project(LEGACY)

      result = in_dir(legacy) { okf("registry", "init") }

      assert_equal 2, result.status
      assert_match(/already initialized/, result.err)
      assert_match(/#{Regexp.escape(LEGACY)}/, result.err,
        "the refusal names the file that is in the way, which is the old one here")
      refute File.exist?(File.join(legacy, SHORT)), "a second registry beside the first is the trap, not the fix"
    end
  end
end
