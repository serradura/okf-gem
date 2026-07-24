# frozen_string_literal: true

require_relative "../cli_integration_case"

# The CLI loads these on demand (`server` requires them); a test naming the
# classes it asserts on cannot wait for the run to pull them in.
require "okf/server/app"
require "okf/server/hub"
require "rack/deflater"
require "stringio"

# `okf server @slug` — one ref, one bundle. Arity decides the mode *before* refs
# are considered, so a single ref lands on the historical single-bundle App at
# `/`, exactly as a single dir does: no hub, and therefore no `/b/<slug>/` mount,
# however registered the bundle is. Every flag driven through the ref, and no
# socket — the base class injects a runner that captures the app instead.
#
# One ref only: several refs are the hub's surface, tested where multi-bundle
# behavior lives.
module ByRegistry
  # Bundles named by @ref — the identity form the registry gives.
  class CLIServerTest < CLIIntegrationCase
    test "one @ref boots a single App at / on the default address" do
      result, booted = with_registry("conformant") { okf_server("@conformant") }
      app, host, port = booted

      assert_equal 0, result.status
      assert_kind_of Rack::Deflater, app, "a ref-named bundle gzips like any other"
      assert_kind_of OKF::Server::App, booted_app(app), "one bundle is one App — the ref does not summon a hub"
      assert_equal "127.0.0.1", host
      assert_equal 8808, port
      assert_match(%r{\Aserving 3 concepts at http://127\.0\.0\.1:8808 \(Ctrl-C to stop\)\n\z}, result.out)
      refute_match(%r{/b/}, result.out, "no hub, no mount table")

      status, _headers, page = get_page(booted_app(app))
      assert_equal 200, status
      assert_match(%r{<title>OKF · fixtures/conformant</title>}, page, "the page is titled from the directory, not the slug")
    end

    test "a single ref serves no /b/<slug>/ mount — arity decided the mode" do
      _result, booted = with_registry("conformant") { okf_server("@conformant") }

      status, _headers, body = get_page(booted_app(booted.first), "/b/conformant/")
      assert_equal 404, status, "the registered slug buys no mount point: one bundle is served at / and only at /"
      assert_equal "not found\n", body
    end

    test "bare @ boots the registry default as a single App" do
      result, booted = with_registry("conformant", "minimal") { okf_server("@") }

      assert_equal 0, result.status
      assert_kind_of OKF::Server::App, booted_app(booted.first)
      assert_match(/serving 3 concepts/, result.out, "the first bundle registered is the default")

      _status, _headers, page = get_page(booted_app(booted.first))
      assert_match(%r{<title>OKF · fixtures/conformant</title>}, page)
    end

    test "a ref and its path boot the same single-bundle server" do
      by_ref, ref_booted = with_registry("conformant") { okf_server("@conformant") }
      by_path, path_booted = okf_server(fixture("conformant"))

      assert_equal by_path.out, by_ref.out, "the ref chooses the bundle; the boot line is the bundle's"
      assert_equal booted_app(path_booted.first).class, booted_app(ref_booted.first).class
    end

    test "-p/--bind reach the runner for a ref-named bundle" do
      result, booted = with_registry("conformant") { okf_server("@conformant", "-p", "9090", "--bind", "0.0.0.0") }
      _app, host, port = booted

      assert_equal 0, result.status
      assert_equal "0.0.0.0", host
      assert_equal 9090, port
      assert_match(%r{at http://0\.0\.0\.0:9090}, result.out)

      _long, booted = with_registry("minimal") { okf_server("@minimal", "--port", "7001", "--bind", "::1") }
      _app, host, port = booted
      assert_equal "::1", host
      assert_equal 7001, port
    end

    test "-t/-l apply to a ref-named bundle — it is a single-bundle server" do
      result, booted = with_registry("conformant") do
        okf_server("@conformant", "-t", "Custom Title", "-l", "https://example.test/src")
      end

      assert_equal 0, result.status
      refute_match(%r{--title/--link apply to a single-bundle server}, result.err,
        "one ref is one bundle — there is nothing to ignore")

      _status, _headers, page = get_page(booted_app(booted.first))
      assert_match(%r{<title>OKF · Custom Title</title>}, page)
      assert_match(%r{href="https://example\.test/src"}, page)
      refute_match(%r{fixtures/conformant}, page, "-t replaces the dir-derived name")
    end

    test "every valid --layout reaches the page served for a ref" do
      with_registry("minimal") do
        OKF::Render::Graph::LAYOUTS.each do |layout|
          result, booted = okf_server("@minimal", "--layout", layout)

          assert_equal 0, result.status, layout
          _status, _headers, page = get_page(booted_app(booted.first))
          assert_match(/layoutSel\.value='#{layout}';/, page, layout)
        end
      end
    end

    test "an unknown --layout is a usage error that never reaches the runner" do
      result, booted = with_registry("conformant") { okf_server("@conformant", "--layout", "bogus") }

      assert_equal 2, result.status
      assert_nil booted, "a rejected layout must not boot a server"
      assert_match(/invalid argument: --layout bogus/, result.err)
    end

    test "an unknown slug is a usage error that never reaches the runner" do
      result, booted = with_registry("conformant") { okf_server("@ghost") }

      assert_equal 2, result.status
      assert_nil booted, "nothing half-boots on an unresolved ref"
      assert_match(/\Aerror: not a registered bundle: @ghost in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry list\)$/, result.err)
      assert_empty result.out
    end

    test "a registered-but-gone directory is a usage error that never reaches the runner" do
      doomed = register_doomed

      result, booted = with_registry("conformant") { okf_server("@doomed") }

      assert_equal 2, result.status
      assert_nil booted
      assert_match(/\Aerror: @doomed points to #{Regexp.escape(doomed)}, which is not a directory \(okf registry del doomed, or restore it\)$/,
        result.err)
      assert_empty result.out
    end

    test "bare @ on an empty registry hints at registering one, and boots nothing" do
      result, booted = okf_server("@")

      assert_equal 2, result.status
      assert_nil booted, "bare @ is an explicit ask — unlike a bundle-less run, it never falls back to the empty hub"
      assert_match(/not a registered bundle: @ in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry set <dir>\)/, result.err)
    end

    test "a malformed ref-named bundle is best-effort — the skip is noted and the server still boots" do
      result, booted = with_registry("malformed") { okf_server("@malformed") }

      assert_equal 0, result.status
      assert_match(/note: skipped 2 unusable file\(s\)/, result.err)
      assert_kind_of OKF::Server::App, booted_app(booted.first)
      assert_match(/serving 3 concepts/, result.out)
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

    # Drive a booted (unwrapped) Rack app the way a browser would, no socket:
    # returns [ status, headers, body ]. App and Hub both answer with an array
    # body, so joining it is the whole response.
    def get_page(app, path = "/")
      status, headers, body = app.call(
        "REQUEST_METHOD" => "GET", "PATH_INFO" => path, "QUERY_STRING" => "", "rack.input" => StringIO.new("")
      )
      [ status, headers, body.join ]
    end
  end
end
