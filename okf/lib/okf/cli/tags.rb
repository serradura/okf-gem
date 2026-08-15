# frozen_string_literal: true

module OKF
  class CLI
    # The tag index: which tags exist, how often, and on what. --by regroups them
    # per concept dimension, which is the view for curating a vocabulary rather
    # than reading one.
    class Tags < Command
      def self.id
        :tags
      end

      def self.group
        :read
      end

      def self.help_rows
        [
          [ "tags      <dir|@slug> [--json] [--by DIM] [filters]", "list tags with their concepts, by count" ]
        ]
      end

      def call(argv)
        options = { json: false, by: nil }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf tags <dir|@slug> [--by type|dir] [--type T] [--dir D] [--status S] [--trust T] [--json]"
          json_flags(o, options, "emit the tag index as JSON")
          o.on("--by DIM", %w[type dir area], "group the tags by a concept dimension (type | dir)") do |v|
            options[:by] = v.to_sym
            deprecated("--by area", "--by dir") if options[:by] == :area
          end
          filter_flags(o, options, :type, :area)
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        return grouped_tags(dir, options) if options[:by]

        print_inverted_index(dir, "Tags", :tag, "tags", options)
      end

      private

      # `tags --by type|dir`: the tag index re-cut per concept type or directory,
      # with within-group counts — the curation view. A tag confined to one
      # group at count 1 is scattered; one recurring across groups is connective.
      # The --type/--dir filters narrow the concepts first, then the grouping cuts.
      def grouped_tags(dir, options)
        folder = OKF::Bundle::Folder.load(dir)
        report_skipped(folder)
        graph = folder.graph(minimal: true)
        titles = graph.nodes.map { |node| [ node[:id], node[:title] ] }.to_h
        groups = folder.tag_groups(by: options[:by],
          entries: filter_entries(folder.catalog, options, dir_scope(folder, options)))
        options[:json] ? print_grouped_tags_json(dir, options[:by], groups) : print_grouped_tags(dir, options[:by], groups, titles)
        0
      end

      # The grouping itself is Bundle#tag_groups — one home, shared with the
      # MCP shell; this layer keeps only what is the CLI's own, the filter
      # narrowing passed through `entries:`.

      # `.` prints "(root)" bare; every other dir carries the trailing slash that
      # says it is one. The deprecated --by area already stores "(root)" itself.
      def group_label(key, dim)
        return key if dim == :type

        dir_label(key, slash: true)
      end

      def print_grouped_tags(dir, dim, groups, titles)
        @out.puts "Tags — #{bundle_label(dir)} (#{distinct_tags(groups)} distinct, by #{dim})"
        groups.each do |key, rows|
          label = group_label(key, dim)
          @out.puts
          @out.puts "  #{label} (#{rows.size} #{pluralize(rows.size, "tag")})"
          width = rows.map { |row| row[:tag].length }.max || 0
          cwidth = [ 3, *rows.map { |row| count_cell(row).length } ].max
          rows.each do |row|
            names = row[:concepts].map { |id| titles[id] || id }.join(", ")
            @out.puts "    #{row[:tag].ljust(width)}  #{count_cell(row).rjust(cwidth)}   #{truncate(names, 76)}"
          end
        end
      end

      # "2/3" when the tag spreads beyond this group, the plain count when it is
      # local — so equality (locality 1.0) reads by absence.
      def count_cell(row)
        row[:count] == row[:total] ? row[:count].to_s : "#{row[:count]}/#{row[:total]}"
      end

      def print_grouped_tags_json(dir, dim, groups)
        groups_json = groups.map do |key, rows|
          rows_json = rows.map { |row| { "tag" => row[:tag], "count" => row[:count], "total" => row[:total], "concepts" => row[:concepts] } }
          { dim.to_s => key, "count" => rows.size, "tags" => rows_json }
        end
        emit_json(bundle_head(dir).merge("count" => distinct_tags(groups), "by" => dim.to_s, "groups" => groups_json))
      end

      def distinct_tags(groups)
        groups.flat_map { |_, rows| rows.map { |row| row[:tag] } }.uniq.size
      end
    end

    register(Tags)
  end
end
