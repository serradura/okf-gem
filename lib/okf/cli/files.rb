# frozen_string_literal: true

module OKF
  class CLI
    # Every file with its title, grouped by folder — the view for "what is on disk"
    # rather than "what is modelled".
    class Files < Command
      def self.id
        :files
      end

      def self.group
        :read
      end

      def self.help_rows
        [
          [ "files     <dir|@slug> [--json] [filters]", "list files with titles, by folder" ]
        ]
      end

      def call(argv)
        options = { json: false }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf files <dir|@slug> [--type T] [--area A] [--tag T] [--json]"
          json_flags(o, options, "emit the file tree as JSON")
          projection_flags(o, options)
          filter_flags(o, options, :type, :area, :tag)
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        folder = OKF::Bundle::Folder.load(dir)
        report_skipped(folder)
        entries = folder.catalog
        selected = filter_entries(entries, options)
        return print_files_json(dir, selected, options) if options[:json]

        print_files(dir, selected, entries.size)
        0
      end

      private

      def print_files(dir, entries, total)
        @out.puts "Files — #{bundle_label(dir)} (#{counted(entries.size, total, "file")})"
        entries.group_by { |entry| entry[:dir] }.sort_by(&:first).each do |folder, group|
          width = group.map { |entry| File.basename("#{entry[:id]}.md").length }.max
          @out.puts
          @out.puts "  #{folder == "." ? "(root)" : "#{folder}/"}"
          group.each do |entry|
            @out.puts "    #{File.basename("#{entry[:id]}.md").ljust(width)}  #{entry[:title]}"
          end
        end
      end

      def print_files_json(dir, entries, options)
        files = entries.map do |entry|
          { "path" => "#{entry[:id]}.md", "id" => entry[:id], "dir" => entry[:dir], "type" => entry[:type], "title" => entry[:title],
            "description" => entry[:description] }
        end
        emit_list_json(dir, "files", files, options)
      end
    end

    register(Files)
  end
end
