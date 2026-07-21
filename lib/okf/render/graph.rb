# frozen_string_literal: true

require "rack/utils"

module OKF
  # The view layer: turns a bundle into the interactive graph page. Pairs with the
  # pure OKF::Bundle::Graph (the data model) — Bundle builds the graph, Render
  # draws it. A shell (reads the template, escapes with rack/utils), but knows
  # nothing about HTTP: OKF::Server::App serves what this produces, and `okf
  # render` writes it to a file, from the one class.
  module Render
    # Renders an OKF::Bundle::Graph as the interactive graph page. The markup lives
    # in graph/template.html.erb; #render returns the HTML string.
    #
    # The page boots from a *minimal* payload — nodes carry only id + title, plus
    # compact TYPES/TAGS inverted indexes for colouring and filtering. It has two
    # data modes, both driven by one template:
    #
    #   server mode (embed: nil) — the default. Each concept's markdown body,
    #     metadata, catalog, index and log are pulled from OKF::Server::App on
    #     demand via fetch, so the initial payload stays small and bodies read
    #     live from disk (edits show without a restart). Nothing extra embedded.
    #   render mode (embed: payload) — `okf render` bakes the whole bundle in via
    #     .static below: the same fetch getters resolve from the injected payload
    #     instead, so the single file needs no server (e.g. GitHub Pages).
    #
    # NOTE (trust boundary): the page loads Cytoscape + marked from a CDN, so it
    # needs network for those libraries even in render mode. Fetched/embedded
    # markdown is sanitized client-side (DOMPurify.sanitize(marked.parse(...)))
    # and all inline-<script> data — including any embedded body — is
    # </script>-escaped by #json_for_script (stdlib ERB does not auto-escape).
    # Still, only serve bundles you trust.
    class Graph
      TEMPLATE = File.expand_path("graph/template.html.erb", __dir__)
      LAYOUTS = %w[cose concentric breadthfirst circle grid].freeze

      # Node-diameter range in px; the template scales within it by node degree.
      MIN_SIZE = 14
      MAX_SIZE = 44

      # The 6-character JSON unicode escape for `<` (backslash, u, 0, 0, 3, c),
      # built from the backslash code point so no literal escape appears here.
      LT_ESCAPE = (92.chr(Encoding::UTF_8) + "u003c").freeze

      # `okf render`: the whole page as one self-contained file, the bundle baked
      # in, so it hosts where no server answers a fetch. Takes any bundle handle
      # (an OKF::Bundle::Folder) and returns the HTML string.
      def self.static(folder, title: nil, link: nil, layout: "cose")
        new(folder.graph(minimal: true), title: title || folder.name, link: link, layout: layout, embed: payload(folder)).render
      end

      # What the baked page carries in place of the endpoints a live server would
      # answer. Every key here is data a client getter reads from EMBED instead of
      # fetching — and each derives from the *same* folder method the matching
      # OKF::Server::App endpoint uses, so the bake and the live server cannot
      # drift (/node/meta is the exception: the fragment is derived on the client
      # from the catalog's raw description, so no map is baked for it).
      def self.payload(folder)
        {
          catalog: folder.catalog,
          index: folder.directory_index,
          logs: folder.log_entries,
          bodies: folder.concepts.each_with_object({}) { |concept, map| map[concept.id] = concept.body.to_s }
        }
      end

      # +node_endpoint+/+meta_endpoint+ are the (mount-relative) URLs the page
      # fetches a concept's raw markdown and metadata fragment from — relative so
      # the page works whether served at "/" or mounted under a Rails prefix.
      # +embed+ is the render-mode payload (nil = server mode); see the class doc.
      # +siblings+/+self_slug+/+hub_path+ carry the hub's bundle switcher into the
      # page (server mode only). nil — the standalone-server and `okf render`
      # default — injects an empty SIBLINGS, so the switcher never appears in a
      # single bundle or a static file. +search_endpoint+ rides along with them:
      # the hub's cross-bundle /search, which only a hub can answer.
      def initialize(graph, title: nil, link: nil, layout: "cose", node_endpoint: "node", meta_endpoint: "node/meta", embed: nil,
                     siblings: nil, self_slug: nil, hub_path: nil, search_endpoint: nil,
                     manage_root: nil, manage_token: nil)
        @graph = graph
        @title = title
        @link = link
        @layout = layout
        @node_endpoint = node_endpoint
        @meta_endpoint = meta_endpoint
        @embed = embed
        @siblings = siblings
        @self_slug = self_slug
        @hub_path = hub_path
        @search_endpoint = search_endpoint
        @manage_root = manage_root
        @manage_token = manage_token
      end

      def render
        ERB.new(File.read(TEMPLATE, encoding: "UTF-8")).result(binding)
      end

      private

      def graph_name
        @title.to_s.empty? ? "OKF Knowledge Graph" : @title
      end

      def escaped_name
        html_escape(graph_name)
      end

      # The bundle's own name, for the client: what the header already shows, so
      # the page can label the root with it instead of `(root)` or `/`.
      def name_json
        json_for_script(graph_name)
      end

      def og_title
        html_escape("OKF · #{graph_name}")
      end

      def og_desc
        html_escape("#{@graph.nodes.length} concepts · interactive Open Knowledge Format knowledge graph")
      end

      def source_link
        return "" if @link.to_s.empty?

        %( <a class="src" href="#{html_escape(@link)}" target="_blank" rel="noopener">source ↗</a>)
      end

      def nodes_json
        json_for_script(@graph.nodes)
      end

      def edges_json
        json_for_script(@graph.edges)
      end

      # { type => [id, …] } — the client builds an id→type map for node colour.
      def types_json
        json_for_script(@graph.type_index)
      end

      # { tag => [id, …] } — the client derives a node's tags and offers filters.
      def tags_json
        json_for_script(@graph.tag_index)
      end

      # The render-mode payload, or the literal `null` in server mode — both from
      # the same </script>-escaping helper, so injection stays uniform and safe.
      def embed_json
        json_for_script(@embed)
      end

      # The hub switcher's data: the other bundles (empty when standalone/static),
      # this bundle's slug, and the hub root — all </script>-escaped like the rest.
      def siblings_json
        json_for_script(@siblings || [])
      end

      def self_slug_json
        json_for_script(@self_slug)
      end

      def hub_path_json
        json_for_script(@hub_path)
      end

      # The hub's cross-bundle /search, mount-relative — null everywhere else, and
      # that null is the gate: a standalone server and a static file have no set
      # of bundles to search, so the palette never offers concepts there.
      def search_endpoint_json
        json_for_script(@search_endpoint)
      end

      # Behind a hub the mark is a link back to the bundle list — "../" reaches
      # it under any mount, because every page lives at <prefix>/b/<slug>/.
      # Standalone and static have nowhere to go, so there it stays the plain
      # identity badge it has always been, and an <a href> to nothing is worse
      # than no <a> at all.
      def rail_brand_open
        return %(<span class="rail-brand" title=") unless @manage_root

        %(<a class="rail-brand" href="../" aria-label="All bundles" title=")
      end

      def rail_brand_close
        @manage_root ? "</a>" : "</span>"
      end

      # The hub root, mount-relative — where the Bundles panel reads /bundles and
      # posts /registry/<verb>. Null everywhere else, and that null is the gate:
      # a standalone server and a static file have no registry behind them, so
      # the panel never appears there.
      def manage_root_json
        json_for_script(@manage_root)
      end

      # This boot's CSRF token, and only where a write could be honoured — a
      # read-only hub bakes null, so the page holds no credential it may not use.
      # It is no wider than the /b/ manager, which any script on this origin
      # could already read; keeping it out of the page where it is useless is
      # tidiness, not a boundary.
      def manage_token_json
        json_for_script(@manage_token)
      end

      # JSON-encode for safe embedding in an inline <script>: escaping every `<` to
      # its JSON unicode escape neutralizes </script>, <!-- and <script in one
      # stroke, and the result stays valid JSON *and* JavaScript.
      def json_for_script(obj)
        JSON.generate(coerce(obj)).gsub("<") { LT_ESCAPE }
      end

      # Coerce any non-JSON-native scalar (e.g. a YAML Date/Time in tags) to a
      # string, leaving numbers/booleans/nil native.
      def coerce(obj)
        case obj
        when Hash then obj.transform_values { |value| coerce(value) }
        when Array then obj.map { |value| coerce(value) }
        when String, Integer, Float, true, false, nil then obj
        else obj.to_s
        end
      end

      # Rack's, not a hand-rolled one — this output goes into attributes
      # (`href="…"`), so the escape set is load-bearing rather than cosmetic.
      def html_escape(str)
        Rack::Utils.escape_html(str.to_s)
      end
    end
  end
end
