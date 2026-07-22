# frozen_string_literal: true

module OKF
  class CLI
    # The bundle's directories — its clusters — and how many concepts live
    # directly in each. The shape view: `index` reads a directory's contents,
    # `dirs` reads the layout they hang off, which is the question `--dir` is
    # answered against.
    #
    # `count` is *direct*, never cumulative: a dir's number is what lives in it,
    # so the column sums to the bundle's concept count and an empty intermediate
    # dir reads as the zero it is. `subtree` is the other half of that honesty —
    # what `--dir <that row>` would return — because a direct count alone cannot
    # say where the mass is once `--depth` truncates the listing: on a deep
    # bundle the top-level rows are then all zeroes.
    #
    # Presentation only — every number comes off Bundle#directory_index, the same
    # source `okf index` and the server's Index panel read. Advisory: exit 0.
    class Dirs < Command
      def self.id
        :dirs
      end

      def self.group
        :read
      end

      def self.help_rows
        [
          [ "dirs      <dir|@slug> [--json] [--dir D] [--depth N]", "list the bundle's dirs (clusters) and their concept counts" ]
        ]
      end

      def call(argv)
        options = { json: false, dirs: nil, depth: nil, ancestors: true }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf dirs <dir|@slug> [--dir PATH] [--depth N] [--json]"
          json_flags(o, options, "emit the dirs as JSON")
          projection_flags(o, options)
          o.on("--dir PATH", "only this directory and the ones below it",
            "(repeatable; `root` for the bundle root)") { |v| (options[:dirs] ||= []) << v }
          depth_flag(o, options)
          ancestors_flag(o, options)
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2
        bad_depth = depth_error(options)
        return bad_depth if bad_depth

        folder = OKF::Bundle::Folder.load(dir)
        report_skipped(folder)
        rows = select_rows(folder.directory_index, options)
        return emit_list_json(dir, "dirs", rows, options, "total" => total(rows)) if options[:json]

        print_dirs(dir, rows)
        0
      end

      private

      # The subtree counts come off the *whole* map, before any narrowing — a
      # truncated view still has to report the real weight hanging below a row,
      # which is the only reason the column exists.
      def select_rows(entries, options)
        subtree = subtree_counts(entries)
        all_dirs = entries.map { |entry| entry[:dir] }
        wanted = select_dirs(all_dirs, options)
        chain = ancestor_dirs(options, all_dirs) - wanted
        entries.select { |entry| wanted.include?(entry[:dir]) || chain.include?(entry[:dir]) }.map do |entry|
          { "dir" => entry[:dir], "ancestor" => chain.include?(entry[:dir]), "count" => entry[:count],
            "subtree" => subtree[entry[:dir]], "subdirs" => entry[:subdirs] }
        end
      end

      # Per dir, the concepts at or below it — defined as exactly what `--dir` on
      # that row selects, so the number on the row and the flag can never
      # disagree. Which is also why the root's subtree is its own direct count:
      # `.` is a prefix of nothing, the same rule `--dir .` is built on.
      def subtree_counts(entries)
        entries.each_with_object({}) do |entry, out|
          out[entry[:dir]] = entries.reduce(0) do |sum, other|
            under_dir?(other[:dir], entry[:dir]) ? sum + other[:count] : sum
          end
        end
      end

      # The chain is context, not the answer, so it stays out of the total —
      # which is what keeps a row's `subtree` equal to the total `--dir` on that
      # row returns. `count` in the envelope is rows printed, chain included,
      # because that is what it has always meant: how many rows came back.
      def total(rows)
        rows.reject { |row| row["ancestor"] }.map { |row| row["count"] }.reduce(0, :+)
      end

      # `.` is the stored value and "(root)" the human one — the same split every
      # grouped view keeps, so a table and its --json never disagree about which
      # spelling is the data.
      def print_dirs(dir, rows)
        @out.puts "Dirs — #{bundle_label(dir)}"
        @out.puts
        labels = rows.map { |row| "#{"↑ " if row["ancestor"]}#{dir_label(row["dir"])}" }
        # The second column earns its place only where a dir actually nests. On a
        # flat bundle it would repeat the first one down the page.
        nested = rows.any? { |row| row["subtree"] != row["count"] }
        unless rows.empty?
          width = [ 3, *labels.map(&:length) ].max
          @out.puts "  #{"Dir".ljust(width)}  Concepts#{"   Subtree" if nested}"
          rows.each_with_index do |row, i|
            line = "  #{labels[i].ljust(width)}  #{row["count"].to_s.rjust(8)}"
            line += "   #{row["subtree"].to_s.rjust(7)}" if nested
            @out.puts line
          end
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
