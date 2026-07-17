# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf loose` named through the registry — the folder-grouped view of degree-0
# concepts, re-proven for the @ref identity. Like `stats`, its whole flag set is
# --json/--pretty; unlike it, the view is a list, so the ref envelope has to
# survive next to a `loose` array whose ids resolve under `bundle`.
module ByRegistry
  # Bundles named by @ref — the registry form every read verb accepts.
  class CLILooseTest < CLIIntegrationCase
    test "@slug lists a floating concept grouped under its folder (exit 0)" do
      with_registry("minimal") do
        result = okf("loose", "@minimal")

        assert_equal 0, result.status
        assert_match(/^ {2}\(root\)\n {4}note\.md {2}Only Note$/, result.out)
        assert_equal okf("loose", fixture("minimal")).out.lines.drop(1), result.out.lines.drop(1),
          "naming a bundle by ref changes its header, never its content"
      end
    end

    test "the human header reads `@slug (/path)`, with the count after it" do
      with_registry("minimal") do
        assert_match(/^Loose files — @minimal \(#{Regexp.escape(fixture("minimal"))}\) \(1\)$/, okf("loose", "@minimal").out)
      end
    end

    test "--json carries both bundle (the directory) and slug (the registry name)" do
      with_registry("minimal") do
        data = json(okf("loose", "@minimal", "--json"))

        assert_equal fixture("minimal"), data.fetch("bundle"), "`bundle` is always the directory"
        assert_equal "minimal", data.fetch("slug"), "`slug` is only ever the registry slug"
        assert_equal 1, data.fetch("count")
        assert_equal %w[dir id title], data.fetch("loose").first.keys.sort
        assert_equal "note", data.fetch("loose").first.fetch("id"),
          "the row's id resolves to <bundle>/<id>.md — the envelope just named the directory"
      end
    end

    test "bare @ resolves the registry default, and names it by the slug it landed on" do
      with_registry("conformant", "minimal") do
        # conformant is the effective default until one is chosen — and every one
        # of its concepts is linked.
        assert_match(/^Loose files — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(0\)$/, okf("loose", "@").out)

        okf("registry", "default", "minimal")
        result = okf("loose", "@")

        assert_equal 0, result.status
        assert_match(/^Loose files — @minimal \(#{Regexp.escape(fixture("minimal"))}\) \(1\)$/, result.out,
          "bare @ follows the chosen default, and the header names the slug it resolved to")
        assert_equal "minimal", json(okf("loose", "@", "--json")).fetch("slug")
      end
    end

    test "@One resolves the way registration slugified it" do
      with_registry do
        okf("registry", "set", fixture("minimal"), "--as", "One")

        data = json(okf("loose", "@One", "--json"))

        assert_equal fixture("minimal"), data.fetch("bundle")
        assert_equal "one", data.fetch("slug")
        assert_match(/^Loose files — @one \(/, okf("loose", "@One").out, "the header answers with the registered slug, not the spelling asked for")
      end
    end

    test "--pretty implies --json and indents it, slug and all" do
      with_registry("minimal") do
        result = okf("loose", "@minimal", "--pretty")

        assert_equal 1, JSON.parse(result.out).fetch("count") # implies --json
        assert_match(/^\{\n  "bundle": /, result.out)         # …and indents it
        assert_match(/^  "slug": "minimal",$/, result.out)
        assert_match(/^\{"bundle".*"slug":"minimal"/, okf("loose", "@minimal", "--json").out) # compact without it
      end
    end

    test "a ref whose every concept is linked reports none, and still names itself (exit 0)" do
      with_registry("conformant") do
        result = okf("loose", "@conformant")

        assert_equal 0, result.status
        assert_match(/^Loose files — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(0\)$/, result.out)
        assert_match(/none — every concept links or is linked/, result.out)

        data = json(okf("loose", "@conformant", "--json"))
        assert_equal 0, data.fetch("count")
        assert_equal [], data.fetch("loose")
        assert_equal "conformant", data.fetch("slug"), "an empty answer still carries the identity it was asked in"
      end
    end

    test "a curation-failing bundle is still an advisory read: loose reports, never exit 1" do
      with_registry("unhealthy") do
        result = okf("loose", "@unhealthy")

        assert_equal 0, result.status
        assert_match(/^Loose files — @unhealthy \(#{Regexp.escape(fixture("unhealthy"))}\) \(1\)$/, result.out)
        assert_match(/stub\.md {2}Stub/, result.out)
        assert_equal [ "stub" ], json(okf("loose", "@unhealthy", "--json")).fetch("loose").map { |row| row.fetch("id") }
      end
    end

    test "an empty registered bundle has nothing loose, not a crash" do
      with_registry("empty") do
        result = okf("loose", "@empty")

        assert_equal 0, result.status
        assert_match(/^Loose files — @empty \(#{Regexp.escape(fixture("empty"))}\) \(0\)$/, result.out)
        assert_equal [], json(okf("loose", "@empty", "--json")).fetch("loose")
      end
    end

    test "an unknown slug is a usage error naming the registry file it consulted (exit 2)" do
      with_registry("minimal") do
        result = okf("loose", "@nope")

        assert_equal 2, result.status
        assert_match(/^error: not a registered bundle: @nope in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry list\)$/, result.err)
        assert_equal "", result.out
        refute_match(/\.rb:\d+/, result.err, "a bad ref is a message, never a backtrace")
      end
    end

    test "a registered-but-gone directory is a usage error naming the next move (exit 2)" do
      with_registry("minimal") do
        gone = register_vanished("doomed")

        result = okf("loose", "@doomed")

        assert_equal 2, result.status
        assert_match(/^error: @doomed points to #{Regexp.escape(gone)}, which is not a directory \(okf registry del doomed, or restore it\)$/, result.err)
        assert_equal "", result.out
      end
    end

    test "bare @ against an empty registry hints `okf registry set`" do
      with_registry do
        result = okf("loose", "@")

        assert_equal 2, result.status
        assert_match(/^error: not a registered bundle: @ in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry set <dir>\)$/, result.err)
        assert_equal "", result.out
      end
    end

    test "the read views' filters and projections are not on offer (exit 2)" do
      with_registry("minimal") do
        assert_match(/invalid option: --type/, okf("loose", "@minimal", "--type", "Note").err)
        assert_match(/invalid option: --fields/, okf("loose", "@minimal", "--fields", "id").err)
        assert_equal 2, okf("loose", "@minimal", "--type", "Note").status
        assert_equal 2, okf("loose", "@minimal", "--fields", "id").status
      end
    end

    test "a second bundle is a usage error — loose answers about one (exit 2)" do
      with_registry("conformant", "minimal") do
        result = okf("loose", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_match(/^error: unexpected argument '@minimal'$/, result.err)
        assert_equal "", result.out
      end
    end

    test "best-effort read through a ref: malformed files are skipped (stderr), not fatal" do
      with_registry("malformed") do
        result = okf("loose", "@malformed", "--json")

        assert_equal 0, result.status
        assert_match(/skipped 2 unusable file\(s\)/, result.err)
        assert_equal %w[blank-type good no-type], json(result).fetch("loose").map { |row| row.fetch("id") },
          "the three that parse are all degree-0, and all report"
        assert_equal "malformed", json(result).fetch("slug")
        refute_match(/note:/, result.out)
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
