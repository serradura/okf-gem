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
        by_top_dir = entries.group_by { |entry| entry[:top_dir] }.transform_values(&:size).sort_by { |_, n| -n }.to_h
        by_dir = directory_counts(folder)
        {
          concepts: entries.size,
          dirs: by_dir.size,
          top_dirs: by_top_dir.size,
          types: by_type.size,
          cross_links: graph.edges.size,
          tags: graph.tag_index.size,
          by_type: by_type,
          by_dir: by_dir,
          by_top_dir: by_top_dir
        }
      end

      # Every directory the bundle has, with the concepts that live *directly* in
      # it. Read off Bundle#directory_index — the same map `okf dirs` lists and
      # `--dir` is answered against — rather than off the catalog, which knows
      # only the directories that happen to hold a concept. Grouping the catalog
      # made `stats` and `dirs` report different totals for one bundle, and left
      # an addressable directory out of by_dir entirely: `--dir deeply` answers,
      # but nothing in `stats` said `deeply` was there to ask about.
      #
      # A directory holding nothing directly therefore appears at 0. That is the
      # honest reading — it is the same zero `okf dirs` prints in its Concepts
      # column — and it keeps `dirs` equal to `by_dir.size`. Ties break by path so
      # the order is total, not whatever the sort happened to leave.
      def directory_counts(folder)
        folder.directory_index
              .map { |entry| [ entry[:dir], entry[:count] ] }
              .sort_by { |dir, count| [ -count, dir ] }.to_h
      end

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
