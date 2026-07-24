# frozen_string_literal: true

module OKF
  class CLI
    # List the "loose" files — concepts with graph degree 0 (no cross-links in or
    # out), grouped by folder. A folder-grouped view over lint's `unlinked` check,
    # for the common "which files float in the graph?" question. Advisory (exit 0):
    # a terminal leaf can be loose by design. `--json` for a machine substrate.
    class Loose < Command
      def self.id
        :loose
      end

      def self.group
        :judge
      end

      def self.help_rows
        [
          [ "loose     <dir|@slug> [--json]", "list files with no graph links, by folder" ]
        ]
      end

      def call(argv)
        options = { json: false }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf loose <dir|@slug> [--json]"
          json_flags(o, options, "emit the loose files as JSON")
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        folder = OKF::Bundle::Folder.load(dir)
        report_skipped(folder)
        files = loose_files(folder.graph(minimal: true))
        options[:json] ? print_loose_json(dir, files) : print_loose(dir, files)
        0
      end

      private

      # Degree-0 nodes as { id:, title:, dir: }, sorted by path — the same set lint's
      # `unlinked` check reports, resolved to titles/folders for display.
      def loose_files(graph)
        titles = graph.nodes.map { |node| [ node[:id], node[:title] ] }.to_h
        graph.unlinked_ids
             .map { |id| { id: id, title: titles[id], dir: OKF.dir_of(id) } }
             .sort_by { |file| file[:id] }
      end

      def print_loose(dir, files)
        @out.puts "Loose files — #{bundle_label(dir)} (#{files.size})"
        if files.empty?
          @out.puts "  #{paint("✓ none — every concept links or is linked", 32)}"
          return
        end

        files.group_by { |file| file[:dir] }.sort_by(&:first).each do |folder, group|
          width = group.map { |file| File.basename("#{file[:id]}.md").length }.max
          @out.puts
          @out.puts "  #{dir_label(folder, slash: true)}"
          group.each do |file|
            @out.puts "    #{File.basename("#{file[:id]}.md").ljust(width)}  #{file[:title]}"
          end
        end
      end

      def print_loose_json(dir, files)
        emit_json(bundle_head(dir).merge(
          "count" => files.size,
          "loose" => files.map { |file| stringify(file) }
        ))
      end
    end

    register(Loose)
  end
end
