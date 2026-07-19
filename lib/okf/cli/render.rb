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

        options = { output: nil, title: nil, link: nil, layout: "cose" }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf render <dir|@slug> [-o FILE] [--layout NAME] [-t title] [-l url]"
          o.on("-o", "--output FILE", "write to FILE instead of stdout") { |v| options[:output] = v }
          o.on("-t", "--title TITLE", "graph title (default: parent/bundle dir name)") { |v| options[:title] = v }
          o.on("-l", "--link URL", "source URL shown in the header") { |v| options[:link] = v }
          o.on("--layout NAME", OKF::Render::Graph::LAYOUTS, "initial layout (#{OKF::Render::Graph::LAYOUTS.join(", ")})") { |v| options[:layout] = v }
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        folder = OKF::Bundle::Folder.load(dir)
        report_skipped(folder)
        html = OKF::Render::Graph.static(folder, title: options[:title], link: options[:link], layout: options[:layout])
        if options[:output]
          # A bad -o path (a missing directory, a permission denial) is a bad
          # *argument*: exit 2 with the reason, never a backtrace and an exit code
          # that means "failing bundle".
          begin
            File.write(options[:output], html)
          rescue SystemCallError => e
            return usage_error("cannot write #{options[:output]}: #{e.message}")
          end
          count = folder.graph(minimal: true).nodes.size
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
