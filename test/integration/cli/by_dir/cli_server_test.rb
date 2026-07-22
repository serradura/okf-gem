# frozen_string_literal: true

require_relative "../cli_integration_case"

# The CLI loads these on demand (`server` requires them); a test naming the
# classes it asserts on cannot wait for the run to pull them in.
require "okf/server/hub"
require "rack/deflater"
require "stringio"

# `okf server` end-to-end — every synchronous path, no socket. The base class
# injects a runner, so the argv parsing, the mode selection, the notes, and the
# mount table all run for real and the app that *would* have been served is
# captured instead.
#
# Arity is the interface: one dir is a single App at `/`, two or more an
# ephemeral hub, none the hub over the persistent registry.
module ByDir
  # Bundles named by path — the plain form every verb accepts.
  class CLIServerTest < CLIIntegrationCase
    test "one dir boots a single App at / on the default address" do
      result, booted = okf_server(fixture("conformant"))
      app, host, port = booted

      assert_equal 0, result.status
      assert_kind_of Rack::Deflater, app
      assert_kind_of OKF::Server::App, booted_app(app)
      assert_equal "127.0.0.1", host
      assert_equal 8808, port
      assert_match(%r{serving 3 concepts at http://127\.0\.0\.1:8808 \(Ctrl-C to stop\)}, result.out)

      status, _headers, page = get_page(booted_app(app))
      assert_equal 200, status
      assert_match(%r{<title>OKF · fixtures/conformant</title>}, page)
    end

    # The App defaults to advertising nothing, because only the caller knows
    # where it is mounted and the page resolves the endpoint relative to the URL
    # the reader is on. `okf server` mounts it at the root, so it is the one that
    # can name it — and the palette must still search the bundle it was given.
    test "a single-bundle server names its own search endpoint, so the palette searches it" do
      _result, booted = okf_server(fixture("conformant"))
      app = booted_app(booted.first)

      _status, _headers, page = get_page(app)
      assert_match(/const SEARCH_ENDPOINT="search"/, page)

      status, _headers, body = app.call(
        "REQUEST_METHOD" => "GET", "PATH_INFO" => "/search", "QUERY_STRING" => "q=orders",
        "rack.input" => StringIO.new("")
      )
      assert_equal 200, status
      assert_equal "tables/orders", JSON.parse(body.join).fetch("results").first.fetch("id")
    end

    test "two dirs boot a hub with ephemeral slugs, gzipped like a single bundle" do
      result, booted = okf_server(fixture("conformant"), fixture("minimal"))
      app, = booted

      assert_equal 0, result.status
      assert_kind_of Rack::Deflater, app, "the boot seam gzips a hub exactly like a single bundle"
      hub = booted_app(app)
      assert_kind_of OKF::Server::Hub, hub
      assert_match(/serving 2 bundles, 4 concepts/, result.out)
      assert_match(%r{^ {2}\* /b/conformant/\s+fixtures/conformant$}, result.out, "the first dir is the default")
      assert_match(%r{^ {4}/b/minimal/\s+fixtures/minimal$}, result.out)

      status, headers, = get_page(hub)
      assert_equal 302, status
      assert_equal "/b/conformant/", headers["location"]
    end

    test "-p/--bind reach the runner in both modes" do
      single, booted = okf_server(fixture("conformant"), "-p", "9090", "--bind", "0.0.0.0")
      _app, host, port = booted
      assert_equal "0.0.0.0", host
      assert_equal 9090, port
      assert_match(%r{at http://0\.0\.0\.0:9090}, single.out)

      hub, booted = okf_server(fixture("conformant"), fixture("minimal"), "--port", "7001", "--bind", "::1")
      _app, host, port = booted
      assert_equal "::1", host
      assert_equal 7001, port
      assert_match(%r{at http://::1:7001}, hub.out)
    end

    test "-t/-l apply to a single bundle" do
      _result, booted = okf_server(fixture("conformant"), "-t", "Custom Title", "-l", "https://example.test/src")
      _status, _headers, page = get_page(booted_app(booted.first))

      assert_match(%r{<title>OKF · Custom Title</title>}, page)
      assert_match(%r{href="https://example\.test/src"}, page)
      refute_match(%r{fixtures/conformant}, page, "-t replaces the dir-derived name")
    end

    test "-t/-l are ignored with a note when several dirs are given" do
      result, booted = okf_server(fixture("conformant"), fixture("minimal"), "-t", "Custom Title", "-l", "https://example.test/src")

      assert_equal 0, result.status
      assert_match(%r{note: --title/--link apply to a single-bundle server; ignored}, result.err)
      refute_match(/Custom Title/, result.out, "the mount table keeps the dir-derived titles")

      _status, _headers, page = get_page(booted_app(booted.first), "/b/conformant/")
      assert_match(%r{<title>OKF · fixtures/conformant</title>}, page)
      refute_match(/example\.test/, page, "the ignored --link reaches no app behind the hub")
    end

    test "every valid --layout reaches the served page" do
      OKF::Render::Graph::LAYOUTS.each do |layout|
        result, booted = okf_server(fixture("minimal"), "--layout", layout)

        assert_equal 0, result.status, layout
        _status, _headers, page = get_page(booted_app(booted.first))
        assert_match(/layoutSel\.value='#{layout}';/, page, layout)
      end
    end

    test "--layout reaches the apps behind a hub too" do
      _result, booted = okf_server(fixture("minimal"), fixture("conformant"), "--layout", "grid")
      _status, _headers, page = get_page(booted_app(booted.first), "/b/minimal/")

      assert_match(/layoutSel\.value='grid';/, page)
    end

    test "an unknown --layout is a usage error that never reaches the runner" do
      result, booted = okf_server(fixture("conformant"), "--layout", "bogus")

      assert_equal 2, result.status
      assert_nil booted, "a rejected layout must not boot a server"
      assert_match(/invalid argument: --layout bogus/, result.err)
    end

    test "two dirs with the same basename dedupe to <slug> and <slug>-2" do
      result, _booted = okf_server(scratch_bundle("a/notes"), scratch_bundle("b/notes"))

      assert_equal 0, result.status
      assert_match(/serving 2 bundles, 2 concepts/, result.out)
      assert_match(%r{^ {2}\* /b/notes/\s+a/notes$}, result.out)
      assert_match(%r{^ {4}/b/notes-2/\s+b/notes$}, result.out)
    end

    test "the same directory passed twice mounts one bundle" do
      dir = fixture("conformant")
      result, booted = okf_server(dir, dir)

      assert_equal 0, result.status
      assert_kind_of OKF::Server::Hub, booted_app(booted.first)
      assert_match(/serving 1 bundle, 3 concepts/, result.out)
      assert_equal 1, result.out.scan(%r{/b/conformant/}).size

      # deduped by resolved path, not by argv spelling
      spelled, = okf_server(dir, File.join(dir, "."))
      assert_match(/serving 1 bundle, 3 concepts/, spelled.out)
    end

    test "@refs mount each bundle under its registered slug" do
      okf("registry", "set", fixture("conformant"), "--as", "uno")
      okf("registry", "set", fixture("minimal"), "--as", "dos")

      result, booted = okf_server("@uno", "@dos")
      hub = booted_app(booted.first)

      assert_equal 0, result.status
      assert_kind_of OKF::Server::Hub, hub
      assert_match(%r{^ {2}\* /b/uno/\s+fixtures/conformant$}, result.out)
      assert_match(%r{^ {4}/b/dos/\s+fixtures/minimal$}, result.out)
      refute_match(%r{/b/conformant/}, result.out, "the mount carries the registry slug, not the dir basename")

      status, _headers, page = get_page(hub, "/b/uno/")
      assert_equal 200, status
      assert_match(%r{<title>OKF · fixtures/conformant</title>}, page)
    end

    test "a registered slug is reserved before a plain dir's basename is deduped" do
      okf("registry", "set", fixture("conformant"), "--as", "notes")
      plain = scratch_bundle("x/notes")

      # The plain dir leads, so argv order alone would hand it /b/notes/ — but a
      # bookmark to /b/notes/ must keep meaning @notes.
      result, booted = okf_server(plain, "@notes")

      assert_equal 0, result.status
      assert_match(%r{/b/notes/\s+fixtures/conformant$}, result.out)
      assert_match(%r{/b/notes-2/\s+x/notes$}, result.out)

      _status, _headers, page = get_page(booted_app(booted.first), "/b/notes/")
      assert_match(%r{<title>OKF · fixtures/conformant</title>}, page, "/b/notes/ serves the registered bundle")
    end

    test "a missing directory is a usage error that never reaches the runner" do
      missing = File.join(@out_dir, "ghost")

      result, booted = okf_server(missing)
      assert_equal 2, result.status
      assert_nil booted
      assert_match(/error: #{Regexp.escape(missing)} is not a directory/, result.err)

      result, booted = okf_server(fixture("conformant"), missing)
      assert_equal 2, result.status
      assert_nil booted, "one bad dir sinks the whole hub — nothing half-boots"
    end

    test "an unknown @ref is a usage error that never reaches the runner" do
      okf("registry", "set", fixture("conformant"))

      result, booted = okf_server("@ghost", "@conformant")

      assert_equal 2, result.status
      assert_nil booted
      assert_match(/error: not a registered bundle: @ghost/, result.err)
      assert_match(/okf registry list/, result.err)
    end

    test "a bundle-less run with an empty registry boots the hub's empty state" do
      result, booted = okf_server
      hub = booted_app(booted.first)

      assert_equal 0, result.status
      assert_kind_of OKF::Server::Hub, hub
      assert_match(/serving 0 bundles, 0 concepts/, result.out)
      refute_match(%r{/b/}, result.out, "no bundles, no mount table")

      status, _headers, page = get_page(hub)
      assert_equal 200, status
      assert_match(/No bundles registered/, page)
    end

    test "a malformed bundle is best-effort — the skip is noted and the server still boots" do
      result, booted = okf_server(fixture("malformed"))

      assert_equal 0, result.status
      assert_match(/note: skipped 2 unusable file\(s\)/, result.err)
      assert_kind_of OKF::Server::App, booted_app(booted.first)
      assert_match(/serving 3 concepts/, result.out)
    end

    private

    # A throwaway copy of a fixture bundle at <out_dir>/<relative> — for the slug
    # questions (dedupe, reservation) that turn on a directory's basename.
    def scratch_bundle(relative, from = "minimal")
      dest = File.join(@out_dir, relative)
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp_r(fixture(from), dest)
      dest
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
