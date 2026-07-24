# frozen_string_literal: true

require_relative "../cli_integration_case"
require "okf/render/graph"

# `okf render` named through the registry. The verb a ref changes least: it takes
# a `@slug` like every other, and then never mentions it — the page is titled from
# the *directory*, and the -o confirmation names the file. That silence is the
# contract this file pins, alongside every flag driven at a ref.
module ByRegistry
  # Bundles named by @ref — the identity form the registry gives.
  class CLIRenderTest < CLIIntegrationCase
    test "@slug renders the registered bundle, and the page names the directory" do
      with_registry("conformant") do
        result = okf("render", "@conformant")

        assert_equal 0, result.status
        assert_empty result.err
        assert_match(/\A<!doctype html><html lang="en">/, result.out)
        assert_match(/const EMBED=\{"catalog":/, result.out, "the whole bundle is baked in")
        assert_match(/<title>OKF · fixtures\/conformant<\/title>/, result.out,
          "the default title is the parent/bundle dir name — a ref does not retitle the page")
        refute_match(/@conformant/, result.out, "render echoes the ref nowhere at all")
      end
    end

    test "a ref and its path render the same page, byte for byte" do
      with_registry("conformant") do
        assert_equal okf("render", fixture("conformant")).out, okf("render", "@conformant").out,
          "the ref chooses the bundle and then leaves no trace in the output"
      end
    end

    test "bare @ renders the registry default" do
      with_registry("conformant", "minimal") do
        default = okf("render", "@")

        assert_equal 0, default.status
        assert_equal okf("render", "@conformant").out, default.out
        assert_match(/<title>OKF · fixtures\/conformant<\/title>/, default.out)
      end
    end

    test "-o writes the file and the confirmation names the file, not the ref" do
      with_registry("conformant") do
        path = File.join(@out_dir, "ref.html")
        result = okf("render", "@conformant", "-o", path)

        assert_equal 0, result.status
        assert_equal "wrote 3 concepts to #{path}\n", result.out
        refute_match(/@conformant/, result.out, "unlike index/search, render never echoes the ref identity")
        refute_match(/<!doctype html/, result.out, "the page goes to the file, never to stdout as well")

        html = read_utf8(path)
        assert_match(/\A<!doctype html>/, html)
        assert_match(/<title>OKF · fixtures\/conformant<\/title>/, html, "the page is titled from the directory")
        assert_equal okf("render", "@conformant").out, html, "the file is byte-for-byte what stdout would carry"
      end
    end

    test "-t and -l override the header of a ref-named bundle" do
      with_registry("conformant") do
        titled = okf("render", "@conformant", "-t", "My Bundle", "-l", "https://example.com/src")

        assert_equal 0, titled.status
        assert_match(/<title>OKF · My Bundle<\/title>/, titled.out)
        assert_match(/<meta property="og:title" content="OKF · My Bundle">/, titled.out)
        assert_match(/<a class="src" href="https:\/\/example\.com\/src" target="_blank" rel="noopener">source ↗<\/a>/, titled.out)
        refute_match(/fixtures\/conformant<\/title>/, titled.out, "-t replaces the dir-derived name")

        refute_match(/class="src"/, okf("render", "@conformant").out, "no -l means no source link")
      end
    end

    test "--layout seeds the page's initial layout for a ref, for each built-in" do
      with_registry("minimal") do
        OKF::Render::Graph::LAYOUTS.each do |layout|
          result = okf("render", "@minimal", "--layout", layout)

          assert_equal 0, result.status, "--layout #{layout} is valid"
          assert_match(/layout:\{name:'#{layout}',animate:false/, result.out, "cytoscape boots on #{layout}")
          assert_match(/layoutSel\.value='#{layout}';/, result.out, "and the picker shows it")
        end

        assert_match(/layoutSel\.value='cose';/, okf("render", "@minimal").out, "cose is the default")
      end
    end

    test "an unknown --layout is a usage error that writes nothing (exit 2)" do
      with_registry("conformant") do
        path = File.join(@out_dir, "never.html")
        result = okf("render", "@conformant", "--layout", "bogus", "-o", path)

        assert_equal 2, result.status
        assert_match(/invalid argument: --layout bogus/, result.err)
        assert_empty result.out
        refute File.exist?(path), "a rejected layout must not leave a file behind"
      end
    end

    test "-o into an unwritable path is a usage error, not a backtrace" do
      with_registry("minimal") do
        result = okf("render", "@minimal", "-o", File.join(@out_dir, "no-such-dir", "graph.html"))

        assert_equal 2, result.status, "a bad path argument keeps the 0/1/2 contract"
        assert_match(/error: cannot write .*graph\.html: No such file or directory/, result.err)
        refute_match(/cli\.rb:\d+:in/, result.err, "the user sees a reason, never a Ruby backtrace")
        assert_empty result.out
      end
    end

    test "a malformed ref-named bundle is best-effort — skips noted, valid HTML, exit 0" do
      with_registry("malformed") do
        result = okf("render", "@malformed")

        assert_equal 0, result.status
        assert_match(/note: skipped 2 unusable file\(s\)/, result.err)
        assert_match(/\A<!doctype html>/, result.out)
        assert_match(/A valid concept living among malformed ones\./, result.out, "the files that parse are still baked in")
      end
    end

    test "an unknown slug is a usage error naming the registry file it read" do
      with_registry("conformant") do
        path = File.join(@out_dir, "never.html")
        result = okf("render", "@ghost", "-o", path)

        assert_equal 2, result.status
        assert_match(/\Aerror: not a registered bundle: @ghost in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry list\)$/, result.err)
        assert_empty result.out
        refute File.exist?(path), "an unresolved ref must not leave a file behind"
      end
    end

    test "a registered-but-gone directory is a usage error naming the next move" do
      doomed = register_doomed

      with_registry("conformant") do
        result = okf("render", "@doomed")

        assert_equal 2, result.status
        assert_match(/\Aerror: @doomed points to #{Regexp.escape(doomed)}, which is not a directory \(okf registry del doomed, or restore it\)$/,
          result.err)
        assert_empty result.out
      end
    end

    test "bare @ on an empty registry hints at registering one" do
      with_registry do
        result = okf("render", "@")

        assert_equal 2, result.status
        assert_match(/not a registered bundle: @ in .*registry\.json \(okf registry set <dir>\)/, result.err)
        assert_empty result.out
      end
    end

    test "a second bundle is a question render cannot answer (exit 2)" do
      with_registry("conformant", "minimal") do
        result = okf("render", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_match(/error: unexpected argument '@minimal'/, result.err)
        assert_empty result.out
      end
    end

    private

    # A registered bundle whose directory is then deleted — the stale entry every
    # ref-taking verb must refuse rather than half-answer. Returns its path.
    def register_doomed
      dir = File.join(@out_dir, "doomed")
      FileUtils.cp_r(fixture("minimal"), dir)
      okf("registry", "set", dir, "--as", "doomed")
      FileUtils.rm_rf(dir)
      dir
    end
  end
end
