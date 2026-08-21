# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf registry link` end-to-end — the global registry points at another registry
# file, and that file's bundles resolve through the pointer under their own slugs.
# Nothing is copied: the target keeps owning its rows, so a change there shows
# here on the next read.
#
# Links are the global registry's alone, which is what makes depth one structural
# — a linked file's own links are never read.
module ByRegistry
  class CLIRegistryLinkTest < CLIIntegrationCase
    LOCAL = ".okf-registry.json"

    # A registry file at @out_dir/<name>.json listing the named fixtures.
    def target(name, slugs)
      path = File.join(@out_dir, "#{name}.json")
      File.write(path, JSON.pretty_generate(
        "bundles" => slugs.map { |slug| { "slug" => slug, "path" => fixture(slug), "title" => slug } },
        "groups" => []
      ))
      path
    end

    test "link reports what it pointed at, and the bundles resolve under their own slugs" do
      file = target("onm", %w[conformant minimal])

      result = okf("registry", "link", "onm", file)

      assert_equal 0, result.status
      assert_equal "linked onm → #{file} (2 bundles)\n", result.out
      listed = okf("registry", "list").out
      assert_match(/^links:$/, listed)
      assert_match(/^  onm +→ #{Regexp.escape(file)}/, listed)
      assert_match(/conformant/, listed)
    end

    test "a linked bundle is addressable as an @slug by every verb" do
      okf("registry", "link", "onm", target("onm", %w[conformant]))

      assert_equal 0, okf("validate", "@conformant").status
    end

    test "the link name resolves as a group over its bundles" do
      okf("registry", "link", "onm", target("onm", %w[conformant minimal]))

      result = okf("search", "@onm", "orders")

      assert_equal 0, result.status
      # search fans a group out and labels each leaf by its own slug, so the
      # group name shows in the header rather than on the rows.
      assert_match(/^Search — @conformant @minimal/, result.out)
    end

    test "@all spans linked bundles" do
      okf("registry", "set", fixture("minimal"))
      okf("registry", "link", "onm", target("onm", %w[conformant]))

      assert_match(/@conformant/, okf("search", "@all", "orders").out)
    end

    test "a linked slug colliding with a local one is prefixed, and the list says so" do
      okf("registry", "set", fixture("conformant"))
      okf("registry", "link", "onm", target("onm", %w[conformant]))

      listed = okf("registry", "list").out

      assert_match(/^\* conformant/, listed, "the local bundle keeps the bare name and stays the default")
      assert_match(/onm-conformant .*\[conformant\]/, listed, "the moved name is visible, with the slug it had")
    end

    test "a write aimed at a linked bundle is refused, naming the file that owns it" do
      file = target("onm", %w[conformant])
      okf("registry", "link", "onm", file)

      result = okf("registry", "rename", "@conformant", "core")

      assert_equal 2, result.status
      assert_match(/linked registry at #{Regexp.escape(file)}/, result.err)
      assert_match(/okf registry unlink onm/, result.err)
    end

    test "unlink drops the link and every bundle that arrived through it" do
      okf("registry", "link", "onm", target("onm", %w[conformant]))

      result = okf("registry", "unlink", "onm")

      assert_equal 0, result.status
      assert_equal "unlinked onm\n", result.out
      assert_match(/no bundles registered/, okf("registry", "list").out)
    end

    test "unlink refuses a name nothing is linked under (exit 2)" do
      result = okf("registry", "unlink", "nope")

      assert_equal 2, result.status
      assert_match(/no such link: nope/, result.err)
    end

    test "a link whose target is gone is listed missing, and the registry still works" do
      file = target("onm", %w[conformant])
      okf("registry", "set", fixture("minimal"))
      okf("registry", "link", "onm", file)
      File.unlink(file)

      listed = okf("registry", "list")

      assert_equal 0, listed.status, "one dead pointer must not take down the registry holding it"
      assert_match(/^\* minimal/, listed.out)
      assert_match(/\(missing\)/, listed.out)
    end

    test "link from a project-local registry is refused, pointing at -g" do
      dir = File.join(@out_dir, "proj")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, LOCAL), JSON.generate("bundles" => [], "groups" => []))
      file = target("onm", %w[conformant])

      result = in_dir(dir) { okf("registry", "link", "onm", file) }

      assert_equal 2, result.status
      assert_match(/links live in the global registry/, result.err)
      assert_match(/--global/, result.err)
    end

    test "link -g reaches the global registry from inside a local one's tree" do
      dir = File.join(@out_dir, "proj2")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, LOCAL), JSON.generate("bundles" => [], "groups" => []))
      file = target("onm", %w[conformant])

      result = in_dir(dir) { okf("registry", "link", "onm", file, "-g") }

      assert_equal 0, result.status
      global = JSON.parse(File.read(File.join(@home, "registry.json")))
      assert_equal [ "onm" ], global["links"].map { |row| row["slug"] }
    end

    test "--json carries the links, so a script sees them too" do
      file = target("onm", %w[conformant])
      okf("registry", "link", "onm", file)

      payload = json(okf("registry", "list", "--json"))

      assert_equal [ { "slug" => "onm", "registry" => file, "bundles" => 1,
                       "missing" => false, "unreadable" => false } ], payload["links"]
      assert_equal "onm", payload["bundles"].first["link"]
    end
  end
end
