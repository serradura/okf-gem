# frozen_string_literal: true

require_relative "../cli_integration_case"

# The CLI loads these on demand (`server` requires them); a test naming the
# classes it asserts on cannot wait for the run to pull them in.
require "okf/server/hub"
require "rack/deflater"
require "stringio"

# `okf server` naming SEVERAL bundles — the verb's real multi-bundle mode, and
# the whole surface of it. No socket is ever opened: the base class injects a
# runner, so argv parsing, mode selection, slug assignment, the notes, and the
# mount table all run for real and the app that *would* have been served is
# captured instead.
#
# Arity chooses the mode, and two of the three arities land here: two or more
# dirs fan out behind an *ephemeral* hub (slugs from basenames, nothing
# registered), and zero dirs put the *persistent* registry behind one (slugs from
# the registry, its chosen default at `/`). One dir is a single App — by_dir's.
module AcrossBundles
  # Bundles named several at a time — a hub.
  class CLIServerTest < CLIIntegrationCase
    # -- the ephemeral hub: two or more dirs

    test "two or more dirs boot a hub with ephemeral slugs, registering nothing" do
      result, booted = okf_server(fixture("conformant"), fixture("minimal"), fixture("rooted"))
      hub = booted_app(booted.first)

      assert_equal 0, result.status
      assert_kind_of OKF::Server::Hub, hub
      assert_match(%r{^ {2}\* /b/conformant/\s+fixtures/conformant$}, result.out)
      assert_match(%r{^ {4}/b/minimal/\s+fixtures/minimal$}, result.out)
      assert_match(%r{^ {4}/b/rooted/\s+fixtures/rooted$}, result.out)

      # Ephemeral is the whole point: the slugs came from the basenames and the
      # run left no trace behind it.
      assert_match(/no bundles registered/, okf("registry", "list", "--home", @home).out,
        "an ephemeral hub registers nothing — its slugs live for one run")
    end

    test "the serving line counts bundles and concepts across the whole hub" do
      result, _booted = okf_server(fixture("conformant"), fixture("minimal"), fixture("rooted"))

      assert_match(%r{^serving 3 bundles, 6 concepts at http://127\.0\.0\.1:8808 \(Ctrl-C to stop\)$}, result.out,
        "3 + 1 + 2 concepts, summed across the mounted bundles")
    end

    test "the mount table marks the default, which is the first dir given" do
      result, booted = okf_server(fixture("minimal"), fixture("conformant"))

      assert_match(%r{^ {2}\* /b/minimal/}, result.out, "argv order chose the default; only the first is starred")
      assert_equal 1, result.out.scan(/^ {2}\* /).size, "exactly one default"

      status, headers, = get_page(booted_app(booted.first))
      assert_equal 302, status
      assert_equal "/b/minimal/", headers["location"], "the table's * and the hub's / agree"
    end

    test "the boot seam wraps a hub in Rack::Deflater exactly as it wraps a single bundle" do
      _single, single_booted = okf_server(fixture("conformant"))
      _many, many_booted = okf_server(fixture("conformant"), fixture("minimal"))

      # The wrap belongs to *booting a server*, not to either mode — so a hub
      # gzips like a single bundle, and a mode added later gets it for free.
      assert_kind_of Rack::Deflater, single_booted.first
      assert_kind_of Rack::Deflater, many_booted.first
      assert_kind_of OKF::Server::App, booted_app(single_booted.first)
      assert_kind_of OKF::Server::Hub, booted_app(many_booted.first)
    end

    test "two dirs with the same basename dedupe to <slug> and <slug>-2" do
      result, booted = okf_server(scratch_bundle("a/notes"), scratch_bundle("b/notes"))

      assert_equal 0, result.status
      assert_match(/serving 2 bundles, 2 concepts/, result.out)
      assert_match(%r{^ {2}\* /b/notes/\s+a/notes$}, result.out)
      assert_match(%r{^ {4}/b/notes-2/\s+b/notes$}, result.out, "the second claimant is deduped, never silently dropped")

      hub = booted_app(booted.first)
      assert_equal 200, get_page(hub, "/b/notes/").first
      assert_equal 200, get_page(hub, "/b/notes-2/").first, "both bundles are reachable"
    end

    test "the same directory named twice mounts one bundle, deduped by resolved path" do
      dir = fixture("conformant")
      result, booted = okf_server(dir, dir)

      assert_equal 0, result.status
      assert_kind_of OKF::Server::Hub, booted_app(booted.first), "arity is read from argv, so two args still mean a hub"
      assert_match(/serving 1 bundle, 3 concepts/, result.out)
      assert_equal 1, result.out.scan(%r{/b/conformant/}).size,
        "two windows on one bundle would burn a slug on a URL that vanishes next run"

      # deduped by resolved path, not by argv spelling
      spelled, _booted = okf_server(dir, File.join(dir, "."))
      assert_match(/serving 1 bundle, 3 concepts/, spelled.out)
    end

    # -- the persistent hub: zero dirs

    test "zero dirs boot a hub over the persistent registry, honoring its chosen default at /" do
      result, booted = with_registry("conformant", "rooted") do
        okf("registry", "default", "rooted", "--home", @home)
        okf_server
      end
      hub = booted_app(booted.first)

      assert_equal 0, result.status
      assert_kind_of OKF::Server::Hub, hub
      assert_match(/serving 2 bundles, 5 concepts/, result.out)
      # rooted was registered *second*: the chosen default beats argv/registry order.
      assert_match(%r{^ {4}/b/conformant/\s+fixtures/conformant$}, result.out)
      assert_match(%r{^ {2}\* /b/rooted/\s+fixtures/rooted$}, result.out, "the * follows `registry default`, not the first entry")

      status, headers, = get_page(hub)
      assert_equal 302, status
      assert_equal "/b/rooted/", headers["location"], "/ opens the bundle the registry chose"
    end

    test "a bundle-less run with no chosen default falls back to the first registered bundle" do
      result, booted = with_registry("conformant", "rooted") { okf_server }

      assert_match(%r{^ {2}\* /b/conformant/}, result.out)
      assert_equal "/b/conformant/", get_page(booted_app(booted.first))[1]["location"]
      refute_match(/serving 0 bundles/, result.out)
    end

    test "a bundle-less run with an empty registry boots the hub's empty state" do
      result, booted = okf_server("--home", @home)
      hub = booted_app(booted.first)

      assert_equal 0, result.status
      assert_kind_of OKF::Server::Hub, hub, "no bundles is still a hub — there is nothing to mount at /"
      assert_match(/serving 0 bundles, 0 concepts/, result.out)
      refute_match(%r{/b/}, result.out, "no bundles, no mount table")

      status, _headers, page = get_page(hub)
      assert_equal 200, status, "the empty state is a page, not a redirect to nowhere"
      assert_match(/No bundles registered/, page)
    end

    test "a registered bundle whose directory is gone is skipped, and the hub boots without it" do
      gone = File.join(@out_dir, "gone")
      FileUtils.cp_r(fixture("minimal"), gone)
      okf("registry", "set", fixture("conformant"), "--home", @home)
      okf("registry", "set", gone, "--home", @home)
      FileUtils.rm_rf(gone)

      result, booted = okf_server("--home", @home)

      assert_equal 0, result.status, "one stale entry does not sink the hub"
      assert_match(/note: skipping gone — cannot read #{Regexp.escape(gone)}/, result.err)
      assert_match(/serving 1 bundle, 3 concepts/, result.out)
      assert_match(%r{^ {2}\* /b/conformant/}, result.out)
      refute_match(%r{/b/gone/}, result.out, "a bundle that cannot be read is not mounted")
      assert_equal 404, get_page(booted_app(booted.first), "/b/gone/").first
    end

    # -- @refs across bundles

    test "several @refs mount each bundle under its registered slug" do
      okf("registry", "set", fixture("conformant"), "--as", "handbook", "--home", @home)
      okf("registry", "set", fixture("mentions"), "--as", "runbooks", "--home", @home)

      result, booted = okf_server("@handbook", "@runbooks", "--home", @home)
      hub = booted_app(booted.first)

      assert_equal 0, result.status
      assert_kind_of OKF::Server::Hub, hub
      assert_match(%r{^ {2}\* /b/handbook/\s+fixtures/conformant$}, result.out)
      assert_match(%r{^ {4}/b/runbooks/\s+fixtures/mentions$}, result.out)
      refute_match(%r{/b/conformant/}, result.out, "the mount carries the registry slug, not the dir basename")
      refute_match(%r{/b/mentions/}, result.out)
      refute_match(/--home applies/, result.err, "--home steers an @ref — nothing to ignore")

      status, _headers, page = get_page(hub, "/b/handbook/")
      assert_equal 200, status
      assert_match(%r{<title>OKF · fixtures/conformant</title>}, page)
    end

    test "a registered slug is reserved before a plain dir's basename is deduped" do
      okf("registry", "set", fixture("rooted"), "--as", "two", "--home", @home)
      plain = scratch_bundle("x/two")

      # The plain dir leads, so argv order alone would hand it /b/two/ — but
      # /b/two/ is @two's name, and a bookmark from a bundle-less run must keep
      # meaning @two. Reserve every ref's slug first, then dedupe the basenames.
      result, booted = okf_server(plain, "@two", "--home", @home)

      assert_equal 0, result.status
      assert_match(%r{^ {4}/b/two/\s+fixtures/rooted$}, result.out, "@two keeps the slug it is registered under")
      assert_match(%r{^ {2}\* /b/two-2/\s+x/two$}, result.out, "the unregistered dir is the one that gets deduped")

      hub = booted_app(booted.first)
      _status, _headers, page = get_page(hub, "/b/two/")
      assert_match(%r{<title>OKF · fixtures/rooted</title>}, page, "/b/two/ serves the registered bundle")
      _status, _headers, other = get_page(hub, "/b/two-2/")
      assert_match(%r{<title>OKF · x/two</title>}, other)
    end

    test "a dir and a ref naming one bundle mount it once, under the registered slug" do
      okf("registry", "set", fixture("conformant"), "--as", "handbook", "--home", @home)

      result, _booted = okf_server(fixture("conformant"), "@handbook", "--home", @home)

      assert_equal 0, result.status
      assert_match(/serving 1 bundle, 3 concepts/, result.out, "one resolved path is one bundle, however it was spelled")
      assert_match(%r{^ {2}\* /b/handbook/\s+fixtures/conformant$}, result.out,
        "the registered slug wins over the basename the plain dir would have taken")
      refute_match(%r{/b/conformant/}, result.out)
    end

    # -- flags in multi form

    test "-p/--bind reach the runner for a hub" do
      result, booted = okf_server(fixture("conformant"), fixture("minimal"), "-p", "9090", "--bind", "0.0.0.0")
      _app, host, port = booted

      assert_equal "0.0.0.0", host
      assert_equal 9090, port
      assert_match(%r{at http://0\.0\.0\.0:9090}, result.out)

      long, booted = okf_server(fixture("conformant"), fixture("minimal"), "--port", "7001", "--bind", "::1")
      _app, host, port = booted
      assert_equal "::1", host
      assert_equal 7001, port
      assert_match(%r{at http://::1:7001}, long.out)
    end

    test "every valid --layout reaches every page mounted behind the hub" do
      OKF::Server::Graph::LAYOUTS.each do |layout|
        _result, booted = okf_server(fixture("minimal"), fixture("rooted"), "--layout", layout)
        hub = booted_app(booted.first)

        [ "/b/minimal/", "/b/rooted/" ].each do |mount|
          _status, _headers, page = get_page(hub, mount)
          assert_match(/layoutSel\.value='#{layout}';/, page, "#{layout} at #{mount}")
        end
      end
    end

    test "an unknown --layout is a usage error that never boots a hub" do
      result, booted = okf_server(fixture("conformant"), fixture("minimal"), "--layout", "bogus")

      assert_equal 2, result.status
      assert_nil booted, "a rejected layout must not boot a server"
      assert_match(/invalid argument: --layout bogus/, result.err)
      assert_empty result.out, "nothing was served, so nothing is announced"
    end

    test "-t/-l are ignored with a note in multi mode, and reach no page behind the hub" do
      result, booted = okf_server(fixture("conformant"), fixture("minimal"), "-t", "Custom Title", "-l", "https://example.test/src")

      assert_equal 0, result.status, "a flag with no effect here gets a note, not a refusal"
      assert_match(%r{note: --title/--link apply to a single-bundle server; ignored}, result.err)
      refute_match(/Custom Title/, result.out, "the mount table keeps the dir-derived titles")

      hub = booted_app(booted.first)
      _status, _headers, page = get_page(hub, "/b/conformant/")
      assert_match(%r{<title>OKF · fixtures/conformant</title>}, page)
      refute_match(/example\.test/, page, "the ignored --link reaches no app behind the hub")
    end

    test "--home is ignored with a note when dirs are given, but not when a ref needs it" do
      ignored, booted = okf_server(fixture("conformant"), fixture("minimal"), "--home", @home)
      assert_equal 0, ignored.status
      assert_match(/note: --home applies to a bundle-less run or an @ref; ignored/, ignored.err)
      assert_kind_of OKF::Server::Hub, booted_app(booted.first), "the note does not stop the boot"

      # A mix: the ref needs --home to resolve at all, so there is nothing to ignore.
      okf("registry", "set", fixture("rooted"), "--as", "steered", "--home", @home)
      mixed, booted = okf_server(fixture("minimal"), "@steered", "--home", @home)
      assert_equal 0, mixed.status
      refute_match(/--home applies/, mixed.err)
      assert_match(%r{^ {4}/b/steered/\s+fixtures/rooted$}, mixed.out)
      assert_kind_of OKF::Server::Hub, booted_app(booted.first)
    end

    # -- failure: nothing half-boots

    test "a missing directory among several is a usage error that never boots" do
      missing = File.join(@out_dir, "ghost")

      result, booted = okf_server(fixture("conformant"), missing, fixture("minimal"))

      assert_equal 2, result.status
      assert_nil booted, "one bad dir sinks the whole hub — nothing half-boots"
      assert_match(/error: #{Regexp.escape(missing)} is not a directory/, result.err)
      assert_empty result.out
    end

    test "an unknown @ref among several is a usage error that never boots" do
      okf("registry", "set", fixture("conformant"), "--home", @home)

      result, booted = okf_server("@conformant", "@ghost", "--home", @home)

      assert_equal 2, result.status
      assert_nil booted
      assert_match(/error: not a registered bundle: @ghost/, result.err)
      assert_match(/okf registry list/, result.err, "the message names the next move")
      assert_empty result.out
    end

    # -- best effort

    test "a malformed bundle among several is noted on stderr and the hub still boots" do
      result, booted = okf_server(fixture("malformed"), fixture("minimal"))
      hub = booted_app(booted.first)

      assert_equal 0, result.status
      assert_match(/note: skipped 2 file\(s\) with invalid frontmatter \(run `okf validate` for details\)/, result.err)
      assert_kind_of OKF::Server::Hub, hub
      assert_match(/serving 2 bundles, 4 concepts/, result.out, "the 3 concepts that parsed are served")
      assert_equal 200, get_page(hub, "/b/malformed/").first
    end

    private

    # A throwaway copy of a fixture bundle at <out_dir>/<relative> — for the slug
    # questions (dedupe, reservation) that turn on a directory's basename. Nested
    # one level so the parent/dir title the hub prints is predictable.
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
