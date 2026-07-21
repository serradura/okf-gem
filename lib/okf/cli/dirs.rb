# frozen_string_literal: true

module OKF
  class CLI
    # The bundle's directories — its clusters — and how many concepts live
    # directly in each. The shape view: `index` reads a directory's contents,
    # `dirs` reads the layout they hang off, which is the question `--dir` is
    # answered against.
    #
    # Counts are *direct*, never cumulative: a dir's number is what lives in it,
    # so the column sums to the bundle's concept count and an empty intermediate
    # dir reads as the zero it is. Presentation only — every number comes off
    # Bundle#directory_index, the same source `okf index` and the server's Index
    # panel read. Advisory: exit 0.
    class Dirs < Command
      def self.id
        :dirs
      end

      def self.group
        :read
      end

      def self.help_rows
        [
          [ "dirs      <dir|@slug> [--json]", "list the bundle's dirs (clusters) and their concept counts" ]
        ]
      end

      def call(argv)
        options = { json: false }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf dirs <dir|@slug> [--json]"
          json_flags(o, options, "emit the dirs as JSON")
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        folder = OKF::Bundle::Folder.load(dir)
        report_skipped(folder)
        rows = folder.directory_index.map { |entry| { "dir" => entry[:dir], "count" => entry[:count], "subdirs" => entry[:subdirs] } }
        return emit_list_json(dir, "dirs", rows, options, "total" => total(rows)) if options[:json]

        print_dirs(dir, rows)
        0
      end

      private

      def total(rows)
        rows.map { |row| row["count"] }.reduce(0, :+)
      end

      # `.` is the stored value and "(root)" the human one — the same split every
      # grouped view keeps, so a table and its --json never disagree about which
      # spelling is the data.
      def print_dirs(dir, rows)
        @out.puts "Dirs — #{bundle_label(dir)}"
        @out.puts
        labels = rows.map { |row| dir_label(row["dir"]) }
        unless rows.empty?
          width = [ 3, *labels.map(&:length) ].max
          @out.puts "  #{"Dir".ljust(width)}  Concepts"
          rows.each_with_index { |row, i| @out.puts "  #{labels[i].ljust(width)}  #{row["count"].to_s.rjust(8)}" }
          @out.puts
        end
        @out.puts "  #{rows.size} #{pluralize(rows.size, "dir")} · #{total(rows)} #{pluralize(total(rows), "concept")}"
      end

      def dir_label(dir)
        dir == "." ? "(root)" : dir
      end
    end

    register(Dirs)
  end
end
