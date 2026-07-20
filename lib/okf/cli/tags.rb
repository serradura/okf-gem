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
          o.banner = "Usage: okf tags <dir|@slug> [--by type|area] [--type T] [--area A] [--json]"
          json_flags(o, options, "emit the tag index as JSON")
          o.on("--by DIM", %w[type area], "group the tags by a concept dimension (type | area)") { |v| options[:by] = v.to_sym }
          filter_flags(o, options, :type, :area)
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        return grouped_tags(dir, options) if options[:by]

        print_inverted_index(dir, "Tags", :tag, "tags", options)
      end

      private

      # `tags --by type|area`: the tag index re-cut per concept type or top-level
      # area, with within-group counts — the curation view. A tag confined to one
      # group at count 1 is scattered; one recurring across groups is connective.
      # The --type/--area filters narrow the concepts first, then the grouping cuts.
      def grouped_tags(dir, options)
        folder = OKF::Bundle::Folder.load(dir)
        report_skipped(folder)
        graph = folder.graph(minimal: true)
        titles = graph.nodes.map { |node| [ node[:id], node[:title] ] }.to_h
        groups = tag_groups(graph.tag_index, folder, options)
        options[:json] ? print_grouped_tags_json(dir, options[:by], groups) : print_grouped_tags(dir, options[:by], groups, titles)
        0
      end

      # [ [ group, rows ], … ] — groups sorted by name, rows shaped like index_rows'.
      # A tag carried in several groups appears in each, counted per group.
      def tag_groups(tag_index, folder, options)
        by_id = filter_entries(folder.catalog, options).map { |entry| [ entry[:id], entry ] }.to_h
        groups = {}
        tag_index.each do |tag, ids|
          ids.each do |id|
            entry = by_id[id]
            next if entry.nil?

            key = options[:by] == :type ? entry_type(entry) : entry[:area]
            ((groups[key] ||= {})[tag] ||= []) << id
          end
        end
        groups.map do |key, tags|
          rows = tags.map { |tag, ids| { tag: tag, count: ids.length, concepts: ids } }
                     .sort_by { |row| [ -row[:count], row[:tag] ] }
          [ key, rows ]
        end.sort_by(&:first)
      end

      # A catalog entry's type for display — "Untyped" when blank, matching the graph.
      def entry_type(entry)
        OKF.blank?(entry[:type]) ? "Untyped" : entry[:type]
      end

      def print_grouped_tags(dir, dim, groups, titles)
        @out.puts "Tags — #{bundle_label(dir)} (#{distinct_tags(groups)} distinct, by #{dim})"
        groups.each do |key, rows|
          label = dim == :area && key != "(root)" ? "#{key}/" : key
          @out.puts
          @out.puts "  #{label} (#{rows.size} #{pluralize(rows.size, "tag")})"
          width = rows.map { |row| row[:tag].length }.max || 0
          rows.each do |row|
            names = row[:concepts].map { |id| titles[id] || id }.join(", ")
            @out.puts "    #{row[:tag].ljust(width)}  #{row[:count].to_s.rjust(3)}   #{truncate(names, 76)}"
          end
        end
      end

      def print_grouped_tags_json(dir, dim, groups)
        groups_json = groups.map do |key, rows|
          { dim.to_s => key, "count" => rows.size, "tags" => index_rows_json(:tag, rows) }
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
