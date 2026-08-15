# frozen_string_literal: true

module OKF
  class CLI
    # The §6.3 inventory: every file under `references/`, which concepts cite
    # it through the §6.2 path-valued fields, and the pointers into
    # `references/` that resolve to nothing — with the leading-slash fix named
    # when a bare path written from a subdirectory is what missed. An advisory
    # read (exit 0): what a curator acts on lives in the output, never the
    # status.
    class References < Command
      def self.id
        :references
      end

      def self.group
        :read
      end

      def self.help_rows
        [
          [ "references <dir|@slug> [--json]", "inventory references/ files and the concepts citing them" ]
        ]
      end

      def call(argv)
        options = { json: false }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf references <dir|@slug> [--json]"
          json_flags(o, options, "emit the inventory as JSON")
          projection_flags(o, options)
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        folder = OKF::Bundle::Folder.load(dir)
        report_skipped(folder)
        references = folder.references
        return print_references_json(dir, references, options) if options[:json]

        print_references(dir, references)
        0
      end

      private

      def print_references(dir, references)
        entries = references.entries
        @out.puts "References — #{bundle_label(dir)} (#{entries.size} #{pluralize(entries.size, "file")})"
        @out.puts "  (none)" if entries.empty?
        entries.group_by { |entry| entry[:dir] }.sort_by(&:first).each do |folder, group|
          width = group.map { |entry| File.basename(entry[:path]).length }.max
          @out.puts
          @out.puts "  #{folder}/"
          group.each do |entry|
            @out.puts "    #{File.basename(entry[:path]).ljust(width)}  #{entry_note(entry)}"
          end
        end
        print_dangling(references.dangling)
      end

      def entry_note(entry)
        marker = entry[:kind] == "concept" ? "[concept]  " : ""
        cited = entry[:referenced_by]
        return "#{marker}(unreferenced)" if cited.empty?

        "#{marker}← #{cited.map { |ref| "#{ref[:id]} (#{ref[:field]})" }.join(", ")}"
      end

      def print_dangling(rows)
        return if rows.empty?

        @out.puts
        @out.puts "  dangling pointers:"
        rows.each do |row|
          @out.puts "    #{row[:id]} — #{row[:field]}: #{row[:raw]}"
          line = "      resolves to #{row[:resolved]}, which does not exist"
          # hint is only ever the leading-slash fix, so the human line can name
          # the spelling that would have hit without restating the sentence.
          line += " — /#{row[:raw]} does (missing leading slash?)" if row[:hint]
          @out.puts line
        end
      end

      def print_references_json(dir, references, options)
        rows = references.entries.map do |entry|
          { "path" => entry[:path], "dir" => entry[:dir], "kind" => entry[:kind],
            "referenced_by" => entry[:referenced_by].map { |ref| stringify(ref) } }
        end
        dangling = references.dangling.map { |row| stringify(row) }
        emit_list_json(dir, "references", rows, options, "dangling" => dangling)
      end
    end

    register(References)
  end
end
