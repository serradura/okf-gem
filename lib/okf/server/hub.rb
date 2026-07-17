# frozen_string_literal: true

require "rack"

require "okf/server/app"

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
    #   GET /b/             the bundle index — every hosted bundle, default marked
    #   GET /b/<slug>       301 -> /b/<slug>/      (query string preserved)
    #   GET /b/<slug>/...   delegated to that bundle's App (the prefix stripped)
    #   GET (unknown slug)  404 as a page listing the hosted bundles — a stale
    #                       bookmark after a rename gets a way home, not bare text
    #
    # +bundles+ is an ordered array of Hub::Bundle (slug, folder, title). Apps are
    # built up front, each carrying the *other* bundles as siblings so the in-page
    # switcher can jump between them; static `okf render` files get no siblings and
    # so cannot switch.
    class Hub
      MOUNT = "/b"

      # One hosted bundle: its +slug+ (unique mount key), the on-disk +folder+, and
      # its display +title+.
      Bundle = Struct.new(:slug, :folder, :title)

      # Shared style for the hub's own pages (empty landing, /b/ index, 404) —
      # self-contained and theme-aware, no external requests, in keeping with the
      # graph page's own no-CDN-at-rest rule.
      STYLE = <<~CSS
        body{margin:0;min-height:100vh;display:grid;place-items:center;background:#f4f5f7;color:#1f2328;font:15px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
        main{max-width:34rem;width:calc(100% - 4rem);padding:2rem}h1{font-size:1.3rem;margin:0 0 .5rem}
        code{background:#e6e8eb;padding:.15rem .4rem;border-radius:.35rem}
        ul.bundles{list-style:none;margin:1rem 0 0;padding:0}
        ul.bundles li{padding:.45rem 0;border-top:1px solid #e6e8eb;display:flex;justify-content:space-between;gap:1rem;align-items:baseline}
        ul.bundles a{color:inherit;font-weight:600;text-decoration:none}ul.bundles a:hover{text-decoration:underline}
        .meta{color:#63697a;font-size:.85rem;white-space:nowrap}
        .def{margin-left:.5rem;padding:.05rem .45rem;border-radius:99px;background:#e6e8eb;font-size:.75rem}
        @media(prefers-color-scheme:dark){body{background:#111318;color:#eceef1}code,.def{background:#232833}
        ul.bundles li{border-color:#2a2e36}.meta{color:#9aa0aa}}
      CSS

      # The hosted bundles in mount order, and the one `/` redirects to — so a
      # caller printing the mount table asks the hub instead of re-deriving the
      # rule and drifting from it.
      attr_reader :bundles, :default

      # The first bundle is the one `/` redirects to — the registry hands them over
      # in its own order, where first *is* the default (`okf registry default`
      # moves an entry to the front), and an ephemeral run takes the dirs as typed.
      def initialize(bundles, layout: "cose")
        @bundles = bundles
        @default = bundles.first
        @apps = build_apps(layout)
      end

      def call(env)
        request = Rack::Request.new(env)
        return not_found unless request.get?

        path = request.path_info
        query = request.query_string.to_s
        # Everything this class *emits* must carry the prefix a host mounted it
        # under; PATH_INFO is already relative to it.
        base = env["SCRIPT_NAME"].to_s
        return landing(base, query) if [ "", "/" ].include?(path)
        return html(200, index_page(base)) if [ MOUNT, "#{MOUNT}/" ].include?(path)

        slug, rest = split(path)
        app = slug && @apps[slug]
        return html(404, missing_page(base, path)) unless app
        return redirect("#{base}#{MOUNT}/#{slug}/", 301, query) if rest.empty?

        app.call(mounted(env, slug, rest))
      end

      private

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
            hub_path: "/"
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

      # The /b/ index — every hosted bundle with its mount link, concept count,
      # and the default marked. The browser counterpart of `okf registry`.
      def index_page(base)
        page("OKF · bundles", "<h1>Bundles</h1>#{bundle_list(base)}")
      end

      # The 404 for a slug the hub does not host: name what was asked for, then
      # list what exists — a stale bookmark after a rename gets a way home.
      def missing_page(base, path)
        body = "<h1>No bundle here</h1><p><code>#{escape(path)}</code> does not match a hosted bundle.</p>"
        body += bundle_list(base) unless @bundles.empty?
        page("OKF · not found", body)
      end

      def bundle_list(base)
        rows = @bundles.map do |bundle|
          count = counts[bundle.slug]
          badge = bundle.equal?(@default) ? %(<span class="def">default</span>) : ""
          %(<li><a href="#{escape(base)}#{MOUNT}/#{escape(bundle.slug)}/">#{escape(bundle.title)}</a>) +
            %(<span class="meta">#{escape(bundle.slug)} · #{count} concepts#{badge}</span></li>)
        end
        %(<ul class="bundles">#{rows.join}</ul>)
      end

      def page(title, body)
        <<~HTML
          <!doctype html><html lang="en"><head><meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <title>#{escape(title)}</title>
          <style>#{STYLE}</style>
          </head><body><main>#{body}</main></body></html>
        HTML
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
