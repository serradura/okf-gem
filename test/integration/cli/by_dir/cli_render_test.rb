# frozen_string_literal: true

require_relative "../cli_integration_case"
require "okf/server/graph"

# `okf render` end to end — the static counterpart to `server`: the same
# interactive page with the whole bundle baked into one self-contained HTML file
# (bodies, catalog, index, logs), so it needs no server. Printed to stdout unless
# -o names a file.
module ByDir
  # Bundles named by path — the plain form every verb accepts.
  class CLIRenderTest < CLIIntegrationCase
    test "renders the whole page to stdout with the bundle baked into EMBED" do
      result = okf("render", fixture("conformant"))

      assert_equal 0, result.status
      assert_empty result.err
      assert_match(/\A<!doctype html><html lang="en">/, result.out)
      assert_match(/<\/html>\s*\z/, result.out)
      assert_match(/const EMBED=\{"catalog":/, result.out, "render mode bakes the payload in")
      refute_match(/const EMBED=null/, result.out, "EMBED=null is the server mode the page must not be in")
      assert_match(/"bodies":/, result.out)
      assert_match(/Joined with \[customers\]\(\/tables\/customers\.md\) on `customer_id`\./, result.out,
        "a concept's markdown body is baked in verbatim")
      assert_match(/# Update Log/, result.out, "so is the reserved log")
      assert_match(/# Sales Knowledge/, result.out, "and the authored index")
    end

    test "the baked page needs no server: every endpoint fetch is EMBED-guarded" do
      # The one network dependency left is the CDN (Cytoscape, marked, DOMPurify);
      # nothing is ever fetched from a *local* endpoint, because each getter takes
      # the EMBED branch when the payload is baked in.
      out = okf("render", fixture("conformant")).out

      callers = out.scan(/^.*fetch\([A-Z_]+_ENDPOINT.*$/)
      assert_equal 5, callers.size, "every on-demand endpoint the server serves has one getter"
      callers.each do |line|
        assert_match(/EMBED\?/, line, "a getter that fetches without an EMBED branch would break the static file")
      end
      assert_match(/getNodeBody\(id\)\{return EMBED\?Promise\.resolve\(EMBED\.bodies\[id\]/, out)
    end

    test "-o into an unwritable path is a usage error, not a backtrace" do
      result = okf("render", fixture("minimal"), "-o", File.join(@out_dir, "no-such-dir", "graph.html"))

      assert_equal 2, result.status, "a bad path argument keeps the 0/1/2 contract"
      assert_match(/cannot write .*graph\.html: No such file or directory/, result.err)
      refute_match(/cli\.rb:\d+:in/, result.err, "the user sees a reason, never a Ruby backtrace")
      assert_empty result.out
    end

    test "-o writes the file and prints only a confirmation" do
      path = File.join(@out_dir, "graph.html")
      result = okf("render", fixture("conformant"), "-o", path)

      assert_equal 0, result.status
      assert_equal "wrote 3 concepts to #{path}\n", result.out
      refute_match(/<!doctype html/, result.out, "the page goes to the file, never to stdout as well")

      html = read_utf8(path)
      assert_match(/\A<!doctype html>/, html)
      assert_match(/const EMBED=\{"catalog":/, html)
      assert_equal okf("render", fixture("conformant")).out, html, "the file is byte-for-byte what stdout would carry"
    end

    test "the default title is the parent/bundle dir name; -t and -l override the header" do
      default = okf("render", fixture("conformant"))
      assert_match(/<title>OKF · fixtures\/conformant<\/title>/, default.out)
      refute_match(/class="src"/, default.out, "no -l means no source link")

      titled = okf("render", fixture("conformant"), "-t", "My Bundle", "-l", "https://example.com/src")
      assert_equal 0, titled.status
      assert_match(/<title>OKF · My Bundle<\/title>/, titled.out)
      assert_match(/<meta property="og:title" content="OKF · My Bundle">/, titled.out)
      assert_match(/<a class="src" href="https:\/\/example\.com\/src" target="_blank" rel="noopener">source ↗<\/a>/, titled.out)
      refute_match(/fixtures\/conformant<\/title>/, titled.out)
    end

    test "--layout seeds the page's initial layout, for each of the five built-ins" do
      assert_equal %w[cose concentric breadthfirst circle grid], OKF::Server::Graph::LAYOUTS

      OKF::Server::Graph::LAYOUTS.each do |layout|
        result = okf("render", fixture("minimal"), "--layout", layout)

        assert_equal 0, result.status, "--layout #{layout} is valid"
        assert_match(/layout:\{name:'#{layout}',animate:false/, result.out, "cytoscape boots on #{layout}")
        assert_match(/layoutSel\.value='#{layout}';/, result.out, "and the picker shows it")
      end

      default = okf("render", fixture("minimal"))
      assert_match(/layoutSel\.value='cose';/, default.out, "cose is the default")
    end

    test "an unknown layout is a usage error that writes nothing (exit 2)" do
      path = File.join(@out_dir, "never.html")
      result = okf("render", fixture("conformant"), "--layout", "bogus", "-o", path)

      assert_equal 2, result.status
      assert_match(/invalid argument: --layout bogus/, result.err)
      assert_empty result.out
      refute File.exist?(path), "a rejected layout must not leave a file behind"
    end

    test "a malformed bundle is best-effort — skips noted on stderr, valid HTML on stdout, exit 0" do
      result = okf("render", fixture("malformed"))

      assert_equal 0, result.status
      assert_match(/note: skipped 2 unusable file\(s\)/, result.err)
      assert_match(/\A<!doctype html>/, result.out)
      assert_match(/const EMBED=\{"catalog":/, result.out)
      assert_match(/A valid concept living among malformed ones\./, result.out, "the files that parse are still baked in")
    end

    test "usage errors exit 2: missing dir, no dir" do
      missing = okf("render", File.join(BUNDLES, "does-not-exist"))
      assert_equal 2, missing.status
      assert_match(/is not a directory/, missing.err)
      assert_empty missing.out

      bare = okf("render")
      assert_equal 2, bare.status
      assert_match(/Usage: okf render <dir\|@slug> \[-o FILE\]/, bare.err)
    end
  end
end
