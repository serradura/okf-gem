# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf files` named through the registry — the file tree (every concept as a
# path under the folder it lives in), re-proven for the @ref identity: every
# filter and projection reached via `@slug` or bare `@`, the header reading
# `@slug (/path)`, and the JSON carrying both `bundle` and `slug` so a row's
# `path` resolves under the directory without a second lookup.
module ByRegistry
  # Bundles named by @ref — the registry form every read verb accepts.
  class CLIFilesTest < CLIIntegrationCase
    test "@slug lists filenames under their folder, exactly as the path form does (exit 0)" do
      with_registry("conformant") do
        result = okf("files", "@conformant")

        assert_equal 0, result.status
        assert_match(/datasets\/\n {4}sales\.md {2}Sales/, result.out)
        assert_match(/tables\/\n {4}customers\.md {2}Customers\n {4}orders\.md {5}Orders/, result.out)
        assert_equal okf("files", fixture("conformant")).out.lines.drop(1), result.out.lines.drop(1),
          "naming a bundle by ref changes its header, never its content"
      end
    end

    test "the human header reads `@slug (/path)`" do
      with_registry("conformant") do
        assert_match(/^Files — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(3 files\)$/, okf("files", "@conformant").out)
      end
    end

    test "--json carries both bundle (the directory) and slug (the registry name)" do
      with_registry("conformant") do
        data = json(okf("files", "@conformant", "--json"))

        assert_equal fixture("conformant"), data.fetch("bundle"), "`bundle` is always the directory"
        assert_equal "conformant", data.fetch("slug"), "`slug` is only ever the registry slug"
        assert_equal 3, data.fetch("count")
        assert_equal %w[path id dir type title description], data.fetch("files").first.keys
        assert_equal "datasets/sales.md", data.fetch("files").first.fetch("path"),
          "the row's path is relative to `bundle`, which the envelope just named"
      end
    end

    test "bare @ resolves the registry default, and names it by the slug it landed on" do
      with_registry("conformant", "minimal") do
        assert_match(/^Files — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(3 files\)$/, okf("files", "@").out)

        okf("registry", "default", "minimal")
        result = okf("files", "@")

        assert_equal 0, result.status
        assert_match(/^Files — @minimal \(#{Regexp.escape(fixture("minimal"))}\) \(1 file\)$/, result.out,
          "bare @ follows the chosen default, and the header names the slug it resolved to")
        assert_equal "minimal", json(okf("files", "@", "--json")).fetch("slug")
        assert_equal "note.md", json(okf("files", "@", "--json")).fetch("files").first.fetch("path")
      end
    end

    test "@One resolves the way registration slugified it" do
      with_registry do
        okf("registry", "set", fixture("minimal"), "--as", "One")

        data = json(okf("files", "@One", "--json"))

        assert_equal fixture("minimal"), data.fetch("bundle")
        assert_equal "one", data.fetch("slug")
        assert_match(/^Files — @one \(/, okf("files", "@One").out, "the header answers with the registered slug, not the spelling asked for")
      end
    end

    test "--pretty implies --json and indents it, slug and all" do
      with_registry("minimal") do
        result = okf("files", "@minimal", "--pretty")

        assert_equal "note.md", JSON.parse(result.out).fetch("files").first.fetch("path") # implies --json
        assert_match(/^\{\n  "bundle": /, result.out)                                     # …and indents it
        assert_match(/^  "slug": "minimal",$/, result.out)
        assert_match(/^\{"bundle".*"slug":"minimal"/, okf("files", "@minimal", "--json").out) # compact without it
      end
    end

    test "--fields keeps only the named properties; the ref envelope survives the projection" do
      with_registry("conformant") do
        data = json(okf("files", "@conformant", "--fields", "path,title"))

        assert_equal %w[path title], data.fetch("files").first.keys
        assert_equal "Sales", data.fetch("files").first.fetch("title")
        assert_equal "conformant", data.fetch("slug"), "the projection cuts rows, never the identity envelope"
        assert_equal fixture("conformant"), data.fetch("bundle")
        assert_equal 3, data.fetch("count")
      end
    end

    test "--except drops the named properties and keeps the envelope whole" do
      with_registry("conformant") do
        data = json(okf("files", "@conformant", "--except", "description,type"))

        assert_equal %w[path id dir title], data.fetch("files").first.keys
        refute data.fetch("files").first.key?("description")
        assert_equal "conformant", data.fetch("slug")
      end
    end

    test "field names match case-insensitively through a ref too" do
      with_registry("conformant") do
        assert_equal %w[path title], json(okf("files", "@conformant", "--fields", "PATH,Title")).fetch("files").first.keys
      end
    end

    test "--fields and --except are mutually exclusive (exit 2)" do
      with_registry("conformant") do
        result = okf("files", "@conformant", "--fields", "path", "--except", "title")

        assert_equal 2, result.status
        assert_match(/mutually exclusive/, result.err)
      end
    end

    test "an unknown field is a usage error naming the valid ones (exit 2)" do
      with_registry("conformant") do
        result = okf("files", "@conformant", "--fields", "bogus")

        assert_equal 2, result.status
        assert_match(/unknown field\(s\): bogus/, result.err)
        assert_match(/available: path, id, dir, type, title, description/, result.err)
        assert_equal "", result.out
        assert_equal 2, okf("files", "@conformant", "--except", "nope").status # --except too
      end
    end

    test "--type selects one concept type, case-insensitively, and the header counts the narrowing" do
      with_registry("conformant") do
        result = okf("files", "@conformant", "--type", "BigQuery Dataset")

        assert_equal 0, result.status
        assert_match(/^Files — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(1 of 3 files\)$/, result.out)
        assert_match(/sales\.md {2}Sales/, result.out)
        refute_match(/customers\.md/, result.out)

        folded = json(okf("files", "@conformant", "--type", "bigquery dataset", "--json"))
        assert_equal [ "datasets/sales.md" ], folded.fetch("files").map { |row| row["path"] }
        assert_equal "conformant", folded.fetch("slug"), "a filtered view keeps the identity contract"
      end
    end

    test "--area selects a top-level area, case-insensitively, and takes `root`" do
      with_registry("conformant", "edge-cases") do
        data = json(okf("files", "@conformant", "--area", "TABLES", "--json"))
        assert_equal %w[tables/customers.md tables/orders.md], data.fetch("files").map { |row| row["path"] }

        # --area is the top-level area, so it reaches a file nested below it; the
        # row's own `dir` stays the folder on disk.
        nested = json(okf("files", "@edge-cases", "--area", "deeply", "--json"))
        assert_equal [ "deeply/nested/path/concept.md" ], nested.fetch("files").map { |row| row["path"] }
        assert_equal "deeply/nested/path", nested.fetch("files").first.fetch("dir")

        rooted = json(okf("files", "@edge-cases", "--area", "root", "--json"))
        assert_equal 3, rooted.fetch("count")
        assert_equal "edge-cases", rooted.fetch("slug")
      end
    end

    test "--dir selects a directory and its subtree through a ref" do
      with_registry("conformant", "edge-cases") do
        data = json(okf("files", "@conformant", "--dir", "TABLES", "--json"))
        assert_equal %w[tables/customers.md tables/orders.md], data.fetch("files").map { |row| row["path"] }

        nested = json(okf("files", "@edge-cases", "--dir", "deeply/nested", "--json"))
        assert_equal [ "deeply/nested/path/concept.md" ], nested.fetch("files").map { |row| row["path"] }

        rooted = json(okf("files", "@edge-cases", "--dir", "root", "--json"))
        assert_equal 3, rooted.fetch("count")
        assert_equal "edge-cases", rooted.fetch("slug")
      end
    end

    test "--area still selects through a ref, and warns on stderr" do
      with_registry("conformant") do
        result = okf("files", "@conformant", "--area", "tables", "--json")

        assert_equal "warning: --area is deprecated, use --dir\n", result.err
        assert_equal 2, json(result).fetch("count")
      end
    end

    test "--tag selects concepts carrying a tag, case-insensitively" do
      with_registry("conformant") do
        data = json(okf("files", "@conformant", "--tag", "ORDERS", "--json"))

        assert_equal 1, data.fetch("count")
        assert_equal "tables/orders.md", data.fetch("files").first.fetch("path")
        refute data.fetch("files").first.key?("tags"), "--tag narrows over the catalog behind the view, not over the row"
      end
    end

    test "a filter composes with a projection under a ref" do
      with_registry("conformant") do
        data = json(okf("files", "@conformant", "--area", "tables", "--fields", "path"))

        assert_equal [ { "path" => "tables/customers.md" }, { "path" => "tables/orders.md" } ], data.fetch("files")
        assert_equal "conformant", data.fetch("slug")
      end
    end

    test "a filter matching nothing is an empty list, not an error (exit 0)" do
      with_registry("conformant") do
        result = okf("files", "@conformant", "--tag", "nosuchtag", "--json")

        assert_equal 0, result.status
        assert_equal 0, json(result).fetch("count")
        assert_equal [], json(result).fetch("files")
        assert_match(/\(0 of 3 files\)/, okf("files", "@conformant", "--tag", "nosuchtag").out)
      end
    end

    test "an unknown slug is a usage error naming the registry file it consulted (exit 2)" do
      with_registry("conformant") do
        result = okf("files", "@nope")

        assert_equal 2, result.status
        assert_match(/^error: not a registered bundle: @nope in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry list\)$/, result.err)
        assert_equal "", result.out
        refute_match(/\.rb:\d+/, result.err, "a bad ref is a message, never a backtrace")
      end
    end

    test "a registered-but-gone directory is a usage error naming the next move (exit 2)" do
      with_registry("conformant") do
        gone = register_vanished("doomed")

        result = okf("files", "@doomed")

        assert_equal 2, result.status
        assert_match(/^error: @doomed points to #{Regexp.escape(gone)}, which is not a directory \(okf registry del doomed, or restore it\)$/, result.err)
        assert_equal "", result.out
      end
    end

    test "bare @ against an empty registry hints `okf registry set`" do
      with_registry do
        result = okf("files", "@")

        assert_equal 2, result.status
        assert_match(/^error: not a registered bundle: @ in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry set <dir>\)$/, result.err)
      end
    end

    test "a second bundle is a usage error — files answers about one (exit 2)" do
      with_registry("conformant", "minimal") do
        result = okf("files", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_match(/^error: unexpected argument '@minimal'$/, result.err)
        assert_equal "", result.out
      end
    end

    test "best-effort read through a ref: malformed files are skipped (stderr), stdout stays valid" do
      with_registry("malformed") do
        result = okf("files", "@malformed")
        assert_equal 0, result.status, "a bundle full of §9 errors still lists — this is an advisory read, never exit 1"
        assert_match(/skipped 2 unusable file\(s\)/, result.err)
        assert_match(/good\.md {8}Good/, result.out)

        machine = okf("files", "@malformed", "--json")
        assert_equal %w[blank-type.md good.md no-type.md], json(machine).fetch("files").map { |row| row["path"] }
        assert_equal "malformed", json(machine).fetch("slug")
      end
    end

    test "an empty registered bundle lists zero files, not a crash" do
      with_registry("empty") do
        result = okf("files", "@empty")

        assert_equal 0, result.status
        assert_match(/^Files — @empty \(#{Regexp.escape(fixture("empty"))}\) \(0 files\)$/, result.out)
        assert_equal [], json(okf("files", "@empty", "--json")).fetch("files")
      end
    end

    private

    # Register a scratch bundle, then delete its directory: the "registered but
    # gone" ref no committed fixture can carry (a fixture is always on disk).
    # Returns the path that went away.
    def register_vanished(slug)
      dir = File.join(@out_dir, slug)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "note.md"), "---\ntype: Note\ntitle: Doomed\n---\n\nA concept about to lose its directory.\n")
      okf("registry", "set", dir)
      FileUtils.rm_rf(dir)
      dir
    end
  end
end
