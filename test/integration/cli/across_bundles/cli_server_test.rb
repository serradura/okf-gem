# frozen_string_literal: true

require_relative "../cli_integration_case"

# The CLI loads these on demand (`server` requires them); a test naming the
# classes it asserts on cannot wait for the run to pull them in.
require "json"
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
      assert_match(/no bundles registered/, okf("registry", "list").out,
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
        okf("registry", "default", "rooted")
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

    test "a bare server inside a project tree discovers and serves its local registry" do
      # The payoff: no $OKF_HOME setup — a .okf-registry.json in the tree is what
      # a bare `okf server` here serves.
      tree = File.join(@out_dir, "proj")
      FileUtils.mkdir_p(tree)
      File.write(File.join(tree, ".okf-registry.json"), JSON.generate("bundles" => [], "groups" => []))
      in_dir(tree) do
        okf("registry", "set", fixture("conformant"))
        okf("registry", "set", fixture("minimal"))
      end

      result, booted = in_dir(tree) { okf_server }
      hub = booted_app(booted.first)

      assert_equal 0, result.status
      assert_kind_of OKF::Server::Hub, hub
      assert_match(%r{/b/conformant/}, result.out)
      assert_match(%r{/b/minimal/}, result.out)
      refute_path_exists File.join(@home, "registry.json"), "the global $OKF_HOME registry was never written"
    end

    test "OKF_NO_DISCOVERY makes a bare server serve the global registry, not a local one under cwd" do
      File.write(File.join(Dir.pwd, ".okf-registry.json"), JSON.generate(
        "bundles" => [ { "slug" => "localonly", "path" => fixture("minimal"), "title" => "t" } ], "groups" => []
      ))

      # The harness keeps OKF_NO_DISCOVERY=1, so the local file under cwd is ignored.
      result, = with_registry("conformant") { okf_server }

      assert_match(%r{/b/conformant/}, result.out, "the escape hatch serves the global registry")
      refute_match(/localonly/, result.out)
    end

    test "a bundle-less run with no chosen default falls back to the first registered bundle" do
      result, booted = with_registry("conformant", "rooted") { okf_server }

      assert_match(%r{^ {2}\* /b/conformant/}, result.out)
      assert_equal "/b/conformant/", get_page(booted_app(booted.first))[1]["location"]
      refute_match(/serving 0 bundles/, result.out)
    end

    test "a vanished first entry drops out, and / opens the same bundle the listing stars" do
      # The two derive the default separately — the hub from the bundles it could
      # actually load, `registry list` from the entries on disk — so they are
      # pinned against each other here. Drifting apart would put the * on a
      # bundle `/` never opens, which is what the star exists to name.
      doomed = scratch_bundle("doomed")
      okf("registry", "set", doomed)
      okf("registry", "set", fixture("conformant"))
      FileUtils.rm_rf(doomed)

      result, booted = okf_server

      assert_equal 0, result.status
      assert_match(/note: skipping doomed/, result.err, "the hole is named, never silently closed")
      assert_match(/serving 1 bundle, 3 concepts/, result.out)
      assert_match(%r{^ {2}\* /b/conformant/}, result.out)
      assert_equal "/b/conformant/", get_page(booted_app(booted.first))[1]["location"]
      assert_match(/^\* conformant/, okf("registry", "list").out,
        "the listing stars exactly the bundle / just redirected to")
    end

    test "a first entry that is on disk but holds an unreadable file still opens at /" do
      # The other half of the pin above. "On disk" and "the hub could load it"
      # agree everywhere except here: a directory that is present and readable
      # but carries a file that is not. The listing stars it — it is on disk,
      # not even (missing) — so the hub has to open it, which means one
      # unreadable file must not cost the whole bundle.
      skip_unless_permissions_bite
      locked = scratch_bundle("locked")
      okf("registry", "set", locked)
      okf("registry", "set", fixture("conformant"))
      make_unreadable(locked) # registered while healthy, rotted afterwards — the way it happens

      result, booted = okf_server

      assert_equal 0, result.status
      assert_match(/serving 2 bundles/, result.out, "an unreadable file costs a concept, never the bundle")
      assert_equal "/b/locked/", get_page(booted_app(booted.first))[1]["location"]
      assert_match(/^\* locked/, okf("registry", "list").out,
        "the listing stars exactly the bundle / just redirected to")
      refute_match(/note: skipping locked/, result.err, "nothing is skipped: the bundle loads, minus the file it cannot read")
    end

    test "an ephemeral dir named all/ mounts at /b/all/ — nothing is reserved without a registry" do
      # `all` is reserved in the *registry*, because `@all` names every registered
      # bundle there. An ephemeral run has no registry and no refs, so there is no
      # name to protect and no collision to dodge: suffixing here would invent a
      # /b/all-2/ whose /b/all/ does not exist.
      result, booted = okf_server(fixture("all"), fixture("minimal"))

      assert_equal 0, result.status
      assert_match(%r{^ {2}\* /b/all/\s}, result.out)
      assert_equal 200, get_page(booted_app(booted.first), "/b/all/")[0]
      refute_match(%r{/b/all-2/}, result.out, "a suffix dodging a collision with nothing")
    end

    test "a bundle-less run with an empty registry boots the hub's empty state" do
      result, booted = okf_server
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
      okf("registry", "set", fixture("conformant"))
      okf("registry", "set", gone)
      FileUtils.rm_rf(gone)

      result, booted = okf_server

      assert_equal 0, result.status, "one stale entry does not sink the hub"
      assert_match(/note: skipping gone — cannot read #{Regexp.escape(gone)}/, result.err)
      assert_match(/serving 1 bundle, 3 concepts/, result.out)
      assert_match(%r{^ {2}\* /b/conformant/}, result.out)
      refute_match(%r{/b/gone/}, result.out, "a bundle that cannot be read is not mounted")
      assert_equal 404, get_page(booted_app(booted.first), "/b/gone/").first
    end

    # -- @refs across bundles

    test "several @refs mount each bundle under its registered slug" do
      okf("registry", "set", fixture("conformant"), "--as", "handbook")
      okf("registry", "set", fixture("mentions"), "--as", "runbooks")

      result, booted = okf_server("@handbook", "@runbooks")
      hub = booted_app(booted.first)

      assert_equal 0, result.status
      assert_kind_of OKF::Server::Hub, hub
      assert_match(%r{^ {2}\* /b/handbook/\s+fixtures/conformant$}, result.out)
      assert_match(%r{^ {4}/b/runbooks/\s+fixtures/mentions$}, result.out)
      refute_match(%r{/b/conformant/}, result.out, "the mount carries the registry slug, not the dir basename")
      refute_match(%r{/b/mentions/}, result.out)

      status, _headers, page = get_page(hub, "/b/handbook/")
      assert_equal 200, status
      assert_match(%r{<title>OKF · fixtures/conformant</title>}, page)
    end

    test "a registered slug is reserved before a plain dir's basename is deduped" do
      okf("registry", "set", fixture("rooted"), "--as", "two")
      plain = scratch_bundle("x/two")

      # The plain dir leads, so argv order alone would hand it /b/two/ — but
      # /b/two/ is @two's name, and a bookmark from a bundle-less run must keep
      # meaning @two. Reserve every ref's slug first, then dedupe the basenames.
      result, booted = okf_server(plain, "@two")

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
      okf("registry", "set", fixture("conformant"), "--as", "handbook")

      result, _booted = okf_server(fixture("conformant"), "@handbook")

      assert_equal 0, result.status
      assert_match(/serving 1 bundle, 3 concepts/, result.out, "one resolved path is one bundle, however it was spelled")
      assert_match(%r{^ {2}\* /b/handbook/\s+fixtures/conformant$}, result.out,
        "the registered slug wins over the basename the plain dir would have taken")
      refute_match(%r{/b/conformant/}, result.out)
    end

    # -- a group @ref fans out to its member bundles

    test "a group ref mounts each of its members under its registered slug" do
      okf("registry", "set", fixture("conformant"), "--as", "handbook")
      okf("registry", "set", fixture("mentions"), "--as", "runbooks")
      okf("registry", "group", "docs", "@handbook", "@runbooks")

      result, booted = okf_server("@docs")
      hub = booted_app(booted.first)

      assert_equal 0, result.status
      assert_kind_of OKF::Server::Hub, hub
      assert_match(%r{^ {2}\* /b/handbook/\s+fixtures/conformant$}, result.out, "the group's first member lands at /")
      assert_match(%r{^ {4}/b/runbooks/\s+fixtures/mentions$}, result.out)

      status, headers, = get_page(hub)
      assert_equal 302, status
      assert_equal "/b/handbook/", headers["location"], "the mount table's * and the hub's / agree"
    end

    test "a vanished group member is skipped with a note; the rest still serve" do
      doomed = scratch_bundle("doomed")
      okf("registry", "set", fixture("conformant"), "--as", "handbook")
      okf("registry", "set", doomed)
      okf("registry", "group", "docs", "@handbook", "@doomed")
      FileUtils.rm_rf(doomed)

      result, _booted = okf_server("@docs")

      assert_equal 0, result.status
      assert_match(/note: skipping doomed — cannot read #{Regexp.escape(doomed)}/, result.err)
      # One surviving member takes the single-bundle path (arity decides the mode),
      # so it serves at / with the single-bundle serving line.
      assert_match(/serving 3 concepts at/, result.out, "the readable member still serves")
    end

    test "a group whose every member vanished fails the server (exit 2), booting nothing" do
      a = scratch_bundle("a")
      b = scratch_bundle("b")
      okf("registry", "set", a, "--as", "aa")
      okf("registry", "set", b, "--as", "bb")
      okf("registry", "group", "docs", "@aa", "@bb")
      FileUtils.rm_rf(a)
      FileUtils.rm_rf(b)

      result, booted = okf_server("@docs")

      assert_equal 2, result.status
      assert_nil booted, "nothing half-boots on an empty resolution"
      assert_match(/@docs resolves to no readable bundle/, result.err)
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
      OKF::Render::Graph::LAYOUTS.each do |layout|
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

    # -- --read-only: who may change the registry from the browser

    # Writability is read off `GET /bundles` rather than off the manager page:
    # /b/ carries no controls at any setting now, so its markup cannot tell the
    # settings apart. That endpoint is what the graph page's Bundles panel asks
    # before it decides what to offer, which makes it the honest signal.

    test "a loopback bind manages the registry from the browser without a flag" do
      _result, booted = with_registry("conformant", "rooted") { okf_server }

      assert_equal true, writable?(booted_app(booted.first)),
        "the audience this page was built for should not need a flag to use it"
    end

    test "--read-only takes management away from a loopback bind" do
      # The off switch, and the only one: management follows the bind, and this
      # is how you decline it on the bind that would otherwise have it.
      _result, booted = with_registry("conformant", "rooted") { okf_server("--read-only") }
      hub = booted_app(booted.first)

      assert_equal false, writable?(hub)
      assert_match(/fixtures\/conformant/, manager(hub), "the list is still worth reading")
    end

    test "--read-only refuses the write itself, not only the controls for it" do
      # The flag is what a public deployment binds, so it is worth proving at the
      # endpoint and not just on the page. This POST carries everything a real
      # one would — same origin, this boot's token — and the registry is read
      # back off disk afterwards, because a refusal that still wrote is the only
      # failure that matters here.
      _result, booted = with_registry("conformant", "rooted") { okf_server("--read-only") }
      hub = booted_app(booted.first)
      before = read_utf8(OKF::Registry.path)

      status, _headers, body = post(hub, "/registry/remove", "slug" => "rooted")

      assert_equal 403, status
      assert_match(/read-only/, body)
      assert_equal before, read_utf8(OKF::Registry.path), "nothing reached the registry"
      assert_match(/^\s*rooted/, okf("registry", "list").out, "and the entry is still registered")
    end

    test "a non-loopback bind is read-only, and no flag opens it" do
      # --bind 0.0.0.0 is how a personal tool becomes a public one. The manager
      # still *reads* — the page is worth having either way — but nothing writes,
      # and there is no longer an opt-in that says otherwise: the registry is
      # managed from the machine that owns it.
      _result, booted = with_registry("conformant", "rooted") { okf_server("--bind", "0.0.0.0") }
      hub = booted_app(booted.first)

      assert_equal false, writable?(hub)
      assert_match(/fixtures\/conformant/, manager(hub), "the list is still worth reading")

      # Gone, not quietly ignored — an unknown flag that boots anyway would let
      # a stale command line believe it had opened something.
      opted, = with_registry("conformant", "rooted") { okf_server("--bind", "0.0.0.0", "--allow-manage") }
      assert_equal 2, opted.status
      assert_match(/--allow-manage/, opted.err)
    end

    test "an ephemeral hub offers no management, loopback or not" do
      _result, booted = okf_server(fixture("conformant"), fixture("minimal"))
      hub = booted_app(booted.first)

      assert_equal false, JSON.parse(get_page(hub, "/bundles").last)["registry"],
        "there is no registry behind these dirs to change"
      assert_match(/not registered/, manager(hub),
        "and the page says so rather than leaving it a mystery")
    end

    test "--read-only shows up in the verb's own help" do
      assert_match(/--read-only/, okf("server", "--help").out)
    end

    test "a read-only hub refuses a registry POST outright, and the file on disk is untouched" do
      # Hiding the controls is a UI; refusing the request is the boundary. This
      # POST carries everything the page's own form would have — same origin,
      # this boot's token — and is still refused, because the bind decides.
      _result, booted = with_registry("conformant", "rooted") { okf_server("--bind", "0.0.0.0") }
      hub = booted_app(booted.first)
      before = read_utf8(OKF::Registry.path)

      status, _headers, page = post(hub, "/registry/rename", "slug" => "conformant", "to" => "renamed")

      assert_equal 403, status
      assert_match(/loopback/, page, "the refusal names what decides it")
      assert_equal before, read_utf8(OKF::Registry.path), "nothing reached the registry"
      assert_match(/^\* conformant/, okf("registry", "list").out, "and the entry still answers to its own slug")
    end

    test "a plain dir and a ref mount side by side, each under its own name" do
      okf("registry", "set", fixture("rooted"), "--as", "steered")

      mixed, booted = okf_server(fixture("minimal"), "@steered")

      assert_equal 0, mixed.status
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
      okf("registry", "set", fixture("conformant"))

      result, booted = okf_server("@conformant", "@ghost")

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
      assert_match(/note: skipped 2 unusable file\(s\) \(run `okf validate` for details\)/, result.err)
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
    # The /b/ manager as a booted hub renders it — where every question about
    # who may change what has a visible answer.
    def manager(hub)
      get_page(hub, "/b/").last
    end

    # What the Bundles panel asks before it decides what to offer — and so the
    # one place a boot's writability is visible from outside.
    def writable?(hub)
      JSON.parse(get_page(hub, "/bundles").last)["writable"]
    end

    # A form POST as the manager's own page would send it: same-origin, and
    # carrying this boot's token. Anything the hub refuses through here it
    # refuses for a reason of its own, not for a missing credential.
    def post(hub, path, params = {})
      body = Rack::Utils.build_query(params.merge("token" => hub.send(:token)))
      status, headers, response = hub.call(
        "REQUEST_METHOD" => "POST", "PATH_INFO" => path, "QUERY_STRING" => "",
        "HTTP_HOST" => "example.org", "HTTP_ORIGIN" => "http://example.org",
        "CONTENT_TYPE" => "application/x-www-form-urlencoded",
        "CONTENT_LENGTH" => body.bytesize.to_s, "rack.input" => StringIO.new(body)
      )
      [ status, headers, response.join ]
    end

    def get_page(app, path = "/")
      status, headers, body = app.call(
        "REQUEST_METHOD" => "GET", "PATH_INFO" => path, "QUERY_STRING" => "", "rack.input" => StringIO.new("")
      )
      [ status, headers, body.join ]
    end
  end
end
