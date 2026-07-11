# frozen_string_literal: true

require "rack"

require "okf/server/graph"

module OKF
  module Server
    # HTTP access to a bundle's knowledge graph — a Rack app, so it runs under any
    # Rack server (WEBrick, via `okf server`) and can be mounted in a Rails app:
    #
    #   mount OKF::Server::App.new(folder) => "/knowledge"
    #
    # The page (OKF::Server::Graph) boots from a *minimal* graph (id + title + edges
    # + type/tag indexes) and pulls each concept's markdown body and description from
    # here on demand, so the initial payload stays small and bodies are read live
    # from disk (edits show without a restart). Part of the shell — it does I/O.
    #
    #   GET /               the interactive graph page (text/html)
    #   GET /node?id=…      the concept's raw markdown body (text/markdown)
    #   GET /node/meta?id=… its description, as an escaped HTML fragment
    #   GET /catalog        rich per-concept metadata for the catalog/files/stats
    #                       views: { concepts: [ {id, title, type, description,
    #                       tags, timestamp, status, area, dir, links_*} ] } (JSON)
    #   GET /tags           the tag index  { tag  => [id, …] } (JSON)
    #   GET /types          the type index { type => [id, …] } (JSON)
    class App
      def initialize(folder, title: nil, link: nil, layout: "cose")
        @folder = folder
        @title = title
        @link = link
        @layout = layout
      end

      def call(env)
        request = Rack::Request.new(env)
        return not_found unless request.get?

        case request.path_info
        when "", "/" then respond("text/html; charset=utf-8", page)
        when "/node" then node_body(request.params["id"])
        when "/node/meta" then node_meta(request.params["id"])
        when "/catalog" then respond_json(catalog)
        when "/tags" then respond_json(graph.tag_index)
        when "/types" then respond_json(graph.type_index)
        else not_found
        end
      end

      private

      # The minimal graph snapshot taken at boot — drives the page and the indexes.
      def graph
        @graph ||= @folder.graph(minimal: true)
      end

      # Rich per-concept metadata the Catalog, Files and Stats views need but the
      # lean graph payload deliberately omits — descriptions, tags, timestamps,
      # status, folder, and in/out link degree. Fetched once, lazily, by the client
      # so the graph's first paint stays minimal. The shape is built by the pure
      # OKF::Bundle#catalog, shared with the `okf catalog/files/tags/stats` CLI views.
      def catalog
        { concepts: @folder.catalog }
      end

      def page
        @page ||= Graph.new(graph, title: @title || @folder.name, link: @link, layout: @layout).render
      end

      def node_body(id)
        concept = concept_for(id)
        return not_found if concept.nil?

        respond("text/markdown; charset=utf-8", concept.body)
      end

      def node_meta(id)
        concept = concept_for(id)
        return not_found if concept.nil?

        respond("text/html; charset=utf-8", description_fragment(concept))
      end

      # Resolve an id to its concept, read live from disk. The id is only ever a key
      # into the bundle's id→path map, so it cannot name a file outside the bundle
      # (and Concept::File re-guards the path); an unknown id, a since-deleted file,
      # or one that no longer parses all map to 404.
      def concept_for(id)
        return nil if id.nil? || id.empty?

        @folder.concept(id)&.concept
      rescue OKF::Error, SystemCallError
        nil
      end

      def description_fragment(concept)
        description = concept.description.to_s
        return %(<span class="empty">no description</span>) if description.strip.empty?

        html_escape(description)
      end

      def respond(content_type, body)
        [ 200, { "content-type" => content_type }, [ body.to_s ] ]
      end

      def respond_json(object)
        respond("application/json; charset=utf-8", JSON.generate(object))
      end

      def not_found
        [ 404, { "content-type" => "text/plain; charset=utf-8" }, [ "not found\n" ] ]
      end

      def html_escape(str)
        str.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      end
    end
  end
end
