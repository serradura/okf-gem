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
          [ "graph     <dir|@slug> [--json] [--minimal] [--hubs]", "print the knowledge graph" ],
          [ "graph     <dir|@slug> --traffic [--cut N]", "directories and the link traffic between them" ]
        ]
      end

      def call(argv)
        options = { json: false, minimal: false, body: true, hubs: false, traffic: false, cut: nil }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf graph <dir|@slug> [--json] [--minimal] [--no-body] [--hubs] [--traffic]"
          json_flags(o, options, "emit nodes and edges as JSON")
          o.on("--minimal", "leanest nodes (id + title); adds type/tag indexes") { options[:minimal] = true }
          o.on("--[no-]body", "include each concept's body (default: yes)") { |v| options[:body] = v }
          o.on("--hubs", "rank concepts by inbound links, with the source top-level dirs") { options[:hubs] = true }
          o.on("--traffic", "collapse concepts into their dirs; count the links between them") { options[:traffic] = true }
          o.on("--cut N", Integer, "least arc weight to draw (default: fitted to the bundle)") { |v| options[:cut] = v }
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        return print_traffic(dir, options) if options[:traffic]
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

      # `graph --traffic`: concepts collapse into the directory they live in, and
      # the links between two directories collapse into one weighted arc. It is
      # the reduction that pays, and the measurement says why: on a typical
      # bundle three quarters of all links cross a directory boundary, and those
      # aggregate roughly ten-to-one — 227 links became 14 arcs on the bundle
      # this was built for.
      #
      # The other half of the view is the cohesion column, which is the reason
      # `refine` wants this. `--hubs` measures concepts; refine's step-3
      # judgements ("does this directory prune?", "concern or container?") are
      # about *directories*, and nothing measured those. Cohesion is a
      # directory's internal traffic over its total, so it reads directly:
      # near-zero with heavy inbound is a shared primitive, heavy outbound with
      # nothing coming back is an index behaving like a container, and high is a
      # directory that genuinely holds together.
      def print_traffic(dir, options)
        folder = OKF::Bundle::Folder.load(dir)
        skeleton = folder.skeleton
        cut = options[:cut] || skeleton.suggested_cut
        return usage_error("--cut must be 1 or more, got #{cut}") if cut < 1

        report_skipped(folder)
        arcs = OKF::Bundle::Skeleton.arcs_above(skeleton.arcs, cut)
        rows = dir_traffic(skeleton)
        if options[:json]
          emit_json(bundle_head(dir).merge(
            "cut" => cut, "fitted" => options[:cut].nil?, "dirs" => stringify_rows(rows),
            "arcs" => stringify_rows(arcs), "total_arcs" => skeleton.arcs.size
          ))
        else
          @out.puts "Traffic — #{bundle_label(dir)} (#{skeleton.dirs.size} #{pluralize(skeleton.dirs.size, "dir")}, " \
                    "#{counted(arcs.size, skeleton.arcs.size, "arc")} at weight #{cut} or more)"
          print_dir_rows(rows)
          print_arc_rows(arcs)
        end
        0
      end

      # Each directory's link traffic, split three ways. Counted over *every*
      # arc, never the cut ones: the cut decides what is drawn, and a measurement
      # that moved when the picture was tidied would be worthless as evidence.
      def dir_traffic(skeleton)
        out = Hash.new(0)
        into = Hash.new(0)
        skeleton.arcs.each do |arc|
          out[arc[:source]] += arc[:weight]
          into[arc[:target]] += arc[:weight]
        end

        skeleton.dirs.map do |row|
          total = row[:internal] + out[row[:dir]] + into[row[:dir]]
          row.merge(out: out[row[:dir]], in: into[row[:dir]],
            cohesion: total.zero? ? nil : (100.0 * row[:internal] / total).round)
        end
      end

      # An empty bundle gets no table at all — a column header over nothing is a
      # heading that promises rows. The arc list is the opposite case and prints
      # regardless (see print_arc_rows); the difference is that an empty arc list
      # is a fact about the *cut*, and an empty dir table is a fact about the
      # bundle the count line has already stated.
      #
      # Sorted by cohesion ascending, so the directories with a case to answer
      # come first — a table that leads with the healthy ones buries its finding
      # under the rows nobody needed to read. A directory with no traffic at all
      # has no ratio to report and prints `—` rather than a 0% it did not earn.
      def print_dir_rows(rows)
        return if rows.empty?

        ordered = rows.sort_by { |row| [ row[:cohesion] || 999, row[:dir] ] }
        @out.puts
        labels = ordered.map { |row| dir_label(row[:dir]) }
        width = [ 3, *labels.map(&:length) ].max
        @out.puts "  #{"Dir".ljust(width)}  Concepts  Internal   Out    In  Cohesion"
        ordered.each_with_index do |row, i|
          @out.puts "  #{labels[i].ljust(width)}  #{row[:count].to_s.rjust(8)}  #{row[:internal].to_s.rjust(8)}  " \
                    "#{row[:out].to_s.rjust(4)}  #{row[:in].to_s.rjust(4)}  #{(row[:cohesion] ? "#{row[:cohesion]}%" : "—").rjust(8)}"
        end
      end

      # The arc list is the answer this mode exists for, so it prints even when
      # the cut emptied it — a heading over nothing says "the cut was too tight",
      # where silence reads as "the bundle has no cross-links".
      def print_arc_rows(arcs)
        @out.puts
        @out.puts "  Arcs"
        return @out.puts "    (none at this cut)" if arcs.empty?

        width = arcs.map { |arc| dir_label(arc[:source]).length }.max
        twidth = arcs.map { |arc| dir_label(arc[:target]).length }.max
        arcs.each do |arc|
          @out.puts "    #{dir_label(arc[:source]).ljust(width)} → #{dir_label(arc[:target]).ljust(twidth)}  ×#{arc[:weight]}"
        end
      end

      # The skeleton is symbol-keyed (it is a pure model, not a payload), and every
      # other --json view in this CLI answers in strings. Converted at the edge, so
      # the model stays the model.
      def stringify_rows(rows)
        rows.map { |row| stringify(row) }
      end

      # `graph --hubs`: the inbound ranking with each hub's links grouped by
      # source top-level dir — the "is this hub well-homed?" evidence. A hub whose
      # inbound majority comes from outside its own top-level dir is a move
      # candidate; --minimal/--no-body shape node payloads and change nothing here.
      def print_hubs(dir, options)
        folder = OKF::Bundle::Folder.load(dir)
        hubs = folder.hubs
        report_skipped(folder)
        if options[:json]
          rows = hubs.map { |row| { "id" => row[:id], "top_dir" => row[:top_dir], "inbound" => row[:inbound], "by_top_dir" => row[:by_top_dir] } }
          emit_json(bundle_head(dir).merge("count" => hubs.size, "hubs" => rows))
        else
          @out.puts "Hubs — #{bundle_label(dir)} (#{counted(hubs.size, folder.concepts.size, "concept")} with inbound links)"
          @out.puts
          width = hubs.map { |row| row[:id].length }.max || 0
          dwidth = hubs.map { |row| row[:inbound].to_s.length }.max || 0
          hubs.each do |row|
            sources = row[:by_top_dir].map { |top_dir, count| "#{top_dir} #{count}" }.join(", ")
            @out.puts "  #{row[:id].ljust(width)}  ×#{row[:inbound].to_s.rjust(dwidth)}   #{sources}"
          end
        end
        0
      end
    end

    register(Graph)
  end
end
