# frozen_string_literal: true

require "optparse"

module OKF
  class CLI
    # What every command inherits: the injected streams, and the shared surface
    # a verb leans on — ref resolution, the flags several of them offer, the
    # JSON emitters, the list-view printers.
    #
    # A command answers four questions about *itself* (.id, .group, .help_rows,
    # .hidden?) and one about a *run* (#call, returning an exit status). That is
    # the whole contract, and it is the same one a plugin implements — there is
    # no second, lesser interface for an addon, because a seam only the base gem
    # can use is not a seam.
    #
    # Privacy is the boundary, the one idea worth taking from Thor without
    # taking Thor: #call is the entire public surface, so a helper added below
    # can never become a verb by accident.
    class Command
      # What .register checks before admitting a command. Checked at
      # registration rather than at dispatch, so a malformed addon fails where
      # it is installed instead of the first time a user types its verb.
      DUCK_TYPE = %i[id group help_rows hidden? new].freeze

      class << self
        # The verb this answers to, as a Symbol. The registry is keyed on it.
        def id
          raise NotImplementedError, "#{self}.id must name the verb it answers to"
        end

        # Where the verb sits in the map `okf help` prints. CLI::GROUPS fixes
        # the order; anything else — which is what a plugin gets by default —
        # falls to the end, under its own heading.
        def group
          :extension
        end

        # [ [ left-column, description ], … ] — one row per line of the map.
        # A list rather than a pair because `registry` is an umbrella: five
        # subcommands under one verb, each of which has to be findable alone.
        def help_rows
          []
        end

        # A command that works but is not advertised.
        def hidden?
          false
        end
      end

      # `runner:` is the server's injected boot seam and `input:` the terminal
      # a full-screen command needs. Both live here rather than on the two
      # commands that want them, so construction is uniform: a plugin is built
      # exactly the way a built-in is, and the CLI needs to know nothing about
      # which is which.
      def initialize(out:, err:, runner: nil, input: nil)
        @out = out
        @err = err
        @runner = runner
        @input = input
        @pretty = false
        @ref_slugs = {}
      end

      # The run. Returns the exit status; it never calls exit, and never writes
      # anywhere but the injected streams.
      def call(argv)
        raise NotImplementedError, "#{self.class} must implement #call(argv) and return an exit status"
      end

      private

      # The terminal, for a command that needs one. Nothing built in does —
      # `okf` is a one-shot tool — but a full-screen addon cannot work without
      # it, and reaching for $stdin behind the CLI's back would put a command
      # outside the stream injection every test depends on.
      attr_reader :input

      # Which slug each @ref resolved to, by absolute path — so a hub built from
      # refs mounts each bundle under its registered slug, not its dir basename.
      # Per command instance, which is per run: a command is built fresh for each
      # dispatch, so the memo cannot outlive the argv that filled it. (It used to
      # need clearing by hand at the top of #run; one command object per run is
      # what retired that.)
      attr_reader :ref_slugs

      # `@all` is a ref, not a flag, and only `search` expands it — but the
      # refusal the other verbs give lives in the shared resolver, so the
      # recognizer has to be shared too.
      def all_ref?(ref)
        require "okf/registry"
        OKF::Registry.normalize(ref[1..-1]) == ALL_REF[1..-1]
      end

      # A registered bundle whose directory cannot be read, noted and skipped.
      # Shared because both the verbs that tolerate a gap — `search @all` and the
      # bundle-less `server` — have to skip it the same way, and say so the same
      # way. A named @slug never lands here: it fails hard instead.
      def skip_registered(entry)
        @err.puts "note: skipping #{entry.slug} — cannot read #{entry.path}"
        nil
      end

      # Nothing left over. The registry subcommands each take a fixed number of
      # positionals, and so does every `<dir>` verb through positional_dir — a
      # trailing argument means the command was misunderstood, not that it can be
      # answered anyway.
      def no_extras?(argv)
        return true if argv.empty?

        @err.puts "error: unexpected argument '#{argv.first}'"
        false
      end

      # ── the read views ──
      # The Catalog / Files / Tags / Stats views the server renders in the browser,
      # reproduced on the CLI so an agent can read the same knowledge without one.
      # Each prints a scannable human view by default and machine JSON with --json;
      # all are advisory reads (exit 0). They share OKF::Bundle#catalog for their data,
      # and (with `types`) narrow through the same --type/--dir/--tag filters the
      # server UI offers, so browser and CLI can answer the same questions.
      #
      # ── their shared --type/--dir/--tag narrowing ──
      # Each view takes the filters orthogonal to it (tags can't filter by tag).
      # Matching is case-insensitive; --type and --tag are exact, --dir is a prefix
      # over the whole path (see #under_dir?). The bundle root is `.`, spellable
      # `root` so no shell quoting is needed. --area is --dir's deprecated
      # predecessor and keeps its old first-segment-only behavior.

      # The shared back half of `tags` and `types`: load, narrow, print.
      def print_inverted_index(dir, label, key, plural, options)
        folder = OKF::Bundle::Folder.load(dir)
        report_skipped(folder)
        graph = folder.graph(minimal: true)
        index = key == :tag ? graph.tag_index : graph.type_index
        rows = index_rows(index, key, folder, options)
        if options[:json]
          print_index_json(dir, plural, key, rows)
        else
          titles = graph.nodes.map { |node| [ node[:id], node[:title] ] }.to_h
          print_index(dir, label, key, rows, titles)
        end
        0
      end

      # The --json / --pretty pair every emitting verb shares. --json is the compact
      # machine substrate (the default JSON form, aligned with the server); --pretty
      # indents it for a human and implies --json. Both route through emit_json.
      def json_flags(parser, options, desc)
        parser.on("--json", desc) { options[:json] = true }
        parser.on("--pretty", "indent the JSON for reading (implies --json)") { options[:json] = true; @pretty = true }
      end

      # Every parser answers its own -h/--help, so no parser inherits
      # OptionParser's officious one: that prints to the process's $stdout rather
      # than @out (an embedding app that injects streams never sees it) and ends
      # the process with `exit` rather than returning a status (a test that asks a
      # command for help takes the whole runner down with it). Thrown, not
      # returned — #run catches it — because a parser is parsed inside
      # positional_dir, where every other early exit means "exit 2".
      # on_tail, so help sorts last in the list it is printing.
      def help_flag(parser)
        parser.on_tail("-h", "--help", "print this message") do
          @out.puts parser.help
          throw :help, 0
        end
      end

      # --fields/--except project the JSON down to the properties an agent wants, so it
      # never pays tokens for fields it will not read. --fields is an allowlist,
      # --except a denylist (mutually exclusive); both imply --json and apply per item
      # in a list view (catalog, files, index). Names are the JSON keys, matched
      # case-insensitively.
      def projection_flags(parser, options)
        parser.on("--fields LIST", Array, "emit only these JSON properties (comma-separated)") { |v| options[:json] = true; options[:fields] = v }
        parser.on("--except LIST", Array, "emit every JSON property but these") { |v| options[:json] = true; options[:except] = v }
      end

      def filter_flags(parser, options, *keys)
        parser.on("--type TYPE", "only concepts of this type") { |v| options[:type] = v } if keys.include?(:type)
        if keys.include?(:area)
          parser.on("--dir PATH", "only concepts in this directory or below it",
            "(`root` — or `.` — for the bundle root)") { |v| options[:dir] = v }
          parser.on("--area AREA", "deprecated: use --dir (matches the first path segment only)") do |v|
            options[:area] = v
            deprecated("--area", "--dir")
          end
        end
        parser.on("--tag TAG", "only concepts carrying this tag") { |v| options[:tag] = v } if keys.include?(:tag)
      end

      def filter_entries(entries, options)
        entries.select do |entry|
          (options[:type].nil? || fold(entry[:type]) == fold(options[:type])) &&
            (options[:area].nil? || fold(entry[:area]) == fold_area(options[:area])) &&
            (options[:dir].nil? || under_dir?(entry[:dir], options[:dir])) &&
            (options[:tag].nil? || entry[:tags].any? { |tag| fold(tag) == fold(options[:tag]) })
        end
      end

      # The one rule --dir is built on: a dir names itself and everything beneath
      # it. `--dir foo` reaches foo/bar, `--dir foo/bar` narrows, and `--dir .`
      # needs no special case at all — nothing starts with "./", so the root
      # selects only what lives directly in it.
      def under_dir?(entry_dir, wanted)
        entry = fold(entry_dir)
        path = fold_dir(wanted)
        entry == path || entry.start_with?("#{path}/")
      end

      def fold(value)
        value.to_s.downcase
      end

      def fold_area(value)
        folded = trim_slash(fold(value))
        folded == "root" ? "(root)" : folded
      end

      # `.` is the stored spelling of the root everywhere; `root` is the one a
      # shell needs no quoting for, and the only reason the two exist.
      def fold_dir(value)
        folded = trim_slash(fold(value))
        folded.empty? || folded == "root" ? "." : folded
      end

      # The human views print a directory with the slash that says it is one —
      # `tables/`, `docs/api/` — so the flag has to accept the label the CLI
      # itself just printed. Without this, pasting a row back into --dir matched
      # nothing and exited 0: an empty answer that reads like a real one.
      def trim_slash(value)
        value.sub(%r{/+\z}, "")
      end

      # The inverse of fold_dir: `.` is the stored spelling of the root and
      # "(root)" the human one, and every grouped view keeps that split so a
      # table and its --json never disagree about which spelling is the data.
      # `slash:` adds the trailing slash the listing views use to say "directory"
      # — the same one fold_dir now accepts back.
      def dir_label(dir, slash: false)
        return "(root)" if [ ".", "(root)" ].include?(dir)

        slash ? "#{dir}/" : dir
      end

      # How many path segments deep a directory sits. The root is 0.
      def dir_depth(dir)
        dir == "." ? 0 : dir.count("/") + 1
      end

      # --depth N: how many directory levels below the *starting point* to keep,
      # where the starting point is each --dir when one is given and the bundle
      # root otherwise. Relative rather than absolute on purpose: `--dir a/b
      # --depth 1` reads "a/b and one level under it" without the caller first
      # working out how deep a/b already is — and the two flags then compose the
      # way a reader descending a tree actually moves.
      def depth_flag(parser, options)
        parser.on("--depth N", "keep only this many directory levels below the",
          "starting point (--dir when given, else the bundle root)") { |v| options[:depth] = v }
      end

      # Checked here rather than with OptionParser's Integer coercion, which
      # accepts "-1" and "0x2" and reports in its own words. Returns the exit
      # status to hand back, or nil when the value is fine.
      def depth_error(options)
        raw = options[:depth]
        return nil if raw.nil? || raw.to_s =~ /\A\d+\z/

        usage_error("--depth takes a whole number of levels (got #{raw.inspect})")
      end

      # The chain from the bundle root down to each --dir, so a branch is never
      # shown adrift. On by default in the *directory* views (`index`, `dirs`):
      # the map's job there is orientation, and a subtree printed with nothing
      # above it has dropped the authored context that says what it is — the root
      # index.md's prose first among it. Off with --no-ancestors, which restores
      # the subtree alone.
      #
      # Deliberately not offered on the concept filters (search/catalog/files/…):
      # there --dir narrows *concepts*, and a concept in `a/` is simply not in
      # `a/b`. Same flag, one meaning, because it is asked about two different
      # kinds of row.
      def ancestors_flag(parser, options)
        parser.on("--[no-]ancestors", "with --dir, also show the chain up to the root",
          "so the branch is placed (default: yes)") { |v| options[:ancestors] = v }
      end

      # Every proper ancestor of each --dir, root included. Empty unless --dir
      # named something below the root: with no --dir the whole bundle is already
      # the starting point, and `--dir .` has nothing above it.
      #
      # `known` is the map's own directory list, and a base outside it contributes
      # no chain. Without that check `--dir typo` came back with the root — a
      # chain to a place that does not exist, which reads as a partial answer to
      # a query that in fact matched nothing.
      #
      # The deprecated --area gains no chain either: it is exact, and a deprecated
      # flag that quietly answers with more than it used to is worse than one that
      # is merely old.
      # Matching folds case, but a row is found by its *stored* spelling, so the
      # chain is walked folded and handed back in the map's own words. Returning
      # the folded string instead dropped every ancestor a bundle spelled with a
      # capital — the rows are selected with `include?`, which does not fold.
      def ancestor_dirs(options, known)
        return [] unless options[:ancestors]

        stored = known.each_with_object({}) { |dir, out| out[fold(dir)] = dir }
        Array(options[:dirs]).each_with_object([]) do |path, out|
          base = fold_dir(path)
          next unless stored.key?(base)

          current = dir_parent(base)
          while current
            out << stored.fetch(current, current)
            current = dir_parent(current)
          end
        end.uniq
      end

      # nil above the root, so the walk above terminates on it rather than on ".".
      def dir_parent(dir)
        return nil if dir == "."

        slash = dir.rindex("/")
        slash ? dir[0, slash] : "."
      end

      # The directories a --dir/--depth pair selects, out of the map's own
      # ordered list. Neither flag given keeps everything — these narrow a view,
      # they do not define one. The ancestor chain is unioned on top by the
      # caller, which is also what tells a row apart from context.
      def select_dirs(dirs, options)
        bases = Array(options[:dirs]).map { |path| fold_dir(path) }
        depth = options[:depth]&.to_i
        return dirs if bases.empty? && depth.nil?
        # No --dir means the whole bundle is the starting point, which is *not*
        # `--dir .`: that one selects the root alone, by the same prefix rule
        # everything else here uses.
        return dirs.select { |dir| dir_depth(dir) <= depth } if bases.empty?

        dirs.select do |dir|
          bases.any? do |base|
            # --depth bounds the *descent*; the chain above is the ascent, and the
            # two are separate axes. That is what keeps `--depth 0` meaning "the
            # named directory alone" even while its chain is printed with it.
            under_dir?(dir, base) && (depth.nil? || dir_depth(dir) - dir_depth(base) <= depth)
          end
        end
      end

      # A deprecated spelling still does what it always did — never silently
      # something else — and says so once per run, on stderr so a --json
      # consumer's stdout stays a clean machine substrate.
      def deprecated(what, instead)
        @deprecated ||= {}
        return if @deprecated[what]

        @deprecated[what] = true
        @err.puts "warning: #{what} is deprecated, use #{instead}"
      end

      # Turn an inverted index ({ value => [id, …] }) into display rows ordered by
      # count, narrowed to the concepts the active filters select; rows the narrowing
      # empties drop. With no filters the index passes through whole.
      def index_rows(index, key, folder, options)
        keep = filter_ids(folder, options)
        index.each_with_object([]) do |(value, ids), rows|
          ids = ids.select { |id| keep.include?(id) } unless keep.nil?
          rows << { key => value, count: ids.length, concepts: ids } unless ids.empty?
        end.sort_by { |row| [ -row[:count], row[key] ] }
      end

      # The ids the filters select, resolved through the catalog metadata — or nil
      # when no filter is active, meaning keep everything.
      def filter_ids(folder, options)
        return nil if options[:type].nil? && options[:area].nil? && options[:dir].nil? && options[:tag].nil?

        filter_entries(folder.catalog, options).map { |entry| entry[:id] }
      end

      # §9 best-effort: the graph is built from concepts that parse. Surface any that
      # the reader could not parse (to stderr, so JSON on stdout stays clean) rather
      # than dropping them silently.
      def report_skipped(folder)
        note_skipped(folder.bundle.unparseable.size)
      end

      # The bucket holds two kinds now — frontmatter that would not parse, and a
      # file that would not open — so the note names neither and points at the verb
      # that names both. "invalid frontmatter" was a guess the summary had no need
      # to make: `validate` prints the file and the reason for every one of them.
      def note_skipped(count)
        return if count.nil? || count <= 0

        @err.puts "note: skipped #{count} unusable file(s) (run `okf validate` for details)"
      end

      # Parse options, then require a single bundle positional — a directory, or an
      # @ref into the registry. Returns the bundle's directory, or nil (after
      # reporting) so the caller returns 2.
      def positional_dir(parser, argv)
        parser.parse!(argv)
        dir = argv.shift
        if dir.nil?
          @err.puts parser.banner
          return nil
        end
        # A second bundle is a question this verb cannot answer: only `search`
        # merges across bundles and only `server` mounts several. Reading the
        # first and dropping the rest would answer confidently about a bundle the
        # user never asked about — the silent-wrong-answer shape, so: exit 2.
        return nil unless no_extras?(argv)

        resolve_ref(dir)
      rescue OptionParser::ParseError => e
        @err.puts e.message
        nil
      end

      # Parse options, then take zero or more bundle positionals (the multi-bundle
      # server) — directories or @refs. Returns the resolved array (possibly
      # empty), or nil (after reporting) so the caller returns 2.
      def positional_dirs(parser, argv, expand_groups: false)
        parser.parse!(argv)
        dirs = if expand_groups
                 argv.flat_map { |arg| resolve_ref_expanding(arg) }
               else
                 argv.map { |dir| resolve_ref(dir) }
               end
        dirs.include?(nil) ? nil : dirs
      rescue OptionParser::ParseError => e
        @err.puts e.message
        nil
      end

      # Like #resolve_ref, but a group @ref fans out to its member directories —
      # the multi-bundle expansion only `server` wants (single-bundle verbs reject
      # a group in #resolve_registered). Always returns an array of dirs so the
      # caller can flat_map, or nil (reported) to fail the run.
      def resolve_ref_expanding(arg)
        return [ resolve_ref(arg) ] unless arg.start_with?("@")

        registry = load_registry
        return [ nil ] unless registry

        slug = OKF::Registry.normalize(arg[1..-1])
        return [ resolve_ref(arg) ] if slug.empty? || registry.group?(slug).nil?

        group_member_dirs(registry, slug)
      end

      # A group's member directories, in order, skipping ones whose directory has
      # vanished with the same note `@all` gives — and populating +ref_slugs+ so the
      # hub mounts each under its registered slug. nil (reported) when nothing
      # readable is left, or on a hand-edited cycle.
      def group_member_dirs(registry, slug)
        dirs = []
        registry.expand(slug).each do |entry|
          if File.directory?(entry.path)
            ref_slugs[entry.path] = entry.slug
            dirs << entry.path
          else
            skip_registered(entry)
          end
        end
        return dirs unless dirs.empty?

        @err.puts "error: @#{slug} resolves to no readable bundle (okf registry list)"
        nil
      rescue OKF::Error => e
        @err.puts "error: #{e.message}"
        nil
      end

      # "@slug" — or bare "@", the registry's default — names a registered bundle
      # wherever a <dir> goes; anything else must be a directory on disk. A
      # leading @ always means the registry (a directory literally named that way
      # stays reachable as ./@name), and the registry loads only when a ref
      # appears, so plain-dir invocations never pay for it. Returns the bundle's
      # directory, or nil after reporting.
      def resolve_ref(arg)
        return resolve_registered(arg) if arg.start_with?("@")

        unless File.directory?(arg)
          @err.puts "error: #{arg} is not a directory or a registry ref " \
                    "(@slug names a registered bundle, @ the default; okf registry list)"
          return nil
        end
        arg
      end

      # Load the registry, turning a malformed file into a reported usage error
      # instead of an OKF::Error escaping through whatever verb took an @ref —
      # only `server` and the `registry` verbs rescue one. Returns nil after
      # reporting, so every caller returns 2.
      def load_registry
        open_registry
      rescue OKF::Error => e
        @err.puts "error: #{e.message}"
        nil
      end

      # The registry a verb resolves against — the single seam that opts the CLI
      # into discovery. `cwd: Dir.pwd` is what makes OKF::Registry.load walk up for
      # a project-local .okf-registry.json; a library caller passing no cwd stays
      # global-only. The registry subcommands and `server` open through here too,
      # so a bare `okf server` inside a repo serves that repo's bundles.
      def open_registry
        require "okf/registry"
        OKF::Registry.load(cwd: Dir.pwd)
      end

      # Resolve one @ref through the active registry — a discovered project-local
      # one, else the global $OKF_HOME (default ~/.okf). The slug part is normalized
      # exactly as registration normalized it, so @One finds the bundle
      # registered from dir One — but never through #slugify's mint-a-name
      # placeholder, so "@***" is a bad ref rather than whatever is slugged
      # "bundle". An explicit ask fails hard: an unknown slug or a
      # registered-but-gone directory is a usage error naming the registry file
      # and the next move, never a silent skip.
      #
      # @all never resolves here. `search` expands it before this point; every
      # other verb takes exactly one bundle, so letting it through would mean
      # @all lints when one bundle is registered and exits 2 when two are —
      # behavior that varies with the size of the registry, which is the
      # silent-wrong-answer shape the second-bundle rule exists to stop. Say what
      # @all is instead of calling it a bundle nobody registered ("all" cannot be
      # registered — Registry::RESERVED_SLUGS sees to that).
      def resolve_registered(ref)
        @ref_failure = :registry
        if all_ref?(ref)
          @err.puts "error: #{ALL_REF} is only supported by `okf search` (it names every registered bundle)"
          return nil
        end
        registry = load_registry
        return nil unless registry

        asked = ref[1..-1]
        slug = OKF::Registry.normalize(asked)

        # A group is a set, and this verb takes one bundle. Reading its first member
        # would answer confidently about a bundle the user never singled out — the
        # silent-wrong-answer shape the second-bundle rule already forbids — so it is
        # exit 2, with the two verbs that *can* take a group named.
        group = slug.empty? ? nil : registry.group?(slug)
        if group
          count = group.members.size
          @err.puts "error: @#{slug} names a group of #{count} #{count == 1 ? "member" : "members"}; " \
                    "only `okf search` and `okf server` take a group"
          return nil
        end

        entry = if asked.empty?
                  registry.default # bare "@"
                elsif slug.empty?
                  nil # "@***" — nothing to look up, and no placeholder to fall back on
                else
                  registry.get(slug)
                end
        if entry.nil?
          @ref_failure = :unknown
          hint = registry.empty? ? "okf registry set <dir>" : "okf registry list"
          @err.puts "error: not a registered bundle: #{ref} in #{registry.path} (#{hint})"
          return nil
        end
        unless File.directory?(entry.path)
          @ref_failure = :missing
          @err.puts "error: #{ref} points to #{entry.path}, which is not a directory (okf registry del #{entry.slug}, or restore it)"
          return nil
        end
        ref_slugs[entry.path] = entry.slug
        entry.path
      end

      # Every bundle-scoped output names its bundle in the identity the caller
      # used: `@handbook (/path)` when they named a registered bundle, the plain
      # path otherwise. A dir named by path stays a path — inventing a slug for it
      # would imply a registration that does not exist, and looking one up would
      # cost a registry read on every plain-dir run.
      def bundle_label(dir)
        slug = ref_slugs[dir]
        slug ? "@#{slug} (#{dir})" : dir.to_s
      end

      # The JSON head for one bundle. `bundle` is always its directory and `slug`
      # always a registry slug — never the same key meaning two things — so a
      # consumer resolves a row to a file without a second lookup.
      def bundle_head(dir)
        head = { "bundle" => dir }
        slug = ref_slugs[dir]
        head["slug"] = slug if slug
        head
      end

      # Parse options, then require a single non-directory positional (e.g. a slug).
      # Returns it, or nil (after reporting the banner) so the caller returns 2.
      def positional(parser, argv)
        parser.parse!(argv)
        value = argv.shift
        if value.nil?
          @err.puts parser.banner
          return nil
        end
        value
      rescue OptionParser::ParseError => e
        @err.puts e.message
        nil
      end

      def print_index(dir, label, key, rows, titles)
        @out.puts "#{label} — #{bundle_label(dir)} (#{rows.size} distinct)"
        @out.puts
        width = rows.map { |row| row[key].length }.max || 0
        rows.each do |row|
          names = row[:concepts].map { |id| titles[id] || id }.join(", ")
          @out.puts "  #{row[key].ljust(width)}  #{row[:count].to_s.rjust(3)}   #{truncate(names, 78)}"
        end
      end

      def print_index_json(dir, plural, key, rows)
        emit_json(bundle_head(dir).merge("count" => rows.size, plural => index_rows_json(key, rows)))
      end

      def index_rows_json(key, rows)
        rows.map { |row| { key.to_s => row[key], "count" => row[:count], "concepts" => row[:concepts] } }
      end

      # "3 concepts", "1 concept", "1 of 7 concepts" — the noun agrees with the
      # number it follows: the size when that is all we show, the total otherwise.
      def counted(size, total, noun)
        return "#{size} #{pluralize(size, noun)}" if size == total

        "#{size} of #{total} #{pluralize(total, noun)}"
      end

      # The gem's whole vocabulary is regular, so a naive +s is not a shortcut —
      # it is the rule. Callers pass the singular.
      def pluralize(count, noun)
        count == 1 ? noun : "#{noun}s"
      end

      # The single JSON writer. Compact by default — the token-efficient substrate an
      # agent consumes; --pretty indents it for a human. JSON semantics are identical
      # either way, so a parser never cares which was emitted.
      def emit_json(payload)
        @out.puts(@pretty ? JSON.pretty_generate(payload) : JSON.generate(payload))
      end

      # Emit a list view's JSON envelope with --fields/--except projection applied to
      # each item. Returns the verb's exit code (0, or 2 on a bad projection request —
      # both flags at once, or a field name no item carries).
      # +dir+ is the bundle's directory — or a ready-made head Hash when the
      # payload spans bundles (multi-bundle search's "bundles" key).
      # +key+ names the JSON property the rows land under; +shape+ names the row
      # shape to check --fields/--except against. They are the same for every view
      # but search, whose two modes emit the same property from different rows.
      def emit_list_json(dir, key, items, options, extra = {}, shape = key)
        return usage_error("--fields and --except are mutually exclusive") if options[:fields] && options[:except]

        unknown = unknown_fields(items, options, shape)
        return usage_error("unknown field(s): #{unknown.join(", ")} (available: #{available_fields(items, shape).join(", ")})") unless unknown.empty?

        payload = (dir.is_a?(Hash) ? dir.dup : bundle_head(dir)).merge(extra)
        payload["count"] = items.size
        payload[key] = project(items, options)
        emit_json(payload)
        0
      end

      # Keep only --fields (allowlist) or drop --except (denylist) from each item's
      # top-level properties; unset flags pass the items through whole.
      def project(items, options)
        return items if options[:fields].nil? && options[:except].nil?

        fields = options[:fields]&.map(&:downcase)
        except = options[:except]&.map(&:downcase)
        items.map do |item|
          fields ? item.select { |k, _| fields.include?(k.to_s.downcase) } : item.reject { |k, _| except.include?(k.to_s.downcase) }
        end
      end

      # The declared shape wins over the data's, so the same typo gets the same
      # answer whether or not the result happened to have rows; a view with no
      # declared shape falls back to what it actually emitted.
      def available_fields(items, key = nil)
        ROW_FIELDS[key] || (items.first ? items.first.keys.map(&:to_s) : [])
      end

      # Requested field names that no item actually carries — a typo guard (exit 2),
      # matching how lint rejects unknown check names.
      def unknown_fields(items, options, key = nil)
        requested = (Array(options[:fields]) + Array(options[:except])).map(&:downcase)
        return [] if requested.empty?

        known = available_fields(items, key).map(&:downcase)
        return [] if known.empty? # an unknown view: no shape to check against, so accept

        requested.reject { |field| known.include?(field) }.uniq
      end

      def usage_error(message)
        @err.puts "error: #{message}"
        2
      end

      def stringify(hash)
        hash.map { |key, value| [ key.to_s, value ] }.to_h
      end

      def truncate(str, max)
        str.length > max ? "#{str[0, max - 1]}…" : str
      end

      def paint(text, code)
        return text unless @out.respond_to?(:tty?) && @out.tty?

        "\e[#{code}m#{text}\e[0m"
      end
    end
  end
end
