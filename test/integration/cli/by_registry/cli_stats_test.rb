# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf stats` named through the registry — the bundle-level rollups, re-proven
# for the @ref identity. The narrowest surface of the six (no filters, no
# projection: --json and --pretty are the whole flag set), which makes it the
# cleanest place to pin the header and envelope a ref produces.
module ByRegistry
  # Bundles named by @ref — the registry form every read verb accepts.
  class CLIStatsTest < CLIIntegrationCase
    test "@slug reports the rollups and both breakdowns (exit 0)" do
      with_registry("conformant") do
        result = okf("stats", "@conformant")

        assert_equal 0, result.status
        assert_match(/^  concepts       3$/, result.out)
        assert_match(/^  dirs           2$/, result.out)
        assert_match(/^  concept types  2$/, result.out)
        assert_match(/^  cross-links    6$/, result.out)
        assert_match(/^  distinct tags  2$/, result.out)
        assert_match(/^  By type\n    BigQuery Table    2\n    BigQuery Dataset  1$/, result.out)
        assert_match(/^  By dir\n    tables    2\n    datasets  1$/, result.out)
        assert_equal okf("stats", fixture("conformant")).out.lines.drop(1), result.out.lines.drop(1),
          "naming a bundle by ref changes its header, never its content"
      end
    end

    # stats' header carries no count, so the ref identity is the whole line.
    test "the human header reads `@slug (/path)`" do
      with_registry("conformant") do
        assert_match(/^Stats — @conformant \(#{Regexp.escape(fixture("conformant"))}\)$/, okf("stats", "@conformant").out)
      end
    end

    test "--json carries both bundle (the directory) and slug (the registry name)" do
      with_registry("conformant") do
        data = json(okf("stats", "@conformant", "--json"))

        assert_equal fixture("conformant"), data.fetch("bundle"), "`bundle` is always the directory"
        assert_equal "conformant", data.fetch("slug"), "`slug` is only ever the registry slug"
        assert_equal %w[areas bundle by_area by_dir by_type concept_types concepts cross_links dirs distinct_tags slug], data.keys.sort,
          "a ref adds `slug` to the path form's keys, and nothing else"
        assert_equal 3, data.fetch("concepts")
        assert_equal 2, data.fetch("areas")
        assert_equal 2, data.fetch("concept_types") # `types` in the human view, `concept_types` here
        assert_equal 6, data.fetch("cross_links")
        assert_equal 2, data.fetch("distinct_tags")
        assert_equal({ "BigQuery Table" => 2, "BigQuery Dataset" => 1 }, data.fetch("by_type"))
        assert_equal({ "tables" => 2, "datasets" => 1 }, data.fetch("by_area"))
      end
    end

    test "bare @ resolves the registry default, and names it by the slug it landed on" do
      with_registry("conformant", "minimal") do
        assert_match(/^Stats — @conformant \(#{Regexp.escape(fixture("conformant"))}\)$/, okf("stats", "@").out)

        okf("registry", "default", "minimal")
        result = okf("stats", "@")

        assert_equal 0, result.status
        assert_match(/^Stats — @minimal \(#{Regexp.escape(fixture("minimal"))}\)$/, result.out,
          "bare @ follows the chosen default, and the header names the slug it resolved to")

        data = json(okf("stats", "@", "--json"))
        assert_equal "minimal", data.fetch("slug")
        assert_equal fixture("minimal"), data.fetch("bundle")
        assert_equal 1, data.fetch("concepts")
      end
    end

    test "@One resolves the way registration slugified it" do
      with_registry do
        okf("registry", "set", fixture("conformant"), "--as", "One")

        data = json(okf("stats", "@One", "--json"))

        assert_equal fixture("conformant"), data.fetch("bundle")
        assert_equal "one", data.fetch("slug")
        assert_equal 3, data.fetch("concepts")
        assert_match(/^Stats — @one \(/, okf("stats", "@One").out, "the header answers with the registered slug, not the spelling asked for")
      end
    end

    test "--pretty implies --json and indents it, slug and all" do
      with_registry("minimal") do
        result = okf("stats", "@minimal", "--pretty")

        assert_equal 1, JSON.parse(result.out).fetch("concepts") # still JSON, no --json needed
        assert_match(/^\{\n  "bundle": /, result.out)
        assert_match(/^  "slug": "minimal",$/, result.out)
        assert_match(/^  "concepts": 1,$/, result.out)
        assert_match(/^  "by_type": \{\n    "Note": 1\n  \},$/, result.out)
        refute_match(/\n  "concepts"/, okf("stats", "@minimal", "--json").out) # compact by default
      end
    end

    test "the counts track the bundle behind the ref: a one-concept bundle links nothing" do
      with_registry("minimal") do
        data = json(okf("stats", "@minimal", "--json"))

        assert_equal 1, data.fetch("concepts")
        assert_equal 0, data.fetch("cross_links")
        assert_equal 0, data.fetch("distinct_tags")
        assert_equal({ "(root)" => 1 }, data.fetch("by_area"))
      end
    end

    test "an empty registered bundle is all zeroes, with no breakdowns and no crash" do
      with_registry("empty") do
        result = okf("stats", "@empty")

        assert_equal 0, result.status
        assert_match(/^Stats — @empty \(#{Regexp.escape(fixture("empty"))}\)$/, result.out)
        assert_match(/^  concepts       0$/, result.out)
        assert_match(/^  cross-links    0$/, result.out)
        refute_match(/By type/, result.out) # an empty breakdown prints nothing, not an empty heading
        refute_match(/By area/, result.out)

        data = json(okf("stats", "@empty", "--json"))
        assert_equal "empty", data.fetch("slug")
        assert_equal 0, data.fetch("concepts")
        assert_equal({}, data.fetch("by_type"))
        assert_equal({}, data.fetch("by_area"))
      end
    end

    test "an unknown slug is a usage error naming the registry file it consulted (exit 2)" do
      with_registry("conformant") do
        result = okf("stats", "@nope")

        assert_equal 2, result.status
        assert_match(/^error: not a registered bundle: @nope in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry list\)$/, result.err)
        assert_equal "", result.out
        refute_match(/\.rb:\d+/, result.err, "a bad ref is a message, never a backtrace")
      end
    end

    # Nothing survives normalization, so there is no slug to look up — and no
    # mint-a-name placeholder to fall back on either.
    test "a ref that normalizes to nothing is a bad ref, not a lookup of the placeholder (exit 2)" do
      with_registry("conformant") do
        result = okf("stats", "@***")

        assert_equal 2, result.status
        assert_match(/^error: not a registered bundle: @\*\*\* in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry list\)$/, result.err)
      end
    end

    test "a registered-but-gone directory is a usage error naming the next move (exit 2)" do
      with_registry("conformant") do
        gone = register_vanished("doomed")

        result = okf("stats", "@doomed")

        assert_equal 2, result.status
        assert_match(/^error: @doomed points to #{Regexp.escape(gone)}, which is not a directory \(okf registry del doomed, or restore it\)$/, result.err)
        assert_equal "", result.out
      end
    end

    test "bare @ against an empty registry hints `okf registry set`" do
      with_registry do
        result = okf("stats", "@")

        assert_equal 2, result.status
        assert_match(/^error: not a registered bundle: @ in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry set <dir>\)$/, result.err,
          "with nothing registered the hint is to register, not to list")
        assert_equal "", result.out
      end
    end

    test "the read views' filters are not on offer — stats rolls up the whole bundle (exit 2)" do
      with_registry("conformant") do
        filtered = okf("stats", "@conformant", "--type", "BigQuery Table")

        assert_equal 2, filtered.status
        assert_match(/invalid option: --type/, filtered.err)
        assert_equal "", filtered.out
      end
    end

    test "a second bundle is a usage error — stats answers about one (exit 2)" do
      with_registry("conformant", "minimal") do
        result = okf("stats", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_match(/^error: unexpected argument '@minimal'$/, result.err)
        assert_equal "", result.out
      end
    end

    test "best-effort read through a ref: malformed files are skipped (stderr), stdout stays parseable JSON" do
      with_registry("malformed") do
        result = okf("stats", "@malformed", "--json")

        assert_equal 0, result.status, "a bundle full of §9 errors still rolls up — this is an advisory read, never exit 1"
        assert_match(/skipped 2 unusable file\(s\)/, result.err)
        data = json(result)
        assert_equal 3, data.fetch("concepts") # the three that parse still count
        assert_equal({ "(root)" => 3 }, data.fetch("by_area"))
        assert_equal "malformed", data.fetch("slug")
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
