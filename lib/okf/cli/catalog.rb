# frozen_string_literal: true

module OKF
  class CLI
    # Every concept with its metadata, grouped by top-level dir. The widest of the
    # read views, and the one the others narrow down from.
    class Catalog < Command
      def self.id
        :catalog
      end

      def self.group
        :read
      end

      def self.help_rows
        [
          [ "catalog   <dir|@slug> [--json] [filters]", "list concepts with metadata, by top-level dir" ]
        ]
      end

      def call(argv)
        options = { json: false }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf catalog <dir|@slug> [--type T] [--dir D] [--tag T] [--json]"
          json_flags(o, options, "emit the catalog as JSON")
          projection_flags(o, options)
          filter_flags(o, options, :type, :area, :tag)
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        folder = OKF::Bundle::Folder.load(dir)
        report_skipped(folder)
        entries = folder.catalog
        selected = filter_entries(entries, options)
        return print_catalog_json(dir, selected, options) if options[:json]

        print_catalog(dir, selected, entries.size)
        0
      end

      private

      def print_catalog(dir, entries, total)
        @out.puts "Catalog — #{bundle_label(dir)} (#{counted(entries.size, total, "concept")})"
        entries.group_by { |entry| entry[:top_dir] }.sort_by(&:first).each do |top_dir, group|
          @out.puts
          @out.puts "  #{top_dir == "(root)" ? "(root)" : "#{top_dir}/"} (#{group.size})"
          group.each do |entry|
            links = entry[:links_out] + entry[:links_in]
            meta = [ entry[:type], (links.positive? ? "↳#{links}" : nil), entry[:status] ].compact.join("  ·  ")
            @out.puts "    #{entry[:title]}  ·  #{meta}"
            @out.puts "      #{truncate(entry[:description], 92)}" unless entry[:description].empty?
          end
        end
      end

      def print_catalog_json(dir, entries, options)
        emit_list_json(dir, "concepts", entries.map { |entry| stringify(entry) }, options)
      end
    end

    register(Catalog)
  end
end
