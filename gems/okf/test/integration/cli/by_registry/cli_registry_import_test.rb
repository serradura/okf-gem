# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf registry import` end-to-end — copy chosen bundles out of another registry
# file and into this one, where they become yours.
#
# It is the counterpart to `registry link`, not a variant of it: a link is live,
# whole-file and read-only, which is the right shape for composing a repository's
# own curation and the wrong one for "I want that one bundle, here". An import
# copies the path and hands over ownership, so `rename`, `default` and `group`
# all work on what lands.
#
# `-g` keeps the meaning it has on every sibling subcommand — the registry being
# written *to*. The one being read *from* is `--from`, defaulting to the global
# registry, which inside a repo is the only other one you have.
module ByRegistry
  class CLIRegistryImportTest < CLIIntegrationCase
    LOCAL = ".okf.json"

    # A project directory carrying an empty local registry, which discovery finds
    # and every command run under `in_dir` then targets.
    def project(name = "proj")
      dir = File.join(@out_dir, name)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, LOCAL), JSON.pretty_generate("bundles" => [], "groups" => [], "links" => []))
      dir
    end

    # A registry file at @out_dir/<name>.json listing the named fixtures, plus
    # any groups given. The shape `--from` is pointed at.
    def source(name, slugs, groups = [])
      path = File.join(@out_dir, "#{name}.json")
      File.write(path, JSON.pretty_generate(
        "bundles" => slugs.map { |slug| { "slug" => slug, "path" => fixture(slug), "title" => slug } },
        "groups" => groups, "links" => []
      ))
      path
    end

    def local_json(dir)
      JSON.parse(File.read(File.join(dir, LOCAL)))
    end

    test "import takes a bundle from the global registry into the local one, under its own slug" do
      okf("registry", "set", fixture("conformant"))
      dir = project

      result = in_dir(dir) { okf("registry", "import", "conformant") }

      assert_equal 0, result.status
      assert_match(/^imported 1 bundle from /, result.out)
      assert_match(/^\s+conformant → #{Regexp.escape(fixture("conformant"))} \(\d+ concepts?\)$/, result.out)
      assert_equal %w[conformant], local_json(dir)["bundles"].map { |row| row["slug"] },
        "the slug it had in the source is the slug it answers to here"
    end

    test "an imported bundle is owned here — it renames, defaults and groups" do
      okf("registry", "set", fixture("conformant"))
      dir = project

      in_dir(dir) do
        okf("registry", "import", "conformant")
        assert_equal 0, okf("registry", "rename", "@conformant", "core").status,
          "an import copies; nothing about it is read-only, which is the whole difference from a link"
      end

      assert_equal %w[core], local_json(dir)["bundles"].map { |row| row["slug"] }
    end

    test "several slugs come in one call" do
      okf("registry", "set", fixture("conformant"))
      okf("registry", "set", fixture("minimal"))
      dir = project

      result = in_dir(dir) { okf("registry", "import", "conformant", "minimal") }

      assert_equal 0, result.status
      assert_match(/^imported 2 bundles from /, result.out)
      assert_equal %w[conformant minimal], local_json(dir)["bundles"].map { |row| row["slug"] }
    end

    test "a leading @ is accepted, the way del and rename accept it" do
      okf("registry", "set", fixture("conformant"))
      dir = project

      result = in_dir(dir) { okf("registry", "import", "@conformant") }

      assert_equal 0, result.status
      assert_equal %w[conformant], local_json(dir)["bundles"].map { |row| row["slug"] }
    end

    test "a group ask brings its members and is recreated here" do
      file = source("onm", %w[conformant minimal],
        [ { "slug" => "conf", "members" => %w[conformant minimal] } ])
      dir = project

      result = in_dir(dir) { okf("registry", "import", "conf", "--from", file) }

      assert_equal 0, result.status
      assert_match(/^\s+conf → @conformant, @minimal \(group\)$/, result.out)
      assert_equal %w[conformant minimal], local_json(dir)["bundles"].map { |row| row["slug"] },
        "a group is worth importing only if its members come with it"
      assert_equal [ { "slug" => "conf", "members" => %w[conformant minimal] } ], local_json(dir)["groups"]
    end

    test "a group whose member is another group pulls that one in too" do
      file = source("onm", %w[conformant minimal],
        [ { "slug" => "inner", "members" => %w[minimal] },
          { "slug" => "outer", "members" => %w[conformant inner] } ])
      dir = project

      result = in_dir(dir) { okf("registry", "import", "outer", "--from", file) }

      assert_equal 0, result.status
      assert_equal %w[inner outer], local_json(dir)["groups"].map { |row| row["slug"] }.sort,
        "an imported group that quietly lost a member is curation silently degraded"
      assert_equal %w[conformant minimal], local_json(dir)["bundles"].map { |row| row["slug"] }.sort
    end

    test "--as renames a single ask on the way in" do
      okf("registry", "set", fixture("conformant"))
      dir = project

      result = in_dir(dir) { okf("registry", "import", "conformant", "--as", "handbook") }

      assert_equal 0, result.status
      assert_equal %w[handbook], local_json(dir)["bundles"].map { |row| row["slug"] }
    end

    test "--as with two asks is a usage error — it names one thing" do
      okf("registry", "set", fixture("conformant"))
      okf("registry", "set", fixture("minimal"))
      dir = project

      result = in_dir(dir) { okf("registry", "import", "conformant", "minimal", "--as", "both") }

      assert_equal 2, result.status
      assert_match(/--as names one bundle/, result.err)
      assert_empty local_json(dir)["bundles"], "a refused import writes nothing"
    end

    test "a slug already taken here refuses, and names the move" do
      okf("registry", "set", fixture("conformant"))
      dir = project
      # A *different* bundle already holding the name. Registering the same path
      # would trip the earlier refusal below instead, which is a different answer.
      in_dir(dir) { okf("registry", "set", fixture("minimal"), "--as", "conformant") }
      before = File.read(File.join(dir, LOCAL))

      result = in_dir(dir) { okf("registry", "import", "conformant") }

      assert_equal 2, result.status
      assert_match(/slug already taken: conformant/, result.err)
      assert_match(/--as/, result.err, "a refusal with no way forward is a dead end")
      assert_equal before, File.read(File.join(dir, LOCAL)), "and it is byte-for-byte untouched"
    end

    test "a bundle already registered here under another name refuses, naming that name" do
      okf("registry", "set", fixture("conformant"))
      dir = project
      in_dir(dir) { okf("registry", "set", fixture("conformant"), "--as", "core") }

      result = in_dir(dir) { okf("registry", "import", "conformant") }

      assert_equal 2, result.status
      assert_match(/already registered here as core/, result.err,
        "what the row is comes before what it wants to be called — renaming your entry to the source's " \
        "name would be the substitution the slug rule forbids, and skipping it would report an import " \
        "that did not happen")
    end

    test "one bad ask refuses the whole import — nothing is half-applied" do
      okf("registry", "set", fixture("conformant"))
      dir = project

      result = in_dir(dir) { okf("registry", "import", "conformant", "nosuch") }

      assert_equal 2, result.status
      assert_match(/nosuch/, result.err)
      assert_empty local_json(dir)["bundles"],
        "conformant was importable; validating every ask before writing any is what keeps it out"
    end

    test "an ask that is not a usable slug refuses rather than being dropped" do
      okf("registry", "set", fixture("conformant"))
      dir = project

      result = in_dir(dir) { okf("registry", "import", "conformant", "@@@") }

      assert_equal 2, result.status
      assert_match(/not a usable slug: @@@/, result.err)
      assert_empty local_json(dir)["bundles"],
        "normalizing an unusable ask to nothing and importing the rest would be a silent partial, " \
        "which is the one thing all-or-nothing promises not to be"
    end

    test "importing from the registry you are writing to is refused" do
      okf("registry", "set", fixture("conformant"))

      result = okf("registry", "import", "conformant")

      assert_equal 2, result.status
      assert_match(/same registry/, result.err,
        "with no local registry in force the default source is also the target, and that is a no-op worth naming")
    end

    test "a bundle outside the local tree lands absolute; one inside lands relative" do
      # Dir.pwd canonicalizes symlinks (on macOS /var → /private/var) and the
      # discovered registry's anchor is canonical with it, so the source has to
      # name the same form or nothing relates to anything.
      dir = File.realpath(project)
      inside = File.join(dir, "docs")
      FileUtils.mkdir_p(inside)
      File.write(File.join(inside, "note.md"), "---\ntype: Note\ntitle: Inside\n---\n\nA concept.\n")
      file = source("mixed", [])
      File.write(file, JSON.pretty_generate(
        "bundles" => [ { "slug" => "outside", "path" => fixture("conformant"), "title" => "outside" },
                       { "slug" => "inside", "path" => inside, "title" => "inside" } ],
        "groups" => [], "links" => []
      ))

      in_dir(dir) { okf("registry", "import", "outside", "inside", "--from", file) }

      stored = local_json(dir)["bundles"].each_with_object({}) { |row, acc| acc[row["slug"]] = row["path"] }
      assert_equal "docs", stored["inside"], "an in-tree bundle is stored relative, so the file travels with the repo"
      assert stored["outside"].start_with?("/"),
        "a path that would climb out of the tree stays absolute — it cannot be re-anchored anywhere useful"
    end

    test "-g imports into the global registry, from the local one" do
      dir = project
      in_dir(dir) { okf("registry", "set", fixture("conformant")) }

      result = in_dir(dir) { okf("registry", "import", "conformant", "--from", LOCAL, "-g") }

      assert_equal 0, result.status
      global = JSON.parse(File.read(File.join(@home, "registry.json")))
      assert_equal %w[conformant], global["bundles"].map { |row| row["slug"] },
        "-g goes on meaning the registry written to; --from is the one read"
    end

    test "a --from that is not a registry file is refused at the keyboard" do
      dir = project

      result = in_dir(dir) { okf("registry", "import", "conformant", "--from", File.join(@out_dir, "nope.json")) }

      assert_equal 2, result.status
      assert_match(/not a registry file/, result.err)
    end
  end
end
