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
          [ "graph     <dir|@slug> [--json] [--minimal] [--no-body] [--hubs]", "print the knowledge graph" ]
        ]
      end

      def call(argv)
        options = { json: false, minimal: false, body: true, hubs: false }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf graph <dir|@slug> [--json] [--minimal] [--no-body] [--hubs]"
          json_flags(o, options, "emit nodes and edges as JSON")
          o.on("--minimal", "leanest nodes (id + title); adds type/tag indexes") { options[:minimal] = true }
          o.on("--[no-]body", "include each concept's body (default: yes)") { |v| options[:body] = v }
          o.on("--hubs", "rank concepts by inbound links, with the source areas") { options[:hubs] = true }
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        return print_hubs(dir, options) if options[:hubs]

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

      private

      # `graph --hubs`: the inbound ranking with each hub's links grouped by
      # source area — the "is this hub well-homed?" evidence. A hub whose
      # inbound majority comes from outside its own area is a move candidate;
      # --minimal/--no-body shape node payloads and change nothing here.
      def print_hubs(dir, options)
        folder = OKF::Bundle::Folder.load(dir)
        hubs = folder.hubs
        report_skipped(folder)
        if options[:json]
          rows = hubs.map { |row| { "id" => row[:id], "area" => row[:area], "inbound" => row[:inbound], "by_area" => row[:by_area] } }
          emit_json(bundle_head(dir).merge("count" => hubs.size, "hubs" => rows))
        else
          @out.puts "Hubs — #{bundle_label(dir)} (#{counted(hubs.size, folder.concepts.size, "concept")} with inbound links)"
          @out.puts
          width = hubs.map { |row| row[:id].length }.max || 0
          dwidth = hubs.map { |row| row[:inbound].to_s.length }.max || 0
          hubs.each do |row|
            sources = row[:by_area].map { |area, count| "#{area} #{count}" }.join(", ")
            @out.puts "  #{row[:id].ljust(width)}  ×#{row[:inbound].to_s.rjust(dwidth)}   #{sources}"
          end
        end
        0
      end
    end

    register(Graph)
  end
end
