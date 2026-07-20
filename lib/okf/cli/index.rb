# frozen_string_literal: true

module OKF
  class CLI
    # The progressive-disclosure map (spec §6): every directory that holds concepts
    # or carries an index.md, with its authored index body, a type/tag rollup, its
    # child directories, and — for a directory with no index.md — the listing
    # synthesized from the concepts there. The "orient before you read" view. `--area`
    # is repeatable (one or many directories; `root` is the bundle root); `--no-body`
    # drops the prose to a skeleton; advisory, exit 0.
    class Index < Command
      def self.id
        :index
      end

      def self.group
        :read
      end

      def self.help_rows
        [
          [ "index     <dir|@slug> [--json] [--area A] [--no-body]", "the index map: dirs, their listings and rollups" ]
        ]
      end

      def call(argv)
        options = { json: false, body: true, areas: nil }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf index <dir|@slug> [--area AREA] [--no-body] [--json]"
          json_flags(o, options, "emit the index map as JSON")
          projection_flags(o, options)
          o.on("--area AREA", "only this directory/area (repeatable; `root` for the bundle root)") { |v| (options[:areas] ||= []) << v }
          o.on("--[no-]body", "include each index's prose body (default: yes)") { |v| options[:body] = v }
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        folder = OKF::Bundle::Folder.load(dir)
        report_skipped(folder)
        entries = folder.directory_index
        selected = select_directories(entries, options[:areas])
        if options[:json]
          # --no-body is shorthand for --except body, so asking for the body by
          # name in the same breath is a contradiction. Letting --fields quietly
          # win would hand back the very thing the other flag was there to drop.
          if !options[:body] && Array(options[:fields]).map(&:downcase).include?("body")
            return usage_error("--no-body and --fields body contradict each other: drop one")
          end

          options[:except] = Array(options[:except]) + [ "body" ] unless options[:body] || options[:fields]
          return print_index_map_json(dir, selected, options)
        end
        print_index_map(dir, selected, options[:body])
        0
      end

      private

      # Narrow the map to the named directories/areas — case-insensitive, `root`
      # matching the bundle root (".") so no shell quoting is needed. No --area passed
      # keeps the whole map.
      def select_directories(entries, areas)
        return entries if areas.nil? || areas.empty?

        wanted = areas.map { |area| area.downcase == "root" ? "." : area.downcase }
        entries.select { |entry| wanted.include?(entry[:dir].downcase) }
      end

      def print_index_map(dir, entries, body)
        noun = entries.size == 1 ? "directory" : "directories"
        @out.puts "Index map — #{bundle_label(dir)} (#{entries.size} #{noun})"
        entries.each do |entry|
          @out.puts
          @out.puts "  #{index_dir_label(entry)}#{index_dir_meta(entry)}"
          subdirs = entry[:subdirs]
          @out.puts "    → #{subdirs.map { |sub| "#{File.basename(sub)}/" }.join("  ")}" unless subdirs.empty?
          if entry[:present]
            print_index_body(entry[:body]) if body
          else
            print_synthesized_listing(entry[:listing])
          end
        end
      end

      def index_dir_label(entry)
        base = entry[:dir] == "." ? "(root)" : "#{entry[:dir]}/"
        entry[:present] ? base : "#{base}  (no index.md)"
      end

      def index_dir_meta(entry)
        count = "#{entry[:count]} #{pluralize(entry[:count], "concept")}"
        types = entry[:types].map { |type, n| "#{OKF.blank?(type) ? "Untyped" : type} #{n}" }.join(", ")
        types.empty? ? "  ·  #{count}" : "  ·  #{count} · #{types}"
      end

      def print_index_body(body)
        text = body.to_s.strip
        return if text.empty?

        text.each_line { |line| @out.puts "    #{line.chomp}" }
      end

      def print_synthesized_listing(listing)
        listing.each do |item|
          suffix = item[:description].empty? ? "" : " — #{truncate(item[:description], 72)}"
          @out.puts "    • #{item[:title]}#{suffix}"
        end
      end

      def print_index_map_json(dir, entries, options)
        emit_list_json(dir, "directories", entries.map { |entry| index_map_entry_json(entry) }, options)
      end

      def index_map_entry_json(entry)
        {
          "dir" => entry[:dir], "index_path" => entry[:index_path],
          "present" => entry[:present], "synthesized" => entry[:synthesized],
          "count" => entry[:count], "types" => entry[:types], "tags" => entry[:tags],
          "subdirs" => entry[:subdirs], "body" => entry[:body],
          "listing" => entry[:listing].map { |item| stringify(item) }
        }
      end
    end

    register(Index)
  end
end
