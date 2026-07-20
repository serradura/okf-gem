# frozen_string_literal: true

module OKF
  class CLI
    # Ranked text retrieval — the browser page's search brought to the CLI on the
    # same engine (a MiniFTS index) and extended to bodies. Terms after the
    # directory are ANDed tokens, matched whole or by prefix (Ruby regexps with
    # --regexp, typo tolerance with --fuzzy); rows rank by BM25+ weighted toward
    # where they hit (title > id > tags > type/description > body) and carry one
    # bounded context snippet, so "which concept covers X?" costs a few rows, not
    # a body read. Advisory read: exit 0 even with no matches. Exact by default —
    # the consuming agent is the fuzzy layer, until it asks not to be.
    class Search < Command
      # The core raises `:regexp`; a user typed `--regexp`. Translating here keeps
      # the flag vocabulary in the shell, where it belongs, and lets the message end
      # with the fix rather than only the complaint: an engine that *can* do what was
      # asked is named, so the next command is obvious.
      CAPABILITY_FLAGS = { regexp: "--regexp", fuzzy: "--fuzzy" }.freeze

      def self.id
        :search
      end

      def self.group
        :read
      end

      def self.help_rows
        [
          [ "search    <dir|@slug…|@all> <term…> [-e|--fuzzy] [...]", "find concepts by text or regexp, ranked (@all: every bundle)" ]
        ]
      end

      def call(argv)
        options = { json: false, regexp: false, fuzzy: false, engine: nil }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf search <dir|@slug…|@all> <term…> [--engine NAME] [--regexp|--fuzzy] [--in FIELDS] [--type T] [--area A] [--tag T] [--json]"
          search_engine_note(o)
          json_flags(o, options, "emit the matches as JSON")
          projection_flags(o, options)
          o.on("-e", "--regexp", "read each term as a Ruby regular expression rather",
            "than literal text — case-insensitive (scan engine)") { options[:regexp] = true }
          o.on("--fuzzy",
            "tolerate typos, edit distance #{OKF::Bundle::Search::FUZZY_DISTANCE} × term length (index engine)") { options[:fuzzy] = true }
          o.on("--engine NAME", "match with this engine instead of the default",
            "(#{engine_names}) — index is BM25+ ranked, token-based") { |v| options[:engine] = v }
          o.on("--in LIST", Array, "search only these fields (#{OKF::Bundle::Search::FIELDS.join(", ")})") { |v| options[:in] = v.map(&:downcase) }
          filter_flags(o, options, :type, :area, :tag)
          help_flag(o)
        end
        begin
          parser.parse!(argv)
        rescue OptionParser::ParseError => e
          @err.puts e.message
          return 2
        end

        # Registry mode — leading @refs, @all among them — searches several bundles
        # and labels every match; a plain dir keeps the classic single-bundle output.
        if argv.first&.start_with?("@")
          pairs = ref_targets(argv) or return 2
          dir = nil
        else
          dir = argv.shift
          if dir.nil?
            @err.puts parser.banner
            return 2
          end
          dir = resolve_ref(dir) or return 2
        end

        terms = argv
        if terms.empty?
          @err.puts parser.banner
          return 2
        end

        # A non-leading @arg is a literal term by the grammar — say so, since the
        # user may have meant a ref (refs must lead) and would otherwise see only
        # a silent zero-match.
        stray = terms.find { |term| term.start_with?("@") }
        @err.puts "note: '#{stray}' searches as a literal term — an @slug or @all must lead" if stray

        unknown = Array(options[:in]) - OKF::Bundle::Search::FIELDS
        return usage_error("unknown field(s): #{unknown.join(", ")} (searchable: #{OKF::Bundle::Search::FIELDS.join(", ")})") unless unknown.empty?

        # Two query languages, not two dials on one: a regexp is matched against raw
        # text, --fuzzy is an edit distance over indexed tokens. Silently honouring
        # one and dropping the other would answer a question nobody asked.
        if options[:regexp] && options[:fuzzy]
          return usage_error("--regexp and --fuzzy are mutually exclusive (a pattern is matched literally, not by edit distance)")
        end

        return multi_search(pairs, terms, options) if pairs

        folder = OKF::Bundle::Folder.load(dir)
        report_skipped(folder)
        rows = OKF::Bundle::Search.call(folder.bundle, terms, fields: options[:in], regexp: options[:regexp],
          fuzzy: options[:fuzzy], engine: options[:engine])
        keep = filter_ids(folder, options)
        rows = rows.select { |row| keep.include?(row[:id]) } unless keep.nil?
        return print_search_json(dir, terms, rows, options) if options[:json]

        print_search(dir, terms, rows, folder.bundle.concepts.size)
        0
      rescue RegexpError => e
        usage_error("invalid pattern: #{e.message}")
      rescue OKF::Bundle::Search::UnknownEngine => e
        usage_error(e.message)
      rescue OKF::Bundle::Search::UnsupportedQuery => e
        usage_error(unsupported_query_message(e))
      end

      private

      # Every registered bundle, as [slug, dir] pairs — what @all expands to.
      # Asking for everything tolerates gaps: a registered directory that has since
      # vanished is skipped with a note, the same forgiveness the hub shows a stale
      # entry. Naming one bundle demands it, so a plain @slug still fails hard.
      def all_targets
        registry = load_registry
        return nil unless registry

        if registry.empty?
          @err.puts "error: no bundles registered (okf registry set <dir>)"
          return nil
        end
        pairs = []
        registry.each do |entry|
          if File.directory?(entry.path)
            pairs << [ entry.slug, entry.path ]
          else
            skip_registered(entry)
          end
        end
        if pairs.empty?
          @err.puts "error: every registered bundle is missing on disk (okf registry list)"
          return nil
        end
        pairs
      end

      # Dedupe by resolved path, not ref spelling — `@ @one` is one bundle when
      # "one" is the default, and must be searched once. `@all @one` is the same
      # story with a wider first ref: all ⊇ one, so the result is right and the
      # duplicate simply drops. No error branch, because there is no wrong answer
      # to warn about.
      def ref_targets(argv)
        refs = []
        refs << argv.shift while argv.first&.start_with?("@")
        pairs = []
        refs.each do |ref|
          found = all_ref?(ref) ? all_targets : ref_pair(ref)
          return nil unless found

          found.each { |slug, path| pairs << [ slug, path ] unless pairs.any? { |_, seen| seen == path } }
        end
        pairs
      end

      # One @ref as a single-element [[slug, dir]], or nil after reporting.
      def ref_pair(ref)
        path = resolve_registered(ref)
        unless path
          # Only an unknown slug is plausibly a mistyped term — a broken registry
          # or a gone directory has nothing to do with the grammar.
          @err.puts "note: searching for a literal @-term? put a non-@ term first, or use -e '\\@term'" if @ref_failure == :unknown
          return nil
        end
        [ [ ref_slugs[path], path ] ]
      end

      # Search every bundle at once and merge the rankings, each row labeled with
      # its bundle's slug. The bundles go in as *one* corpus rather than one search
      # each: BM25 weighs a term by how rare it is, so ranking each bundle on its own
      # statistics and then interleaving the lists would let the same match score
      # differently for no reason a reader could see. One index, one ranking.
      #
      # Filters stay per-bundle — they are per-folder questions — so they apply to
      # the merged rows by (slug, id) afterwards.
      def multi_search(pairs, terms, options)
        bundles = []
        keeps = {}
        total = 0
        pairs.each do |slug, dir|
          folder = OKF::Bundle::Folder.load(dir)
          report_skipped(folder)
          total += folder.bundle.concepts.size
          bundles << [ slug, folder.bundle ]
          keep = filter_ids(folder, options)
          keeps[slug] = keep unless keep.nil?
        end
        rows = OKF::Bundle::Search.across(bundles, terms, fields: options[:in], regexp: options[:regexp],
          fuzzy: options[:fuzzy], engine: options[:engine])
        rows = rows.select { |row| !keeps.key?(row[:slug]) || keeps[row[:slug]].include?(row[:id]) }
        return print_multi_search_json(pairs, terms, rows, options) if options[:json]

        print_multi_search(pairs, terms, rows, total)
        0
      end

      def print_search(dir, terms, rows, total)
        @out.puts "Search — #{bundle_label(dir)} · #{terms.join(" ")} (#{counted(rows.size, total, "concept")})"
        if rows.empty?
          @out.puts "  no matches — fewer or broader terms, or scan `okf tags #{dir}` for the vocabulary"
          return
        end

        width = rows.map { |row| row[:id].length }.max
        rows.each do |row|
          @out.puts
          @out.puts "  #{row[:id].ljust(width)}  #{row[:title]}  ·  #{row[:type]}  ·  #{row[:matched].join("+")}"
          @out.puts "    #{truncate(row[:snippet], 100)}" unless row[:snippet].empty?
        end
      end

      def print_search_json(dir, terms, rows, options)
        emit_list_json(dir, "matches", rows.map { |row| stringify(row) }, options, "query" => terms)
      end

      def print_multi_search(pairs, terms, rows, total)
        @out.puts "Search — #{pairs.map { |slug, _| "@#{slug}" }.join(" ")} · #{terms.join(" ")} (#{counted(rows.size, total, "concept")})"
        if rows.empty?
          @out.puts "  no matches — fewer or broader terms, or scan `okf tags @<slug>` for a bundle's vocabulary"
          return
        end

        slug_width = rows.map { |row| row[:slug].length }.max + 1
        width = rows.map { |row| row[:id].length }.max
        rows.each do |row|
          @out.puts
          @out.puts "  #{"@#{row[:slug]}".ljust(slug_width)}  #{row[:id].ljust(width)}  #{row[:title]}  ·  #{row[:type]}  ·  #{row[:matched].join("+")}"
          @out.puts "    #{truncate(row[:snippet], 100)}" unless row[:snippet].empty?
        end
      end

      # The head maps every searched slug to its directory once, so a row's
      # `slug` resolves to `<dir>/<id>.md` without a second lookup — and without
      # repeating a long path on every row.
      def print_multi_search_json(pairs, terms, rows, options)
        head = { "bundles" => pairs.map { |slug, dir| { "slug" => slug, "dir" => dir } } }
        emit_list_json(head, "matches", rows.map { |row| stringify(row) }, options, { "query" => terms }, "matches_by_ref")
      end

      def unsupported_query_message(error)
        wanted = error.missing.map { |name| CAPABILITY_FLAGS.fetch(name, ":#{name}") }.join(", ")
        return "no available search engine offers #{wanted}" if error.engine.nil?

        able = OKF::Bundle::Search.engines.select { |engine| (error.missing - engine.capabilities).empty? }
        message = "--engine #{error.engine} does not support #{wanted}"
        message += " (try --engine #{able.map(&:id).join(" or ")})" unless able.empty?
        message
      end

      # The engine story, told once, in the only place there is to tell it. `search`
      # routes on what the query needs — a pattern needs the scan, --fuzzy needs the
      # index — and says nothing about it at runtime: no note on stderr, nothing in
      # the header, and deliberately no --engine flag. So this is where a user learns
      # that the exactness a token index gives up is still reachable, and that -e is
      # how. Without it that capability is present but undiscoverable.
      #
      # It leads rather than trails because #help_flag registers -h with `on_tail`,
      # which OptionParser renders after every separator: a closing paragraph would
      # print *above* the -h line and split the option list in half. Stating the
      # matching model before the flags reads better anyway.
      def search_engine_note(parser)
        parser.separator ""
        parser.separator "Terms match raw text, so a phrase (\"dedup key\"), a dotted identifier (7.2.0,"
        parser.separator "customer_id) and a word inside `backticks` all match literally — the scan engine."
        parser.separator "--engine index matches whole tokens and the tokens they prefix, ranked by BM25+:"
        parser.separator "better ranking and the engine the browser page runs, at the cost of that"
        parser.separator "exactness. --fuzzy implies it. Add -e to read the terms as regular expressions."
        parser.separator ""
      end

      # The registered engines, read at parse time so an addon that registers one
      # shows up in `--help` without the CLI knowing it exists.
      def engine_names
        OKF::Bundle::Search.engines.map(&:id).join(" | ")
      end
    end

    register(Search)
  end
end
