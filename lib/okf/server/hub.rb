# frozen_string_literal: true

require "rack"
require "securerandom"
require "uri"

require "okf/server/app"
require "okf/server/hub/not_found"

module OKF
  module Server
    # Multiplexes N bundles behind one server. Each bundle is mounted at
    # /b/<slug>/ and served by its own OKF::Server::App; `/` redirects to the
    # default bundle (explicitly chosen, or the first), or shows an empty-state
    # page when none are registered. The graph page is already mount-relative (its fetch endpoints
    # are relative), so hosting under a prefix needs only a clean PATH_INFO strip
    # here plus a trailing-slash redirect. Part of the shell — it is a Rack app.
    #
    #   GET /               302 -> /b/<default>/   (empty-state page when no bundles)
    #   GET /search?q=…     ranked concepts across *every* hosted bundle (JSON) —
    #                       the only route that answers about the whole set, and
    #                       so the one route that can only live here
    #   GET /b/             the bundles list — every bundle, its health, and the
    #                       way into it. Read-only: managing the registry belongs
    #                       to the graph page's Bundles panel, which is where the
    #                       reader already is
    #   GET /b/<slug>       301 -> /b/<slug>/      (query string preserved)
    #   GET /b/<slug>/...   delegated to that bundle's App (the prefix stripped)
    #   GET (unknown slug)  404 on the app shell (Hub::NotFound) — the asked
    #                       path, a did-you-mean, and the hosted bundles, so a
    #                       stale bookmark after a rename gets a way home
    #   POST /registry/<verb>  default | rename | remove | add — the only routes
    #                       that change anything, gated four ways (see #write),
    #                       answering JSON to the Bundles panel's fetch()
    #
    # +bundles+ is an ordered array of Hub::Bundle (slug, folder, title). Apps are
    # built up front, each carrying the *other* bundles as siblings so the in-page
    # switcher can jump between them; static `okf render` files get no siblings and
    # so cannot switch.
    class Hub
      MOUNT = "/b"

      # The registry verbs POST reaches, and nothing else. A list rather than a
      # method lookup: the route is user input, and "whatever method the path
      # names" is how a router becomes an eval.
      WRITES = %w[default rename remove add].freeze

      # The /search cap and engine live on App, which now defines the payload both
      # hosts answer with (App.search_payload). Two copies of a constant is two
      # places to raise the cap and one of them silently losing.

      # One hosted bundle: its +slug+ (unique mount key), the on-disk +folder+, and
      # its display +title+.
      Bundle = Struct.new(:slug, :folder, :title)

      # Shared style for the hub's own pages (empty landing, /b/ manager, 404) —
      # self-contained and theme-aware, no external requests, in keeping with the
      # graph page's own no-CDN-at-rest rule.
      #
      # The tokens are the graph page's own values, not a second palette: this is
      # the same product, and a bundle index that looks like a different app is
      # worse than a plain list. `--warn` is the one addition — the graph page
      # never had to draw a middle verdict, and the manager does.
      #
      # `body.mgr` opts out of the centred card the landing and the 404 want. A
      # one-paragraph page centres well; a list of bundles does not.
      STYLE = <<~CSS
        :root{--bg:#f4f5f7;--panel:#ffffff;--ink:#1f2328;--muted:#63697a;--faint:#9298a4;
        --line:#e6e8eb;--line-2:#eef0f2;--accent:#e21e1e;--ok:#1a9e5f;--warn:#b7791f;--err:#c81a1a}
        @media(prefers-color-scheme:dark){:root{--bg:#111318;--panel:#1d2026;--ink:#eceef1;--muted:#9aa0aa;--faint:#6b7178;
        --line:#2a2e36;--line-2:#232830;--accent:#f5433b;--ok:#37c07f;--warn:#e0a13a;--err:#ff726b}}
        body{margin:0;min-height:100vh;display:grid;place-items:center;background:var(--bg);color:var(--ink);
        font:15px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
        main{max-width:34rem;width:calc(100% - 4rem);padding:2rem}h1{font-size:1.3rem;margin:0 0 .5rem}
        code{background:var(--line);padding:.15rem .4rem;border-radius:.35rem}
        .def{margin-left:.5rem;padding:.05rem .45rem;border-radius:99px;background:var(--line);font-size:.75rem}

        /* ── the bundles manager ── */
        body.mgr{display:block;place-items:initial}
        body.mgr main{max-width:60rem;width:auto;margin:0 auto;padding:3rem 2rem 4rem}
        .mhead{margin-bottom:1.5rem}
        /* the same 3px accent rule the graph page draws under a section head */
        .mhead h1{margin:0;padding-bottom:.55rem;position:relative;font-size:1.45rem;letter-spacing:-.01em}
        .mhead h1::after{content:"";position:absolute;left:0;bottom:0;width:34px;height:3px;border-radius:3px;background:var(--accent)}
        .mhead .sub{margin:.7rem 0 0;color:var(--muted);font-size:.9rem}
        ol.rows{list-style:none;margin:0;padding:0;border-top:1px solid var(--line)}
        .row{position:relative;display:flex;flex-wrap:wrap;gap:.5rem 1.5rem;align-items:baseline;
        padding:.95rem .9rem;border-bottom:1px solid var(--line)}
        .row:hover{background:var(--line-2)}
        /* The verdict as a left edge — the head's accent rule, stood on end and
           put to work. Colour only reinforces it; the word beside it is the
           message, so nothing here depends on being able to see red. */
        .row::before{content:"";position:absolute;left:0;top:.55rem;bottom:.55rem;width:3px;border-radius:0 3px 3px 0;background:var(--line)}
        .row[data-health=ok]::before{background:var(--ok)}
        .row[data-health=warn]::before{background:var(--warn)}
        .row[data-health=error]::before{background:var(--err)}
        .who{flex:1 1 16rem;min-width:0}
        .who .name{color:var(--ink);font-weight:600;text-decoration:none;font-size:1rem}
        .who .name:hover{text-decoration:underline}
        .who .name.off{color:var(--muted);font-weight:500}
        /* nowrap, because @slug and the folder are one identity read left to
           right — split over two lines they read as two facts */
        .ref{margin-top:.15rem;display:flex;flex-wrap:nowrap;gap:.55rem;align-items:baseline;
        font:12.5px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;color:var(--faint)}
        .ref .slug{flex:none}
        /* Monospace is not decoration here: @slug is what you type at the CLI
           and the folder is a real path. Both are literals, so both are set as
           literals. */
        .ref .slug{color:var(--muted)}
        /* Truncate a long path from the *left*: the tail (…/repo/.okf) is the
           part that identifies it, and clipping the tail identifies nothing.
           An rtl box puts the ellipsis at the front — but a leading "/" is a
           neutral character and would reorder to the far end, printing
           "…/repo/.okf/" for a path that has no trailing slash. The inner <bdi>
           isolates the path as one ltr run, so nothing in it moves. */
        .ref .dir{flex:1 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;direction:rtl;text-align:left}
        .ref .dir bdi{direction:ltr}
        /* Fixed slots, right-aligned as a block: these are columns of counts and
           verdicts read down as much as across, and a ragged column of numbers
           is a column nobody scans. The last slot stays reserved even when the
           row is not the default, so the two before it cannot shift. */
        .facts{margin-left:auto;display:flex;gap:1.1rem;align-items:baseline;font-size:.85rem;color:var(--muted);white-space:nowrap}
        .facts span{display:inline-block}
        .f-count{min-width:6.5rem;text-align:right}
        .f-health{min-width:8.5rem}
        .f-flag{min-width:4.6rem}
        .hv-word{color:var(--muted)}
        .row[data-health=warn] .hv-word{color:var(--warn)}
        .row[data-health=error] .hv-word{color:var(--err)}
        .row[data-health=missing] .who .name{color:var(--faint)}
        .mnote{margin:1.4rem 0 0;color:var(--faint);font-size:.85rem}

        /* Stacked, the fixed slots stop being columns and become indentation on
           a row that has nothing to put in one — so they collapse to their
           content, and an empty one takes no space at all. */
        @media(max-width:640px){body.mgr main{padding:2rem 1.1rem 3rem}
        .facts{margin-left:0;gap:.9rem}.f-count,.f-health,.f-flag{min-width:0;text-align:left}
        .facts span:empty{display:none}}
      CSS

      # The hosted bundles in mount order, and the one `/` redirects to — so a
      # caller printing the mount table asks the hub instead of re-deriving the
      # rule and drifting from it.
      attr_reader :bundles, :default

      # The first bundle is the one `/` redirects to — the registry hands them over
      # in its own order, where first *is* the default (`okf registry default`
      # moves an entry to the front), and an ephemeral run takes the dirs as typed.
      # +registry+ is the OKF::Registry this hub was booted from, when it was. It
      # is what separates the two kinds of hub: a registry-backed one can report
      # on entries it could not host (a folder that has since been deleted), and
      # an ephemeral one (`okf server ./a ./b`) has no such list and says so.
      # The object carries its own path, so the manager re-reads the file per
      # request rather than trusting a snapshot taken at boot.
      # +writable+ decides whether the manager offers the registry forms and
      # whether the POST routes answer at all. The CLI sets it: a loopback bind
      # gets it for free and `--read-only` declines it, while any other address
      # is refused outright with no flag that says otherwise — `--bind 0.0.0.0`
      # turns a personal tool into a public one, and the write surface does not
      # follow it there at all.
      def initialize(bundles, layout: "cose", registry: nil, writable: false)
        @bundles = bundles
        @default = bundles.first
        @boot_registry = registry
        @layout = layout
        @writable = writable
        @apps = build_apps(layout)
      end

      # Load every registered entry the hub can actually serve, skipping the ones
      # it cannot and yielding each skipped entry so a caller with a terminal can
      # say so. One implementation, used at boot by the CLI and again after every
      # write — a second copy is a second answer waiting to disagree.
      def self.bundles_for(registry)
        registry.each_with_object([]) do |entry, bundles|
          bundle = load_entry(entry)
          bundle ? bundles << bundle : (yield entry if block_given?)
        end
      end

      # The Reader maps a nonexistent directory to an *empty* bundle, so the
      # directory check has to be explicit — nothing raises for the commonest
      # failure, which is that someone moved the folder.
      # Method-level rescue, not a `do…end`-block rescue: that is a 2.6 feature
      # and the floor here is 2.4.
      def self.load_entry(entry)
        return nil unless File.directory?(entry.path)

        Bundle.new(entry.slug, OKF::Bundle::Folder.load(entry.path), entry.title)
      rescue SystemCallError, OKF::Error
        nil
      end
      private_class_method :load_entry

      # See App#warm_search — same reason, one corpus over every hosted bundle.
      def warm_search
        search_corpus
        self
      end

      def call(env)
        request = Rack::Request.new(env)
        # Everything this class *emits* must carry the prefix a host mounted it
        # under; PATH_INFO is already relative to it.
        base = env["SCRIPT_NAME"].to_s
        return write(request) if request.post? && request.path_info.start_with?("/registry/")
        return not_found unless request.get?

        path = request.path_info
        query = request.query_string.to_s
        return landing(base, query) if [ "", "/" ].include?(path)
        return search(request.params["q"]) if path == "/search"
        return bundles_json if path == "/bundles"
        return html(200, index_page(base)) if [ MOUNT, "#{MOUNT}/" ].include?(path)

        slug, rest = split(path)
        app = slug && @apps[slug]
        return html(404, missing_page(base, path, slug)) unless app
        return redirect("#{base}#{MOUNT}/#{slug}/", 301, query) if rest.empty?

        app.call(mounted(env, slug, rest))
      end

      private

      # The only route that changes anything, and so the only one with locks on
      # it. Four of them, in the order that leaks the least:
      #
      #   1. the verb is one of WRITES, or there is nothing here to talk about;
      #   2. this hub is writable at all (see #initialize) — a read-only server
      #      offers no controls, and refuses the request that skipped them anyway;
      #   3. there is a registry to write to — an ephemeral hub is serving
      #      directories somebody typed, and has no list to edit;
      #   4. the request is same-origin and carries this boot's token.
      #
      # The answer is always data. It used to be a redirect, because /b/ managed
      # the registry with plain forms and a POST/redirect/GET keeps a reload from
      # re-posting. Those forms are gone: the graph page's Bundles panel does the
      # same four verbs where the reader already is, and two implementations of
      # one contract is the thing that drifts. So there is one caller, it is a
      # fetch(), and asking for HTML no longer resurrects a page-shaped answer
      # that nothing would read.
      def write(request)
        verb = request.path_info.sub("/registry/", "")
        return not_found unless WRITES.include?(verb)

        return deny(403, "This server is read-only. Bundles are managed from a loopback bind, without --read-only.") unless @writable
        return deny(409, "These bundles were named on the command line, so there is no registry to change.") if @boot_registry.nil?
        return deny(403, "That request did not come from this page. Reload and try again.") unless authentic?(request)

        apply(verb, request.params)
      end

      def apply(verb, params)
        registry = OKF::Registry.new(@boot_registry.path)
        message = mutate(verb, registry, params)
        reload(registry)
        json("ok" => true, "message" => message)
      rescue OKF::Error => e
        deny(400, e.message)
      end

      def deny(status, message)
        [ status, { "content-type" => "application/json; charset=utf-8" }, [ JSON.generate("ok" => false, "error" => message) ] ]
      end

      # Every branch ends in the sentence the manager will show. The core does
      # the refusing — a reserved slug, a collision, a slug nothing carries all
      # raise OKF::Error with a message written for a person, and repeating that
      # judgement here is how the two come to disagree.
      def mutate(verb, registry, params)
        case verb
        when "default"
          slug = required(params, "slug")
          registry.default = slug
          "@#{slug} is now the bundle this server opens."
        when "rename"
          from = required(params, "slug")
          # The core normalizes what it is given, so the message reads back the
          # slug that was *stored* rather than the string that was typed —
          # "@a is now @My Notes" would be a sentence about a bundle nobody has.
          entry = registry.rename(from, required(params, "to"))
          "@#{from} is now @#{entry.slug}."
        when "remove"
          slug = required(params, "slug")
          # #remove answers nil for a slug nothing carries rather than raising —
          # it is a delete, and deleting nothing is not an error to the core. It
          # is one here: the button that sent this named a row, so a miss means
          # the page is stale and saying so is the useful answer.
          raise OKF::Error, "no bundle is registered as @#{slug}" if registry.remove(slug).nil?

          "@#{slug} is no longer registered. Its folder is untouched."
        else
          add_entry(registry, params)
        end
      end

      # Registry#add already refuses a path that is not a directory. The concept
      # check is this layer's own: a registry full of empty folders is the shape
      # of somebody pasting the wrong path, and catching it here is the
      # difference between a sentence and a mystery.
      def add_entry(registry, params)
        root = File.expand_path(required(params, "path"))
        raise OKF::Error, "not a directory: #{root}" unless File.directory?(root)

        if OKF::Bundle::Folder.load(root).bundle.concepts.empty?
          raise OKF::Error, "no concepts in #{root} — is this an OKF bundle?"
        end

        entry = registry.add(root, as: blank_to_nil(params["as"]), default: !OKF.blank?(params["default"]))
        "@#{entry.slug} is registered and ready to read."
      end

      def required(params, key)
        value = params[key]
        raise OKF::Error, "#{key} is required" if OKF.blank?(value)

        value.to_s.strip
      end

      def blank_to_nil(value)
        OKF.blank?(value) ? nil : value.to_s.strip
      end

      # Rebuild the served set from the registry that was just written. Without
      # this the file and the running server disagree until a restart, and every
      # link the manager draws afterwards points at the world as it was.
      def reload(registry)
        @boot_registry = registry
        @bundles = self.class.bundles_for(registry)
        @default = @bundles.first
        @apps = build_apps(@layout)
        @counts = nil
        @health = nil
        # The corpus is a snapshot of the set, so a write that changes the set
        # invalidates it. Without this a removed bundle keeps answering /search.
        @search_corpus = nil
      end

      # Same-origin *and* the token. Neither alone is enough: the token lives in
      # a page, and a page is a thing another site can get a reader to submit;
      # Origin alone would trust every tab this browser has open on this host.
      # An unstated origin is refused rather than assumed — a form POST from the
      # manager always states one.
      def authentic?(request)
        same_origin?(request) && Rack::Utils.secure_compare(token, request.params["token"].to_s)
      end

      def same_origin?(request)
        source = request.get_header("HTTP_ORIGIN") || request.get_header("HTTP_REFERER")
        return false if OKF.blank?(source)

        URI.parse(source).host == request.host
      rescue URI::Error
        false
      end

      # One token per boot, minted lazily. Per-boot rather than per-session
      # because the hub has no sessions and wants none: it is a local tool, and
      # a cookie jar is a whole subsystem to defend for a page four people see.
      def token
        @token ||= SecureRandom.hex(16)
      end

      # Cross-bundle search, straight from the pure OKF::Bundle::Search.across —
      # one shared index over every hosted bundle, so BM25 weighs a term against
      # the whole corpus and the merged ranking is comparable by construction.
      #
      # A blank q is an ordinary answer, not a 400: the palette fetches on every
      # keystroke, and the box starts empty. `fuzzy: true` matches both the TUI
      # and the page's own MiniSearch, so all three forgive the same typos.
      def search(query)
        json(App.search_payload(search_corpus, query))
      end

      # One index over every hosted bundle — one corpus, so BM25 weighs a term
      # against the whole set exactly as .across intends. Dropped whenever the
      # bundle set changes, which is the only thing that can invalidate it.
      def search_corpus
        @search_corpus ||= OKF::Bundle::Search.prepare(pairs, engine: App::SEARCH_ENGINE)
      end

      # The /b/ manager's own rows, as JSON — what the graph page's Bundles panel
      # reads. One source for both surfaces, so the panel and the page cannot
      # disagree about what is registered, how big it is, or how healthy.
      #
      # Fetched rather than baked into every page because the registry is
      # re-read per request: a rename made in another terminal shows the next
      # time the panel is opened, where a boot snapshot would go stale silently.
      #
      # `writable` and `registry` are two different reasons the panel might offer
      # nothing, and it says different things for each — a read-only bind names
      # the flag, an ephemeral set names the terminal. The token is deliberately
      # absent: it is baked into the page that may use it, and a credential in a
      # listing endpoint is a habit worth not forming.
      def bundles_json
        json(
          "writable" => @writable,
          "registry" => !@boot_registry.nil?,
          "bundles" => manager_rows.map { |row| stringify_row(row) }
        )
      end

      def stringify_row(row)
        row.each_with_object({}) { |(key, value), memo| memo[key.to_s] = value }
      end

      # [ slug, bundle ] for every hosted bundle — the in-memory model behind each
      # on-disk folder, which is all the search engine reads.
      def pairs
        @bundles.map { |bundle| [ bundle.slug, bundle.folder.bundle ] }
      end

      # Split "/b/<slug>/rest" into [ "<slug>", "/rest" ] (rest "" for just
      # "/b/<slug>"). A path outside the mount prefix, or an empty slug, is [ nil, nil ].
      def split(path)
        prefix = "#{MOUNT}/"
        return [ nil, nil ] unless path.start_with?(prefix)

        slug, slash, rest = path[prefix.length..-1].partition("/")
        return [ nil, nil ] if slug.empty?

        [ slug, slash + rest ]
      end

      # Concept counts for the listing pages, computed once. Bundle#graph is not
      # memoized (App memoizes its own), and /b/ and every stray 404 render this
      # list — without the memo a 404 flood reparses every hosted bundle.
      def counts
        @counts ||= @bundles.each_with_object({}) do |bundle, memo|
          memo[bundle.slug] = bundle.folder.graph(minimal: true).nodes.size
        end
      end

      # A copy of env aimed at the bundle's App: the /b/<slug> prefix moves from
      # PATH_INFO to SCRIPT_NAME. The App ignores SCRIPT_NAME (its endpoints are
      # relative), but keeping the split correct leaves the env well-formed.
      def mounted(env, slug, rest)
        env.merge(
          "SCRIPT_NAME" => "#{env["SCRIPT_NAME"]}#{MOUNT}/#{slug}",
          "PATH_INFO" => rest
        )
      end

      def build_apps(layout)
        @bundles.each_with_object({}) do |bundle, apps|
          apps[bundle.slug] = App.new(
            bundle.folder,
            title: bundle.title,
            layout: layout,
            siblings: siblings_of(bundle),
            self_slug: bundle.slug,
            hub_path: "/",
            # Relative for the same reason siblings are: every page lives at
            # <prefix>/b/<slug>/, so "../../search" reaches the hub's own route
            # under any mount without knowing the prefix.
            search_endpoint: "../../search",
            # Where the Bundles panel reads /bundles and posts /registry/<verb>,
            # by the same relative rule. The token rides along only where a write
            # could actually be honoured — a read-only or ephemeral hub bakes
            # nothing, so the page holds no credential it may not use.
            manage_root: "../../",
            manage_token: (@writable && @boot_registry ? token : nil)
          )
        end
      end

      # Every other bundle, as { slug:, title:, path:, default: } — what the
      # switcher lists; default marks the bundle `/` opens. The path is
      # *relative* because these are baked into each App at boot, before any
      # request names a SCRIPT_NAME: every page lives at <prefix>/b/<slug>/, so
      # "../<other>/" reaches its sibling under any mount and needs no prefix.
      def siblings_of(bundle)
        @bundles.reject { |other| other.slug == bundle.slug }
                .map { |other| { slug: other.slug, title: other.title, path: "../#{other.slug}/", default: other.equal?(@default) } }
      end

      def landing(base, query = "")
        return redirect("#{base}#{MOUNT}/#{@default.slug}/", 302, query) if @default

        html(200, page("OKF · no bundles", <<~BODY))
          <h1>No bundles registered</h1>
          <p>Register one with <code>okf registry set &lt;dir&gt;</code>, then restart <code>okf server</code>.</p>
        BODY
      end

      # The /b/ page — the bundles manager, and the browser counterpart of the
      # TUI's bundles view. Every fact a person needs to choose between bundles
      # is on the row: size, health, which one `/` opens, and whether the folder
      # is still there. A registry-backed hub reads the file per request rather
      # than a boot snapshot, so an edit made elsewhere shows on a refresh.
      def index_page(base)
        rows = manager_rows
        manager_page("OKF · bundles", <<~BODY)
          <header class="mhead"><h1>Bundles</h1><p class="sub">#{escape(manager_summary(rows))}</p></header>
          <ol class="rows">#{rows.map { |row| manager_row(base, row) }.join}</ol>
          #{manager_note}
        BODY
      end

      # One row per bundle this server knows about — which is not the same as
      # one per bundle it *hosts*. A registry entry whose folder was deleted
      # cannot be served, and leaving it off the page would answer "where did my
      # bundle go?" with silence. Matched to a hosted bundle by directory rather
      # than by slug: a rename in the file changes the slug and nothing else,
      # and a row that lost its identity over a rename is the bug this avoids.
      def manager_rows
        return @bundles.map { |bundle| hosted_row(bundle, bundle.slug) } if registry.nil?

        registry.listing.map do |entry|
          hosted = @bundles.find { |bundle| bundle.folder.root == entry[:dir] }
          hosted ? hosted_row(hosted, entry[:slug], entry[:dir]) : unhosted_row(entry)
        end
      end

      def hosted_row(bundle, slug, dir = nil)
        verdict, word = health(bundle)
        { slug: slug, title: bundle.title, dir: dir || bundle.folder.root, mount: bundle.slug,
          count: counts[bundle.slug], health: verdict, word: word, default: bundle.equal?(@default) }
      end

      # A registered entry the hub could not load. `missing` is the registry's
      # own flag (the directory is not there); anything else that failed to load
      # is a folder that exists and cannot be read, which is a different problem
      # and gets a different sentence.
      def unhosted_row(entry)
        word = entry[:missing] ? "folder is gone" : "could not be read"
        { slug: entry[:slug], title: entry[:title], dir: entry[:dir], mount: nil,
          count: nil, health: "missing", word: word, default: false }
      end

      def manager_row(base, row)
        name = if row[:mount]
                 %(<a class="name" href="#{escape(base)}#{MOUNT}/#{escape(row[:mount])}/">#{escape(row[:title])}</a>)
               else
                 %(<span class="name off">#{escape(row[:title])}</span>)
               end
        %(<li class="row" data-health="#{escape(row[:health])}">) +
          %(<div class="who">#{name}<div class="ref"><span class="slug">@#{escape(row[:slug])}</span>) +
          # The row shows the tail; the tooltip is where the whole path stays
          # reachable, since nothing else on the page carries it.
          %(<span class="dir" title="#{escape(row[:dir])}"><bdi>#{escape(row[:dir])}</bdi></span></div></div>) +
          %(<div class="facts">#{facts(row)}</div></li>)
      end

      # Three slots, always all three, so the columns line up down the page even
      # when a row has nothing to put in one of them.
      def facts(row)
        count = row[:count] ? tally(row[:count], "concept") : ""
        flag = row[:default] ? %(<span class="def">default</span>) : ""
        %(<span class="f-count">#{count}</span>) +
          %(<span class="f-health"><span class="hv-word">#{escape(row[:word])}</span></span>) +
          %(<span class="f-flag">#{flag}</span>)
      end

      # Counts what is on the page, including the rows the hub cannot serve —
      # a summary that omits them would contradict the list right underneath it.
      def manager_summary(rows)
        return "Nothing is registered yet." if rows.empty?

        hosted = rows.count { |row| row[:mount] }
        line = "#{tally(hosted, "bundle")} on this server. Open one to read its graph."
        gone = rows.length - hosted
        gone.zero? ? line : "#{line} #{tally(gone, "entry")} cannot be opened."
      end

      # An ephemeral hub has no registry behind it, which is why these bundles
      # will not be here next run — and why the Bundles panel offers nothing on
      # them either. Saying so beats leaving a reader to wonder why the controls
      # they were told about are absent.
      def manager_note
        return "" unless registry.nil?

        %(<p class="mnote">These bundles were named on the command line and are ) +
          %(<strong>not registered</strong> — they last as long as this server does. ) +
          %(<code>okf registry set &lt;dir&gt;</code> registers one for good.</p>)
      end

      # The registry as it is on disk right now, or nil for an ephemeral hub.
      # Re-read per request on purpose: the file is the source of truth, so an
      # `okf registry rename` in another terminal shows on the next refresh
      # instead of waiting for a restart.
      def registry
        @boot_registry && OKF::Registry.new(@boot_registry.path)
      end

      # ok / warn / error, with the word that carries the same message for a
      # reader who cannot see the colour. validate and lint stay separate (§9):
      # a curation finding is a warning and never a conformance error, so a thin
      # bundle keeps its link and only a non-conformant one reads as broken.
      # Memoised like #counts — every stray 404 renders a bundle list too, and
      # linting every hosted bundle per request is not a page render.
      def health(bundle)
        @health ||= {}
        @health[bundle.slug] ||= verdict_for(bundle)
      end

      def verdict_for(bundle)
        result = bundle.folder.validate
        return [ "error", tally(result.errors.length, "error") ] unless result.valid?

        warnings = bundle.folder.lint.warnings.length
        return [ "warn", tally(warnings, "warning") ] if warnings.positive?

        [ "ok", "no problems" ]
      rescue OKF::Error, SystemCallError
        [ "error", "could not be checked" ]
      end

      def tally(count, noun)
        "#{count} #{count == 1 ? noun : "#{noun}s"}"
      end

      # The 404 for a slug the hub does not host: name what was asked for, guess
      # what was meant, then list what exists — a stale bookmark after a rename
      # gets a way home rather than a dead end. Built on the app shell, in
      # NotFound; the rows are the manager's own, so a bundle reads the same
      # here as it does there.
      def missing_page(base, path, slug)
        rows = @bundles.map { |bundle| hosted_row(bundle, bundle.slug) }
        NotFound.page(path, slug, rows, base, MOUNT)
      end

      def page(title, body, body_class = "")
        <<~HTML
          <!doctype html><html lang="en"><head><meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <meta name="color-scheme" content="dark light">
          <title>#{escape(title)}</title>
          <style>#{STYLE}</style>
          </head><body class="#{body_class}"><main>#{body}</main></body></html>
        HTML
      end

      # The manager is a list, not a one-paragraph notice, so it drops the
      # centred card the landing and the 404 are shaped for.
      def manager_page(title, body)
        page(title, body, "mgr")
      end

      def json(object)
        [ 200, { "content-type" => "application/json; charset=utf-8" }, [ JSON.generate(object) ] ]
      end

      def html(status, body)
        [ status, { "content-type" => "text/html; charset=utf-8" }, [ body ] ]
      end

      # Keep the query string across redirects — `/b/notes?view=files` must land
      # on the Files view, not reset to the default graph.
      def redirect(location, status, query = "")
        location += "?#{query}" unless query.empty?
        [ status, { "location" => location, "content-type" => "text/plain; charset=utf-8" }, [ "" ] ]
      end

      def not_found
        OKF::Server::App.not_found
      end

      # Rack's, not a fourth hand-rolled one: the server layer had three, each
      # escaping a different set — App's left `"` alone, which is safe only
      # while nothing interpolates it into an attribute. Rack::Utils covers
      # & " ' < > and ships with the dependency we already have.
      def escape(str)
        Rack::Utils.escape_html(str.to_s)
      end
    end
  end
end
