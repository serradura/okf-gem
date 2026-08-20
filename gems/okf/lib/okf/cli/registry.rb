# frozen_string_literal: true

module OKF
  class CLI
    # The registry umbrella, split by what each verb keys on. `set`/`del`/`list`
    # act on entries — `set` keys on the bundle's path, so --as means one thing
    # ("the slug this entry has") whether it adds or renames. `default`/`rename`
    # act on slugs, the names actually to hand once a bundle is registered. Every
    # positional stays unambiguous, and `config` is left free for real settings.
    class Registry < Command
      # The `registry` umbrella's subcommands — the dispatch, and the words a
      # flag-first invocation is checked against.
      SUBCOMMANDS = %w[init set del list default rename group ungroup].freeze

      def self.id
        :registry
      end

      def self.group
        :registry
      end

      def self.help_rows
        [
          [ "registry  init", "create a project-local .okf-registry.json (nearest one wins)" ],
          [ "registry  list [--json]", "list registered bundles (* marks the default)" ],
          [ "registry  set <dir|@slug> [--as SLUG] [--default]", "add or update a bundle (a bare `server` serves them)" ],
          [ "registry  del <dir|@slug>", "remove a bundle or group from the registry" ],
          [ "registry  default <@slug>", "move a bundle to the front (the default)" ],
          [ "registry  rename <@slug> <new>", "rename a bundle or group (<new> is a new name, not a ref)" ],
          [ "registry  group <slug> <@member…>", "create a group, or add members (search/server can target @slug)" ],
          [ "registry  ungroup <slug> <@member…>", "remove members from a group (emptying it deletes it)" ]
        ]
      end

      def call(argv)
        require "okf/registry"

        sub = argv.first
        case sub
        when "init" then registry_init(argv.drop(1))
        when "set" then registry_set(argv.drop(1))
        when "del" then registry_del(argv.drop(1))
        when "list" then registry_list(argv.drop(1))
        when "default" then registry_default(argv.drop(1))
        when "rename" then registry_rename(argv.drop(1))
        when "group" then registry_group(argv.drop(1))
        when "ungroup" then registry_ungroup(argv.drop(1))
        else
          # A bare word that isn't a known subcommand is a typo (`registry remove x`
          # must not silently render the list and read as success).
          return usage_error("unknown registry subcommand '#{sub}' (expected: #{SUBCOMMANDS.join(", ")})") if sub && !sub.start_with?("-")

          # Same rule for a subcommand hiding behind a flag: `registry --json set
          # dir` would otherwise list an empty registry and exit 0, having written
          # nothing the user asked for. It cannot just be dispatched from wherever
          # it turns up — the word may be a flag's value (`registry --as set <dir>`
          # asks for the slug "set"), and a grammar where that reading depends on
          # which flag precedes it is a trapdoor. So the subcommand must lead, and
          # the error says which one was found rather than guessing at the intent.
          stray = argv.find { |arg| SUBCOMMANDS.include?(arg) }
          return usage_error("put the subcommand first: okf registry #{stray} … (flags follow it)") if stray

          registry_list(argv)
        end
      end

      private

      # Create a project-local .okf-registry.json in the current directory. Once it
      # exists, discovery finds it (walking up from cwd) and every registry op —
      # and every @ref — resolves through it instead of the global $OKF_HOME one.
      # init only writes the empty file; `registry set` fills it. Refuses to clobber
      # an existing local registry, and notes a parent one it would shadow.
      def registry_init(argv)
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf registry init"
          help_flag(o)
        end
        parser.parse!(argv)
        no_extras?(argv) or return 2

        target = File.join(Dir.pwd, OKF::Registry::LOCAL_FILE)
        display = "./#{OKF::Registry::LOCAL_FILE}"
        return usage_error("already initialized: #{display}") if File.exist?(target)

        # The parent it would shadow, if any — a courtesy, not a barrier: nested
        # registries resolve nearest-first, so creating one here is legitimate.
        parent = OKF::Registry.discover(File.dirname(Dir.pwd))
        @err.puts "note: a parent registry at #{parent} — the nearest one wins" if parent

        OKF::Registry.new(target).save
        @out.puts "initialized #{display}"
        0
      rescue OptionParser::ParseError => e
        @err.puts e.message
        2
      rescue OKF::Error => e
        usage_error(e.message)
      end

      # Add a bundle to the persistent registry (so a later bare `okf server` finds
      # it), or update one already there. The entry is keyed by the bundle's path: a
      # path already registered refreshes its title in place, and --as renames it. A
      # new path is added, slugged by directory basename unless --as says otherwise.
      def registry_set(argv)
        options = { as: nil, default: false }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf registry set <dir|@slug> [--as SLUG] [--default]"
          o.on("--as SLUG", "slug to register under (default: directory basename)") { |v| options[:as] = v }
          o.on("--default", "put it first — the bundle a bare `okf server` opens") { options[:default] = true }
          help_flag(o)
        end
        # No no_extras? here: positional_dir has already refused a trailing
        # argument. The sibling subcommands need the call because they take their
        # positional through `positional`, which does not check.
        dir = positional_dir(parser, argv) or return 2

        reg = open_registry
        # Said before the upsert: after it, an update is indistinguishable from an
        # add, and "registered" for what was a rename reads as a duplicate entry.
        known = reg.listing.any? { |row| row[:dir] == File.expand_path(dir) }
        entry = reg.add(dir, as: options[:as], default: options[:default])
        # Through report_skipped like every other bundle-reading verb: the reader
        # tolerates a file it cannot open, so a count taken straight off the graph
        # reports "0 concepts" for a bundle whose files are simply unreadable.
        folder = OKF::Bundle::Folder.load(entry.path)
        report_skipped(folder)
        count = folder.graph(minimal: true).nodes.size
        @out.puts "#{known ? "updated" : "registered"} #{entry.slug} → #{entry.path} (#{count} #{pluralize(count, "concept")})"
        0
      rescue OKF::Error => e
        usage_error(e.message)
      end

      # Remove a bundle from the persistent registry by slug or by its directory.
      def registry_del(argv)
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf registry del <dir|@slug>"
          help_flag(o)
        end
        slug = positional(parser, argv) or return 2
        no_extras?(argv) or return 2

        reg = open_registry
        slug = registry_slug(slug, reg) or return 2
        removed = reg.remove(slug)
        return usage_error("no such bundle: #{slug}") unless removed

        @out.puts "removed #{removed.slug}"
        0
      rescue OKF::Error => e
        usage_error(e.message)
      end

      def registry_list(argv)
        options = { json: false }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf registry list [--json] [--pretty]\n       " \
                     "okf registry set <dir|@slug> | del <dir|@slug> | default <@slug> | rename <@slug> <new>"
          json_flags(o, options, "emit the registry as JSON")
          help_flag(o)
        end
        begin
          parser.parse!(argv)
        rescue OptionParser::ParseError => e
          @err.puts e.message
          return 2
        end
        no_extras?(argv) or return 2

        reg = open_registry
        if options[:json]
          groups = { "groups" => reg.groups_listing.map { |row| stringify(row) } }
          return emit_list_json({ "registry" => reg.path }, "bundles", reg.listing.map { |row| stringify(row) }, options, groups)
        end

        print_registry(reg)
        0
      rescue OKF::Error => e
        usage_error(e.message)
      end

      # Choose which registered bundle a bare `okf server` opens at `/`, by moving
      # it to the front of the registry. The listing is ordered and the JSON is
      # meant to be hand-editable, so the move is stated rather than left to be
      # discovered from a reordered file.
      def registry_default(argv)
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf registry default <@slug>\n       " \
                     "moves it to the front — the first registered bundle is the default until you do"
          help_flag(o)
        end
        slug = positional(parser, argv) or return 2
        no_extras?(argv) or return 2

        reg = open_registry
        slug = registry_slug(slug, reg) or return 2
        reg.default = slug
        @out.puts "default bundle → #{reg.default.slug} (now first)"
        0
      rescue OKF::Error => e
        usage_error(e.message)
      end

      # The @ref grammar for a verb that takes a *slug*, read by name. These three
      # must reach an entry whose directory is gone — that is the one worth
      # deleting or renaming — so they cannot go through resolve_ref, which
      # insists the directory exist. Without this the refs only appeared to work:
      # `normalize` strips the `@` off `@slug`, so `default @slug` resolved by
      # accident while a bare `@` normalized to "" and failed. Returns the slug,
      # or nil after reporting.
      def registry_slug(arg, registry)
        return arg unless arg.start_with?("@")

        asked = arg[1..-1]
        return asked unless asked.empty?

        default = registry.default
        return default.slug if default

        @err.puts "error: no bundle is registered, so `@` names nothing (okf registry set <dir>)"
        nil
      end

      # Rename a registered bundle's slug — its mount path and switcher name.
      def registry_rename(argv)
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf registry rename <@slug> <new>"
          help_flag(o)
        end
        parser.parse!(argv)
        old_slug, new_slug = argv.shift(2)
        if old_slug.nil? || new_slug.nil?
          @err.puts parser.banner
          return 2
        end
        no_extras?(argv) or return 2

        reg = open_registry
        # The old name may be a ref; the new one is a name being minted, never one.
        old_slug = registry_slug(old_slug, reg) or return 2
        entry = reg.rename(old_slug, new_slug)
        # The slug it *found*, not the argv that found it: rename normalizes to look
        # the entry up, so echoing the raw ask names a bundle that never existed.
        @out.puts "renamed #{OKF::Registry.normalize(old_slug)} → #{entry.slug}"
        0
      rescue OptionParser::ParseError => e
        @err.puts e.message
        2
      rescue OKF::Error => e
        usage_error(e.message)
      end

      # Create a group, or add members to one. Members are bundle or group slugs,
      # bare or as @refs; the model normalizes, unions, checks each names something,
      # and refuses a cycle. Only `search`/`server` can then target @slug.
      def registry_group(argv)
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf registry group <slug> <@member…>"
          help_flag(o)
        end
        parser.parse!(argv)
        slug = argv.shift
        if slug.nil? || argv.empty?
          @err.puts parser.banner
          return 2
        end

        reg = open_registry
        group = reg.set_group(slug, argv)
        count = reg.expand(group.slug).size
        @out.puts "grouped #{group.slug} → #{group.members.map { |m| "@#{m}" }.join(", ")} " \
                  "(#{count} #{pluralize(count, "bundle")})"
        0
      rescue OptionParser::ParseError => e
        @err.puts e.message
        2
      rescue OKF::Error => e
        usage_error(e.message)
      end

      # Remove members from a group. Emptying it deletes the group — an empty group
      # resolves to nothing, so it is not worth keeping.
      def registry_ungroup(argv)
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf registry ungroup <slug> <@member…>"
          help_flag(o)
        end
        parser.parse!(argv)
        slug = argv.shift
        if slug.nil? || argv.empty?
          @err.puts parser.banner
          return 2
        end

        reg = open_registry
        removed, emptied = reg.unset_group_members(slug, argv)
        name = OKF::Registry.normalize(slug)
        if emptied
          @out.puts "removed empty group #{name}"
        elsif removed.empty?
          @out.puts "no members removed from #{name} (none of #{argv.join(", ")} were in it)"
        else
          @out.puts "ungrouped #{removed.map { |m| "@#{m}" }.join(", ")} from #{name}"
        end
        0
      rescue OptionParser::ParseError => e
        @err.puts e.message
        2
      rescue OKF::Error => e
        usage_error(e.message)
      end

      def print_registry(reg)
        # A header only when a project-local registry is in play — the case where
        # "which registry am I looking at?" is a real question. The global $OKF_HOME
        # one is the default, so it stays headerless (and the JSON envelope names
        # the file for a script either way).
        @out.puts "registry: #{registry_display(reg)}" if local_registry?(reg)
        groups = reg.groups_listing
        return @out.puts "no bundles registered — okf registry set <dir>" if reg.empty? && groups.empty?

        rows = reg.listing
        unless rows.empty?
          width = rows.map { |row| row[:slug].length }.max
          rows.each do |row|
            marker = row[:default] ? "*" : " "
            missing = row[:missing] ? "  (missing)" : ""
            @out.puts "#{marker} #{row[:slug].ljust(width)}  #{row[:title]}  (#{row[:dir]})#{missing}"
          end
        end
        print_groups(groups, rows) unless groups.empty?
      end

      # Whether this registry was discovered as a project-local file rather than
      # read from $OKF_HOME — the basename settles it (only a local one is named
      # .okf-registry.json).
      def local_registry?(reg)
        File.basename(reg.path) == OKF::Registry::LOCAL_FILE
      end

      # How to name the local registry in the header: `./` when it sits in cwd
      # (the common case, a bare `init` here), its absolute path when discovery
      # walked up to an ancestor.
      def registry_display(reg)
        File.dirname(reg.path) == Dir.pwd ? "./#{OKF::Registry::LOCAL_FILE}" : reg.path
      end

      # The groups section under the bundle listing: one row per group, its members
      # and how many bundles it resolves to (a hand-edited cycle shows `(cycle)`).
      def print_groups(groups, rows)
        @out.puts "" unless rows.empty?
        @out.puts "groups:"
        width = groups.map { |group| group[:slug].length }.max
        groups.each do |group|
          members = group[:members].map { |m| "@#{m}" }.join(", ")
          count = group[:resolved].nil? ? "cycle" : "#{group[:resolved]} #{pluralize(group[:resolved], "bundle")}"
          @out.puts "  #{group[:slug].ljust(width)}  #{members}  (#{count})"
        end
      end
    end

    register(Registry)
  end
end
