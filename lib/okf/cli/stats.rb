# frozen_string_literal: true

module OKF
  class CLI
    # Bundle rollups — concepts, types, areas, links, tags — in one screen.
    class Stats < Command
      def self.id
        :stats
      end

      def self.group
        :read
      end

      def self.help_rows
        [
          [ "stats     <dir|@slug> [--json]", "bundle rollups (concepts, types, areas, links, tags)" ]
        ]
      end

      def call(argv)
        options = { json: false }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf stats <dir|@slug> [--json]"
          json_flags(o, options, "emit the stats as JSON")
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        folder = OKF::Bundle::Folder.load(dir)
        report_skipped(folder)
        stats = bundle_stats(folder)
        options[:json] ? print_stats_json(dir, stats) : print_stats(dir, stats)
        0
      end

      private

      # Bundle-level rollups derived from the catalog and the graph indexes.
      def bundle_stats(folder)
        graph = folder.graph(minimal: true)
        entries = folder.catalog
        by_type = graph.type_index.transform_values(&:size).sort_by { |_, n| -n }.to_h
        by_area = entries.group_by { |entry| entry[:area] }.transform_values(&:size).sort_by { |_, n| -n }.to_h
        {
          concepts: entries.size,
          areas: by_area.size,
          types: by_type.size,
          cross_links: graph.edges.size,
          tags: graph.tag_index.size,
          by_type: by_type,
          by_area: by_area
        }
      end

      def print_stats(dir, stats)
        @out.puts "Stats — #{bundle_label(dir)}"
        @out.puts
        @out.puts "  concepts       #{stats[:concepts]}"
        @out.puts "  areas          #{stats[:areas]}"
        @out.puts "  concept types  #{stats[:types]}"
        @out.puts "  cross-links    #{stats[:cross_links]}"
        @out.puts "  distinct tags  #{stats[:tags]}"
        print_stat_breakdown("By type", stats[:by_type])
        print_stat_breakdown("By area", stats[:by_area])
      end

      def print_stat_breakdown(title, counts)
        return if counts.empty?

        width = counts.keys.map(&:length).max
        @out.puts
        @out.puts "  #{title}"
        counts.each { |label, count| @out.puts "    #{label.ljust(width)}  #{count}" }
      end

      def print_stats_json(dir, stats)
        emit_json(bundle_head(dir).merge(
          "concepts" => stats[:concepts], "areas" => stats[:areas],
          "concept_types" => stats[:types], "cross_links" => stats[:cross_links], "distinct_tags" => stats[:tags],
          "by_type" => stats[:by_type], "by_area" => stats[:by_area]
        ))
      end
    end

    register(Stats)
  end
end
