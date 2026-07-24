# frozen_string_literal: true

module OKF
  class CLI
    # The static counterpart to `server`: bake the whole bundle into one
    # self-contained HTML file (bodies, catalog, index, logs baked in, no server
    # needed — e.g. hosting on GitHub Pages). Prints to stdout unless -o is given.
    class Render < Command
      def self.id
        :render
      end

      def self.group
        :act
      end

      def self.help_rows
        [
          [ "render    <dir|@slug> [-o FILE] [--layout NAME] [...]", "write a static, self-contained HTML graph" ]
        ]
      end

      def call(argv)
        require "okf/render/graph"

        options = { output: nil, title: nil, link: nil, layout: "cose", map: false }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf render <dir|@slug> [-o FILE] [--layout NAME] [-t title] [-l url]"
          o.on("-o", "--output FILE", "write to FILE instead of stdout") { |v| options[:output] = v }
          o.on("-t", "--title TITLE", "graph title (default: parent/bundle dir name)") { |v| options[:title] = v }
          o.on("-l", "--link URL", "source URL shown in the header") { |v| options[:link] = v }
          o.on("--layout NAME", OKF::Render::Graph::LAYOUTS, "initial layout (#{OKF::Render::Graph::LAYOUTS.join(", ")})") { |v| options[:layout] = v }
          o.on("--map", "open in the Map view: concepts boxed by directory, links on selection") { options[:map] = true }
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        folder = OKF::Bundle::Folder.load(dir)
        report_skipped(folder)
        html = OKF::Render::Graph.static(folder, title: options[:title], link: options[:link], layout: options[:layout], map: options[:map])
        if options[:output]
          # A bad -o path (a missing directory, a permission denial) is a bad
          # *argument*: exit 2 with the reason, never a backtrace and an exit code
          # that means "failing bundle".
          begin
            File.write(options[:output], html)
          rescue SystemCallError => e
            return usage_error("cannot write #{options[:output]}: #{e.message}")
          end
          # Off the bundle, not a second graph: Graph.build maps one node per
          # concept, so the counts are identical — and Folder#graph is not
          # memoized, so asking for one here would build a whole second graph
          # (Render::Graph.static already built one) to print one number. Only
          # the graph, to be exact: the concepts are parsed once at Folder.load
          # and Graph.build reads them from memory, so this costs no disk.
          count = folder.bundle.concepts.size
          @out.puts "wrote #{count} #{pluralize(count, "concept")} to #{options[:output]}"
        else
          @out.print html
        end
        0
      end
    end

    register(Render)
  end
end
