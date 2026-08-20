# frozen_string_literal: true

module OKF
  class CLI
    # Bundle rollups — concepts, dirs, types, links, tags — in one screen.
    class Stats < Command
      def self.id
        :stats
      end

      def self.group
        :read
      end

      def self.help_rows
        [
          [ "stats     <dir|@slug> [--json]", "bundle rollups (concepts, dirs, types, links, tags)" ]
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
        stats = folder.stats
        options[:json] ? print_stats_json(dir, stats) : print_stats(dir, stats)
        0
      end

      private

      # The rollup itself is Bundle#stats — one home, shared with the MCP
      # shell, after the by_dir subtlety diverged once when hand-copied.
      def print_stats(dir, stats)
        @out.puts "Stats — #{bundle_label(dir)}"
        @out.puts
        @out.puts "  concepts       #{stats[:concepts]}"
        @out.puts "  dirs           #{stats[:dirs]}"
        @out.puts "  concept types  #{stats[:types]}"
        @out.puts "  cross-links    #{stats[:cross_links]}"
        @out.puts "  distinct tags  #{stats[:tags]}"
        print_stat_breakdown("By type", stats[:by_type])
        # One grouping word in the human view: `by_top_dir` stays in --json (the
        # first-segment rollup) but a screen that printed both it and `by_dir`
        # would double up on one idea, so the human view shows the full-path cut.
        print_stat_breakdown("By dir", stats[:by_dir]) { |label| dir_label(label) }
      end

      def print_stat_breakdown(title, counts)
        return if counts.empty?

        labels = counts.keys.map { |key| block_given? ? yield(key) : key }
        width = labels.map(&:length).max
        @out.puts
        @out.puts "  #{title}"
        counts.each_with_index { |(_, count), i| @out.puts "    #{labels[i].ljust(width)}  #{count}" }
      end

      def print_stats_json(dir, stats)
        emit_json(bundle_head(dir).merge(
          "concepts" => stats[:concepts], "dirs" => stats[:dirs], "top_dirs" => stats[:top_dirs],
          "concept_types" => stats[:types], "cross_links" => stats[:cross_links], "distinct_tags" => stats[:tags],
          "by_type" => stats[:by_type], "by_dir" => stats[:by_dir], "by_top_dir" => stats[:by_top_dir]
        ))
      end
    end

    register(Stats)
  end
end
