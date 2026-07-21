# frozen_string_literal: true

module OKF
  class CLI
    # The progressive-disclosure map (spec §6): every directory that holds concepts
    # or carries an index.md, with its authored index body, a type/tag rollup, its
    # child directories, and — for a directory with no index.md — the listing
    # synthesized from the concepts there. The "orient before you read" view. `--dir`
    # is repeatable and selects a directory *and its subtree* (`root` is the bundle
    # root), `--depth N` bounds how far below the starting point that goes, and
    # `--no-body` drops the prose to a skeleton; advisory, exit 0.
    #
    # The two narrowings are what make the map usable on a deep bundle: every
    # directory is a section, so a few hundred concepts is a map nobody reads at
    # once. `--depth 1` is the top of the tree, `--dir X --depth 1` is one branch
    # of it, and the pair walks down a level at a time.
    class Index < Command
      def self.id
        :index
      end

      def self.group
        :read
      end

      def self.help_rows
        [
          [ "index     <dir|@slug> [--dir D] [--depth N] [--no-body]", "the index map: dirs, their listings and rollups" ]
        ]
      end

      def call(argv)
        options = { json: false, body: true, dirs: nil, areas: nil, depth: nil, ancestors: true }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf index <dir|@slug> [--dir PATH] [--depth N] [--no-body] [--json]"
          json_flags(o, options, "emit the index map as JSON")
          projection_flags(o, options)
          o.on("--dir PATH", "only this directory and the ones below it",
            "(repeatable; `root` for the bundle root)") { |v| (options[:dirs] ||= []) << v }
          depth_flag(o, options)
          ancestors_flag(o, options)
          o.on("--area AREA", "deprecated: use --dir (this directory exactly)") do |v|
            (options[:areas] ||= []) << v
            deprecated("--area", "--dir")
          end
          o.on("--[no-]body", "include each index's prose body (default: yes)") { |v| options[:body] = v }
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2
        bad_depth = depth_error(options)
        return bad_depth if bad_depth

        folder = OKF::Bundle::Folder.load(dir)
        report_skipped(folder)
        entries = folder.directory_index
        selected, chain = select_directories(entries, options)
        if options[:json]
          # --no-body is shorthand for --except body, so asking for the body by
          # name in the same breath is a contradiction. Letting --fields quietly
          # win would hand back the very thing the other flag was there to drop.
          if !options[:body] && Array(options[:fields]).map(&:downcase).include?("body")
            return usage_error("--no-body and --fields body contradict each other: drop one")
          end

          options[:except] = Array(options[:except]) + [ "body" ] unless options[:body] || options[:fields]
          return print_index_map_json(dir, selected, chain, options)
        end
        print_index_map(dir, selected, chain, options[:body])
        0
      end

      private

      # Narrow the map — case-insensitive, `root` matching the bundle root (".").
      # --dir takes the named directory *and its subtree* and --depth bounds how
      # far below the starting point that reaches, both through the shared
      # select_dirs so the whole CLI answers "which directories?" one way. The
      # deprecated --area keeps its old exact match beside them, because a
      # deprecated flag that quietly widens is worse than one that is merely old.
      # Nothing passed keeps the whole map.
      def select_directories(entries, options)
        areas = Array(options[:areas]).map { |area| fold_dir(area) }
        scoped = !options[:dirs].nil? || !options[:depth].nil?
        return [ entries, [] ] if areas.empty? && !scoped

        all_dirs = entries.map { |entry| entry[:dir] }
        wanted = scoped ? select_dirs(all_dirs, options) : []
        chain = ancestor_dirs(options, all_dirs) - wanted
        selected = entries.select do |entry|
          areas.include?(fold(entry[:dir])) || wanted.include?(entry[:dir]) || chain.include?(entry[:dir])
        end
        [ selected, chain ]
      end

      def print_index_map(dir, entries, chain, body)
        noun = entries.size == 1 ? "directory" : "directories"
        @out.puts "Index map — #{bundle_label(dir)} (#{entries.size} #{noun})"
        entries.each do |entry|
          @out.puts
          # ↑ marks a row the reader did not ask for: it is here to place the
          # branch, not to answer about it.
          up = chain.include?(entry[:dir]) ? "↑ " : ""
          @out.puts "  #{up}#{index_dir_label(entry)}#{index_dir_meta(entry)}"
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

      def print_index_map_json(dir, entries, chain, options)
        rows = entries.map { |entry| index_map_entry_json(entry, chain.include?(entry[:dir])) }
        emit_list_json(dir, "directories", rows, options)
      end

      def index_map_entry_json(entry, ancestor)
        {
          "dir" => entry[:dir], "ancestor" => ancestor, "index_path" => entry[:index_path],
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
