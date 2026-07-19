# frozen_string_literal: true

module OKF
  class CLI
    # The knowledge graph as text — nodes, edges and the rollups the browser page
    # draws, for a reader that has no browser.
    class Graph < Command
      def self.id
        :graph
      end

      def self.group
        :graph
      end

      def self.help_rows
        [
          [ "graph     <dir|@slug> [--json] [--minimal] [--no-body]", "print the knowledge graph" ]
        ]
      end

      def call(argv)
        options = { json: false, minimal: false, body: true }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf graph <dir|@slug> [--json] [--minimal] [--no-body]"
          json_flags(o, options, "emit nodes and edges as JSON")
          o.on("--minimal", "leanest nodes (id + title); adds type/tag indexes") { options[:minimal] = true }
          o.on("--[no-]body", "include each concept's body (default: yes)") { |v| options[:body] = v }
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        folder = OKF::Bundle::Folder.load(dir)
        graph = folder.graph(minimal: options[:minimal], body: options[:body])
        report_skipped(folder)
        if options[:json]
          # The head every view carries: a payload of nodes and edges that never
          # says which bundle they came from is exactly what an agent holding
          # several bundles has to guess at.
          payload = bundle_head(dir).merge(graph.to_h)
          payload = payload.merge(types: graph.type_index, tags: graph.tag_index) if options[:minimal]
          emit_json(payload)
        else
          @out.puts "Graph — #{bundle_label(dir)} (#{graph.nodes.size} #{pluralize(graph.nodes.size, "concept")}, " \
                    "#{graph.edges.size} #{pluralize(graph.edges.size, "link")})"
        end
        0
      end
    end

    register(Graph)
  end
end
