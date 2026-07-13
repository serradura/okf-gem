# frozen_string_literal: true

module OKF
  module Server
    # Renders an OKF::Bundle::Graph as the interactive graph page served by
    # OKF::Server::App. The markup lives in graph/template.html.erb; #render
    # returns the HTML string.
    #
    # The page boots from a *minimal* payload — nodes carry only id + title, plus
    # compact TYPES/TAGS inverted indexes for colouring and filtering — and pulls
    # each concept's markdown body (and metadata) from the server on demand via
    # fetch, rendering it client-side with marked. Node bodies are therefore NOT
    # embedded here.
    #
    # NOTE (trust boundary): the page loads Cytoscape + marked from a CDN and
    # renders concept markdown without sanitization, so only serve bundles you
    # trust. The inline-<script> data is </script>-escaped by #json_for_script
    # (stdlib ERB does not auto-escape).
    class Graph
      TEMPLATE = File.expand_path("graph/template.html.erb", __dir__)
      LAYOUTS = %w[cose concentric breadthfirst circle grid].freeze

      # Node-diameter range in px; the template scales within it by node degree.
      MIN_SIZE = 14
      MAX_SIZE = 44

      # The 6-character JSON unicode escape for `<` (backslash, u, 0, 0, 3, c),
      # built from the backslash code point so no literal escape appears here.
      LT_ESCAPE = (92.chr(Encoding::UTF_8) + "u003c").freeze

      # +node_endpoint+/+meta_endpoint+ are the (mount-relative) URLs the page
      # fetches a concept's raw markdown and metadata fragment from — relative so
      # the page works whether served at "/" or mounted under a Rails prefix.
      def initialize(graph, title: nil, link: nil, layout: "cose", node_endpoint: "node", meta_endpoint: "node/meta")
        @graph = graph
        @title = title
        @link = link
        @layout = layout
        @node_endpoint = node_endpoint
        @meta_endpoint = meta_endpoint
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

      def html_escape(str)
        str.to_s.gsub("&", "&amp;").gsub('"', "&quot;").gsub("<", "&lt;").gsub(">", "&gt;")
      end
    end
  end
end
