# frozen_string_literal: true

require "optparse"

module OKF
  # Command-line front end: `okf graph|validate|lint|loose|search|index|catalog|files|tags|types|stats|server <dir>`.
  # This is the
  # only layer that parses argv, prints, writes files, and decides exit codes — the
  # lib classes below it just return data. Streams are injectable for testing.
  #
  # Exit codes: 0 success, 1 non-conformant / failing bundle, 2 usage error.
  class CLI
    # The `registry` umbrella's subcommands — the dispatch, and the words a
    # flag-first invocation is checked against.
    SUBCOMMANDS = %w[set del list default rename].freeze

    # Lint findings grouped for display, in category order.
    LINT_CATEGORIES = {
      "Reachability" => %i[orphan not_in_index disconnected_component unlinked],
      "Backlog" => %i[missing_concept broken_index_entry],
      "Completeness" => %i[stub missing_title missing_description missing_timestamp],
      "Freshness" => %i[stale],
      "Provenance" => %i[uncited_external broken_citation],
      "Hygiene" => %i[duplicate_title unused_reference_def undefined_reference self_link]
    }.freeze

    # Runs a Rack app under WEBrick until interrupted. Injected into the CLI so
    # tests can drive `server` without opening a socket; the runner loads here
    # (not at require time) so `require "okf"` and a Rails mount of the server stay
    # light.
    WEBRICK = lambda do |app, host, port|
      require "okf/server/runner"
      OKF::Server::Runner.run(app, host: host, port: port)
    end

    def self.start(argv, out: $stdout, err: $stderr)
      new(out: out, err: err).run(argv)
    end

    def initialize(out: $stdout, err: $stderr, runner: WEBRICK)
      @out = out
      @err = err
      @runner = runner
      @pretty = false
    end

    def run(argv)
      argv = argv.dup
      # Per-run state, reset so a reused instance never inherits the last run's
      # answer: the ref→slug memo, and the --pretty a previous argv turned on.
      @ref_slugs = {}
      @pretty = false
      # -h/--help is answered wherever a parser sees it — deep inside
      # positional_dir, where returning would only mean "usage error, exit 2".
      # Thrown here instead, so help keeps the contract every other path keeps:
      # a status this method returns. See #help_flag.
      catch(:help) do
        case (command = argv.shift)
        when "graph" then graph(argv)
        when "validate" then validate(argv)
        when "lint" then lint(argv)
        when "loose" then loose(argv)
        when "search" then search(argv)
        when "index" then index(argv)
        when "catalog" then catalog(argv)
        when "files" then files(argv)
        when "tags" then tags(argv)
        when "types" then types(argv)
        when "stats" then stats(argv)
        when "server" then server(argv)
        when "render" then render(argv)
        when "registry" then registry(argv)
        when "skill" then skill(argv)
        when "version", "--version", "-v" then @out.puts(OKF::VERSION); 0
        when "help", "--help", "-h" then usage(@out); 0
        when nil then usage(@err); 2
        else
          @err.puts "okf: unknown command '#{command}'"
          usage(@err)
          2
        end
      end
    end

    # "every registered bundle" as a ref, in its canonical spelling — what the
    # messages say, and (normalized) what #all_ref? recognizes. Only `search`
    # expands it: it is the one verb that merges across bundles, so it is the one
    # verb for which "all" names something it can answer about. See
    # resolve_registered for why the others refuse it outright rather than
    # treating it as an unknown slug. Its slug half is reserved by
    # Registry::RESERVED_SLUGS so no bundle can answer to it; a test pins the two
    # together.
    ALL_REF = "@all"

    # The row shape each list view emits, so `--fields`/`--except` can be checked
    # against a name even when the result is empty. Without it the typo guard
    # keyed off the data: `--fields bogus` was a usage error against a bundle
    # with matches and silently fine against one without, which made a typo's
    # fate depend on whether a filter happened to match. A test asserts each
    # view's real rows carry exactly these, so the two cannot drift.
    # Declared in emission order, so the "available:" list a typo prints reads
    # the same as the rows themselves.
    ROW_FIELDS = {
      "matches" => %w[id title type area tags matched score snippet],
      # Registry mode labels every row with the bundle it came from; a plain-dir
      # search has one bundle and no slug to carry. Two shapes, because the typo
      # guard checks against the *declared* one — a single shape covering both
      # would let `--fields slug` pass on a search whose rows have none, and hand
      # back an empty object per match under a count that says otherwise.
      "matches_by_ref" => %w[slug id title type area tags matched score snippet],
      "concepts" => %w[id title type description tags timestamp status backlog_ref dir area links_out links_in],
      "files" => %w[path id dir type title description],
      "directories" => %w[dir index_path present synthesized count types tags subdirs body listing],
      "bundles" => %w[slug title dir mount default missing]
    }.freeze

    private

    def validate(argv)
      options = { json: false }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf validate <dir|@slug> [--json]"
        json_flags(o, options, "emit a JSON report")
        help_flag(o)
      end
      dir = positional_dir(parser, argv) or return 2

      result = OKF::Bundle::Folder.load(dir).validate
      options[:json] ? print_validation_json(dir, result) : print_validation(dir, result)
      result.valid? ? 0 : 1
    end

    def lint(argv)
      options = { json: false, min_body: OKF::Bundle::Linter::DEFAULT_MIN_BODY, stale_after: nil, only: nil, except: nil, fail_on: :never }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf lint <dir|@slug> [--json] [--min-body N] [--stale-after DUR] [--only a,b] [--except a,b] [--fail-on warn]"
        json_flags(o, options, "emit a JSON report")
        o.on("--min-body N", Integer, "stub threshold in body characters (default #{OKF::Bundle::Linter::DEFAULT_MIN_BODY})") { |v| options[:min_body] = v }
        o.on("--stale-after DUR", "flag concepts older than DUR (e.g. 90d, 12w, 2026-01-01)") { |v| options[:stale_after] = v }
        o.on("--only LIST", Array, "run only these checks (comma-separated)") { |v| options[:only] = v.map(&:to_sym) }
        o.on("--except LIST", Array, "skip these checks (comma-separated)") { |v| options[:except] = v.map(&:to_sym) }
        o.on("--fail-on LEVEL", %w[never warn], "exit 1 when a finding at LEVEL exists (never | warn)") { |v| options[:fail_on] = v.to_sym }
        help_flag(o)
      end
      dir = positional_dir(parser, argv) or return 2

      unknown = ((options[:only] || []) + (options[:except] || [])) - OKF::Bundle::Linter::CHECKS
      unless unknown.empty?
        @err.puts "error: unknown check(s): #{unknown.uniq.join(", ")}"
        return 2
      end

      stale_before = parse_stale_after(options[:stale_after])
      if stale_before == :invalid
        @err.puts "error: invalid --stale-after `#{options[:stale_after]}` (use 90d, 12w, or an ISO date like 2026-01-01)"
        return 2
      end

      folder = OKF::Bundle::Folder.load(dir)
      report = folder.lint(min_body: options[:min_body], stale_before: stale_before, only: options[:only], except: options[:except])
      note_skipped(report.stats[:skipped])
      options[:json] ? print_lint_json(dir, report) : print_lint(dir, report)
      options[:fail_on] == :warn && report.warnings.any? ? 1 : 0
    end

    # List the "loose" files — concepts with graph degree 0 (no cross-links in or
    # out), grouped by folder. A folder-grouped view over lint's `unlinked` check,
    # for the common "which files float in the graph?" question. Advisory (exit 0):
    # a terminal leaf can be loose by design. `--json` for a machine substrate.
    def loose(argv)
      options = { json: false }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf loose <dir|@slug> [--json]"
        json_flags(o, options, "emit the loose files as JSON")
        help_flag(o)
      end
      dir = positional_dir(parser, argv) or return 2

      folder = OKF::Bundle::Folder.load(dir)
      report_skipped(folder)
      files = loose_files(folder.graph(minimal: true))
      options[:json] ? print_loose_json(dir, files) : print_loose(dir, files)
      0
    end

    # Deterministic text retrieval — the browser page's search brought to the CLI
    # and extended to bodies. Terms after the directory are ANDed case-insensitive
    # substrings (Ruby regexps with --regexp); rows rank by where they hit (title >
    # id > tags > type/description > body) and carry one bounded context snippet,
    # so "which concept covers X?" costs a few rows, not a body read. Advisory
    # read: exit 0 even with no matches. Deliberately not fuzzy — the consuming
    # agent is the fuzzy layer.
    def search(argv)
      options = { json: false, regexp: false }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf search <dir|@slug…|@all> <term> [term ...] [--regexp] [--in FIELDS] [--type T] [--area A] [--tag T] [--json]"
        json_flags(o, options, "emit the matches as JSON")
        projection_flags(o, options)
        o.on("-e", "--regexp", "treat each term as a Ruby regular expression (case-insensitive)") { options[:regexp] = true }
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

      return multi_search(pairs, terms, options) if pairs

      folder = OKF::Bundle::Folder.load(dir)
      report_skipped(folder)
      rows = OKF::Bundle::Search.call(folder.bundle, terms, fields: options[:in], regexp: options[:regexp])
      keep = filter_ids(folder, options)
      rows = rows.select { |row| keep.include?(row[:id]) } unless keep.nil?
      return print_search_json(dir, terms, rows, options) if options[:json]

      print_search(dir, terms, rows, folder.bundle.concepts.size)
      0
    rescue RegexpError => e
      usage_error("invalid pattern: #{e.message}")
    end

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

    # Does this @ref name every registered bundle? Takes a ref, sigil and all —
    # both callers reach it only past a start_with?("@") of their own, so a
    # third check here would be a branch no run can take.
    #
    # Compared *normalized*, because the ref grammar has exactly one
    # normalization and a ref exempt from it is a trapdoor: `@ALL` has to reach
    # `@all` for the same reason `@One` reaches the bundle registered from dir
    # `One`. It normalizes through Registry.normalize — the very call the slug
    # lookup makes — rather than a second downcase that could be forgotten while
    # the first was maintained.
    def all_ref?(ref)
      require "okf/registry"
      OKF::Registry.normalize(ref[1..-1]) == ALL_REF[1..-1]
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

    # Search each bundle with the same terms and merge the rankings — scores are
    # absolute term weights, so they compare across bundles — every row labeled
    # with its bundle's slug and ties broken deterministically.
    def multi_search(pairs, terms, options)
      rows = []
      total = 0
      pairs.each do |slug, dir|
        folder = OKF::Bundle::Folder.load(dir)
        report_skipped(folder)
        total += folder.bundle.concepts.size
        found = OKF::Bundle::Search.call(folder.bundle, terms, fields: options[:in], regexp: options[:regexp])
        keep = filter_ids(folder, options)
        found = found.select { |row| keep.include?(row[:id]) } unless keep.nil?
        found.each { |row| rows << { slug: slug }.merge(row) }
      end
      rows.sort_by! { |row| [ -row[:score], row[:slug], row[:id] ] }
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

    def server(argv)
      require "okf/server/app"
      require "rack/deflater"

      options = { port: 8808, bind: "127.0.0.1", title: nil, link: nil, layout: "cose" }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf server [DIR|@slug…] [-p PORT] [--bind ADDR] [--layout NAME] [-t title] [-l url]"
        o.on("-p", "--port PORT", Integer, "port to serve on (default #{options[:port]})") { |v| options[:port] = v }
        o.on("--bind ADDR", "address to bind (default #{options[:bind]})") { |v| options[:bind] = v }
        o.on("-t", "--title TITLE", "graph title, single bundle only (default: parent/bundle dir name)") { |v| options[:title] = v }
        o.on("-l", "--link URL", "source URL shown in the header, single bundle only") { |v| options[:link] = v }
        o.on("--layout NAME", OKF::Server::Graph::LAYOUTS, "initial layout (#{OKF::Server::Graph::LAYOUTS.join(", ")})") { |v| options[:layout] = v }
        help_flag(o)
      end
      dirs = positional_dirs(parser, argv) or return 2

      # A flag that will have no effect in this mode gets a note, not silence.
      @err.puts "note: --title/--link apply to a single-bundle server; ignored" if dirs.size != 1 && (options[:title] || options[:link])

      # One dir keeps the historical single-bundle server at `/`; zero (the
      # persistent registry) or many (ephemeral) fan out behind a hub.
      if dirs.size == 1
        folder = OKF::Bundle::Folder.load(dirs.first)
        report_skipped(folder)
        run_server(folder, options)
      else
        run_hub(dirs, options)
      end
      0
    rescue OKF::Error => e
      usage_error(e.message)
    end

    # Build the single-bundle Rack app and hand it to the runner (WEBrick by
    # default, injected so tests drive this without a socket).
    def run_server(folder, options)
      app = OKF::Server::App.new(folder, title: options[:title] || folder.name, link: options[:link], layout: options[:layout])
      # minimal: the banner wants a count, not bodies — and Folder#graph is not
      # memoized, so a full build here parses every concept a second time (the
      # App builds its own) purely to print one number.
      count = folder.graph(minimal: true).nodes.size
      @out.puts "serving #{count} #{pluralize(count, "concept")} at http://#{options[:bind]}:#{options[:port]} (Ctrl-C to stop)"
      serve(app, options)
    end

    # Build the multi-bundle hub and hand it to the runner. With dirs it serves
    # those ephemerally; with none it serves the persistent registry. Either way
    # the first bundle is the one `/` opens — for the registry that is its own
    # order, and a first entry whose directory has vanished drops out here, so
    # `/` lands on the next one that is actually there.
    def run_hub(dirs, options)
      require "okf/server/hub"
      require "okf/registry"
      if dirs.empty?
        # A malformed registry raises OKF::Error, which `server` rescues into a
        # usage error — no guarded load needed on this path.
        reg = OKF::Registry.load
        bundles = reg.map { |entry| load_registered(entry) }.compact
      else
        bundles = ephemeral_bundles(dirs)
      end
      hub = OKF::Server::Hub.new(bundles, layout: options[:layout])
      concepts = bundles.inject(0) { |sum, bundle| sum + bundle.folder.graph(minimal: true).nodes.size }
      @out.puts "serving #{bundles.size} #{pluralize(bundles.size,
        "bundle")}, #{concepts} #{pluralize(concepts, "concept")} at http://#{options[:bind]}:#{options[:port]} (Ctrl-C to stop)"
      print_mounts(hub)
      serve(hub, options)
    end

    # The one boot seam every served app passes through, so a hub gzips exactly
    # like a single bundle — the wrap belongs to booting a server, not to either
    # mode, and a mode added later gets it for free. Deliberately not inside the
    # runner: an embedding app mounting OKF::Server::App brings its own middleware.
    def serve(app, options)
      # gzip responses when the client accepts it — transparent, no new dependency
      @runner.call(Rack::Deflater.new(app), options[:bind], options[:port])
    end

    # The mount table — which dir landed on which /b/<slug>/ and where `/` goes.
    # Mirrors the Hub's own default resolution (explicit slug, else first).
    # Ask the hub which bundle it chose rather than re-deriving the
    # explicit-else-first rule, and mount at its own prefix: two copies of a
    # rule is two answers waiting to disagree.
    def print_mounts(hub)
      hub.bundles.each do |bundle|
        marker = bundle.equal?(hub.default) ? "*" : " "
        @out.puts "  #{marker} #{OKF::Server::Hub::MOUNT}/#{bundle.slug}/  #{bundle.title}"
      end
    end

    # Load the given directories as unregistered bundles, slugged by basename and
    # deduped within the run. The same directory listed twice mounts once — two
    # windows on one bundle would just burn a slug on a URL that vanishes next run.
    def ephemeral_bundles(dirs)
      roots = []
      dirs.each do |dir|
        root = File.expand_path(dir)
        roots << root unless roots.include?(root)
      end

      # A registered slug owns its mount outright: reserve every ref's slug
      # before any basename is deduped. Otherwise argv order decides, and
      # `server ./two @two` mounts the *unregistered* ./two at /b/two/ while
      # pushing the ref — the bundle whose slug that is — to /b/two-2/, so a
      # bookmark from a bundle-less run silently opens the wrong graph.
      taken = roots.map { |root| ref_slugs[root] }.compact
      roots.each_with_object([]) do |root, bundles|
        folder = OKF::Bundle::Folder.load(root)
        report_skipped(folder)
        slug = ref_slugs[root]
        unless slug
          slug = OKF::Registry.dedupe(File.basename(root), taken)
          taken << slug
        end
        bundles << OKF::Server::Hub::Bundle.new(slug, folder, folder.name)
      end
    end

    # Load one registered bundle; a path that has gone missing or no longer reads
    # drops to nil with a note (to stderr) rather than sinking the whole run. The
    # directory check is explicit — the Reader maps a nonexistent directory to an
    # empty bundle, so nothing would raise for the common "dir was deleted" case.
    # Method-level rescue (not a `do…end`-block rescue — a 2.6 feature).
    def load_registered(entry)
      return skip_registered(entry) unless File.directory?(entry.path)

      folder = OKF::Bundle::Folder.load(entry.path)
      report_skipped(folder)
      OKF::Server::Hub::Bundle.new(entry.slug, folder, entry.title)
    rescue SystemCallError, OKF::Error
      skip_registered(entry)
    end

    def skip_registered(entry)
      @err.puts "note: skipping #{entry.slug} — cannot read #{entry.path}"
      nil
    end

    # The static counterpart to `server`: bake the whole bundle into one
    # self-contained HTML file (bodies, catalog, index, logs baked in, no server
    # needed — e.g. hosting on GitHub Pages). Prints to stdout unless -o is given.
    def render(argv)
      require "okf/server/app"

      options = { output: nil, title: nil, link: nil, layout: "cose" }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf render <dir|@slug> [-o FILE] [--layout NAME] [-t title] [-l url]"
        o.on("-o", "--output FILE", "write to FILE instead of stdout") { |v| options[:output] = v }
        o.on("-t", "--title TITLE", "graph title (default: parent/bundle dir name)") { |v| options[:title] = v }
        o.on("-l", "--link URL", "source URL shown in the header") { |v| options[:link] = v }
        o.on("--layout NAME", OKF::Server::Graph::LAYOUTS, "initial layout (#{OKF::Server::Graph::LAYOUTS.join(", ")})") { |v| options[:layout] = v }
        help_flag(o)
      end
      dir = positional_dir(parser, argv) or return 2

      folder = OKF::Bundle::Folder.load(dir)
      report_skipped(folder)
      html = OKF::Server::App.new(folder, title: options[:title] || folder.name, link: options[:link], layout: options[:layout]).render_static
      if options[:output]
        # A bad -o path (a missing directory, a permission denial) is a bad
        # *argument*: exit 2 with the reason, never a backtrace and an exit code
        # that means "failing bundle".
        begin
          File.write(options[:output], html)
        rescue SystemCallError => e
          return usage_error("cannot write #{options[:output]}: #{e.message}")
        end
        count = folder.graph(minimal: true).nodes.size
        @out.puts "wrote #{count} #{pluralize(count, "concept")} to #{options[:output]}"
      else
        @out.print html
      end
      0
    end

    # The registry umbrella, split by what each verb keys on. `set`/`del`/`list`
    # act on entries — `set` keys on the bundle's path, so --as means one thing
    # ("the slug this entry has") whether it adds or renames. `default`/`rename`
    # act on slugs, the names actually to hand once a bundle is registered. Every
    # positional stays unambiguous, and `config` is left free for real settings.
    def registry(argv)
      require "okf/registry"

      sub = argv.first
      case sub
      when "set" then registry_set(argv.drop(1))
      when "del" then registry_del(argv.drop(1))
      when "list" then registry_list(argv.drop(1))
      when "default" then registry_default(argv.drop(1))
      when "rename" then registry_rename(argv.drop(1))
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
      dir = positional_dir(parser, argv) or return 2
      no_extras?(argv) or return 2

      reg = OKF::Registry.load
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

      reg = OKF::Registry.load
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

      reg = OKF::Registry.load
      return emit_list_json({ "registry" => reg.path }, "bundles", reg.listing.map { |row| stringify(row) }, options) if options[:json]

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

      reg = OKF::Registry.load
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

      reg = OKF::Registry.load
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

    # The registry verbs take an exact number of positionals — a leftover argument
    # is a typo'd invocation, not something to drop silently.
    def no_extras?(argv)
      return true if argv.empty?

      @err.puts "error: unexpected argument '#{argv.first}'"
      false
    end

    def print_registry(reg)
      return @out.puts "no bundles registered — okf registry set <dir>" if reg.empty?

      rows = reg.listing
      width = rows.map { |row| row[:slug].length }.max
      rows.each do |row|
        marker = row[:default] ? "*" : " "
        missing = row[:missing] ? "  (missing)" : ""
        @out.puts "#{marker} #{row[:slug].ljust(width)}  #{row[:title]}  (#{row[:dir]})#{missing}"
      end
    end

    def graph(argv)
      options = { json: false, minimal: false, body: true }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf graph <dir|@slug> [--json] [--minimal] [--no-body]"
        json_flags(o, options, "emit nodes and edges as JSON")
        o.on("--minimal", "leanest nodes (id + title); adds type/tag indexes") { options[:minimal] = true }
        o.on("--[no-]body", "include each concept's body (default: yes)") { |v| options[:body] = v }
        help_flag(o)
      end
      dir = positional_dir(parser, argv) or return 2

      folder = OKF::Bundle::Folder.load(dir)
      graph = folder.graph(minimal: options[:minimal], body: options[:body])
      report_skipped(folder)
      if options[:json]
        # The head every view carries: a payload of nodes and edges that never
        # says which bundle they came from is exactly what an agent holding
        # several bundles has to guess at.
        payload = bundle_head(dir).merge(graph.to_h)
        payload = payload.merge(types: graph.type_index, tags: graph.tag_index) if options[:minimal]
        emit_json(payload)
      else
        @out.puts "Graph — #{bundle_label(dir)} (#{graph.nodes.size} #{pluralize(graph.nodes.size, "concept")}, " \
                  "#{graph.edges.size} #{pluralize(graph.edges.size, "link")})"
      end
      0
    end

    # The progressive-disclosure map (spec §6): every directory that holds concepts
    # or carries an index.md, with its authored index body, a type/tag rollup, its
    # child directories, and — for a directory with no index.md — the listing
    # synthesized from the concepts there. The "orient before you read" view. `--area`
    # is repeatable (one or many directories; `root` is the bundle root); `--no-body`
    # drops the prose to a skeleton; advisory, exit 0.
    def index(argv)
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

    # The Catalog / Files / Tags / Stats views the server renders in the browser,
    # reproduced on the CLI so an agent can read the same knowledge without one.
    # Each prints a scannable human view by default and machine JSON with --json;
    # all are advisory reads (exit 0). They share OKF::Bundle#catalog for their data,
    # and (with `types`) narrow through the same --type/--area/--tag filters the
    # server UI offers, so browser and CLI can answer the same questions.

    def catalog(argv)
      options = { json: false }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf catalog <dir|@slug> [--type T] [--area A] [--tag T] [--json]"
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

    def files(argv)
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

    def tags(argv)
      options = { json: false, by: nil }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf tags <dir|@slug> [--by type|area] [--type T] [--area A] [--json]"
        json_flags(o, options, "emit the tag index as JSON")
        o.on("--by DIM", %w[type area], "group the tags by a concept dimension (type | area)") { |v| options[:by] = v.to_sym }
        filter_flags(o, options, :type, :area)
        help_flag(o)
      end
      dir = positional_dir(parser, argv) or return 2

      return grouped_tags(dir, options) if options[:by]

      print_inverted_index(dir, "Tags", :tag, "tags", options)
    end

    def types(argv)
      options = { json: false }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf types <dir|@slug> [--area A] [--tag T] [--json]"
        json_flags(o, options, "emit the type index as JSON")
        filter_flags(o, options, :area, :tag)
        help_flag(o)
      end
      dir = positional_dir(parser, argv) or return 2

      print_inverted_index(dir, "Types", :type, "types", options)
    end

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

    # `tags --by type|area`: the tag index re-cut per concept type or top-level
    # area, with within-group counts — the curation view. A tag confined to one
    # group at count 1 is scattered; one recurring across groups is connective.
    # The --type/--area filters narrow the concepts first, then the grouping cuts.
    def grouped_tags(dir, options)
      folder = OKF::Bundle::Folder.load(dir)
      report_skipped(folder)
      graph = folder.graph(minimal: true)
      titles = graph.nodes.map { |node| [ node[:id], node[:title] ] }.to_h
      groups = tag_groups(graph.tag_index, folder, options)
      options[:json] ? print_grouped_tags_json(dir, options[:by], groups) : print_grouped_tags(dir, options[:by], groups, titles)
      0
    end

    # [ [ group, rows ], … ] — groups sorted by name, rows shaped like index_rows'.
    # A tag carried in several groups appears in each, counted per group.
    def tag_groups(tag_index, folder, options)
      by_id = filter_entries(folder.catalog, options).map { |entry| [ entry[:id], entry ] }.to_h
      groups = {}
      tag_index.each do |tag, ids|
        ids.each do |id|
          entry = by_id[id]
          next if entry.nil?

          key = options[:by] == :type ? entry_type(entry) : entry[:area]
          ((groups[key] ||= {})[tag] ||= []) << id
        end
      end
      groups.map do |key, tags|
        rows = tags.map { |tag, ids| { tag: tag, count: ids.length, concepts: ids } }
                   .sort_by { |row| [ -row[:count], row[:tag] ] }
        [ key, rows ]
      end.sort_by(&:first)
    end

    # A catalog entry's type for display — "Untyped" when blank, matching the graph.
    def entry_type(entry)
      OKF.blank?(entry[:type]) ? "Untyped" : entry[:type]
    end

    def print_grouped_tags(dir, dim, groups, titles)
      @out.puts "Tags — #{bundle_label(dir)} (#{distinct_tags(groups)} distinct, by #{dim})"
      groups.each do |key, rows|
        label = dim == :area && key != "(root)" ? "#{key}/" : key
        @out.puts
        @out.puts "  #{label} (#{rows.size} #{pluralize(rows.size, "tag")})"
        width = rows.map { |row| row[:tag].length }.max || 0
        rows.each do |row|
          names = row[:concepts].map { |id| titles[id] || id }.join(", ")
          @out.puts "    #{row[:tag].ljust(width)}  #{row[:count].to_s.rjust(3)}   #{truncate(names, 76)}"
        end
      end
    end

    def print_grouped_tags_json(dir, dim, groups)
      groups_json = groups.map do |key, rows|
        { dim.to_s => key, "count" => rows.size, "tags" => index_rows_json(:tag, rows) }
      end
      emit_json(bundle_head(dir).merge("count" => distinct_tags(groups), "by" => dim.to_s, "groups" => groups_json))
    end

    def distinct_tags(groups)
      groups.flat_map { |_, rows| rows.map { |row| row[:tag] } }.uniq.size
    end

    def stats(argv)
      options = { json: false }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf stats <dir|@slug> [--json]"
        json_flags(o, options, "emit the stats as JSON")
        help_flag(o)
      end
      dir = positional_dir(parser, argv) or return 2

      folder = OKF::Bundle::Folder.load(dir)
      report_skipped(folder)
      stats = bundle_stats(folder)
      options[:json] ? print_stats_json(dir, stats) : print_stats(dir, stats)
      0
    end

    # Bundle-level rollups derived from the catalog and the graph indexes.
    def bundle_stats(folder)
      graph = folder.graph(minimal: true)
      entries = folder.catalog
      by_type = graph.type_index.transform_values(&:size).sort_by { |_, n| -n }.to_h
      by_area = entries.group_by { |entry| entry[:area] }.transform_values(&:size).sort_by { |_, n| -n }.to_h
      {
        concepts: entries.size,
        areas: by_area.size,
        types: by_type.size,
        cross_links: graph.edges.size,
        tags: graph.tag_index.size,
        by_type: by_type,
        by_area: by_area
      }
    end

    # ── the read views' shared --type/--area/--tag narrowing ──
    # Each view takes the filters orthogonal to it (tags can't filter by tag).
    # Matching is case-insensitive and exact; a concept at the bundle root lives in
    # the "(root)" area, which --area also accepts as plain `root` (no shell quoting).

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
      parser.on("--area AREA", "only concepts in this top-level area") { |v| options[:area] = v } if keys.include?(:area)
      parser.on("--tag TAG", "only concepts carrying this tag") { |v| options[:tag] = v } if keys.include?(:tag)
    end

    def filter_entries(entries, options)
      entries.select do |entry|
        (options[:type].nil? || fold(entry[:type]) == fold(options[:type])) &&
          (options[:area].nil? || fold(entry[:area]) == fold_area(options[:area])) &&
          (options[:tag].nil? || entry[:tags].any? { |tag| fold(tag) == fold(options[:tag]) })
      end
    end

    def fold(value)
      value.to_s.downcase
    end

    def fold_area(value)
      folded = fold(value)
      folded == "root" ? "(root)" : folded
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
      return nil if options[:type].nil? && options[:area].nil? && options[:tag].nil?

      filter_entries(folder.catalog, options).map { |entry| entry[:id] }
    end

    # Install this gem's companion agent skill into a destination directory. The
    # destination is required (no magic default) so the user always decides where
    # their agent picks the skill up. By default the skill lands in a skills/okf/
    # folder under it — point at a project or skills dir (.claude, .agents/skills)
    # and it settles in its own folder, never loose among the others — so the
    # resolved path is echoed back. --here installs straight into <dest-dir>.
    def skill(argv)
      options = { force: false, nest: true }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf skill <dest-dir> [--here] [--force]"
        o.on("--here", "install straight into <dest-dir>, wherever it is (no skills/okf nesting)") { options[:nest] = false }
        o.on("--force", "overwrite a non-empty destination") { options[:force] = true }
        help_flag(o)
      end
      parser.parse!(argv)
      dest = argv.shift
      if dest.nil?
        @err.puts parser.banner
        return 2
      end

      skill = OKF::Skill.new(dest, force: options[:force], nest: options[:nest])
      files = skill.install
      @out.puts "installed the okf skill (#{files.size} files) -> #{skill.dest}"
      files.each { |f| @out.puts "  #{f}" }
      @out.puts "your agent picks it up from #{skill.dest} (needs the `okf` CLI, which you already have)."
      0
    rescue OptionParser::ParseError => e
      @err.puts e.message
      2
    rescue OKF::Skill::Error => e
      @err.puts "error: #{e.message}"
      2
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

    # Turn a --stale-after value (90d, 12w, or an ISO date) into an absolute cutoff
    # Time so the pure Linter never reads the clock. nil when unset, :invalid on a
    # bad value.
    def parse_stale_after(value)
      return nil if value.nil?

      if (match = value.match(/\A(\d+)([dw])\z/))
        days = match[1].to_i * (match[2] == "w" ? 7 : 1)
        Time.now - (days * 86_400)
      else
        Date.iso8601(value).to_time
      end
    rescue ArgumentError
      :invalid
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
    def positional_dirs(parser, argv)
      parser.parse!(argv)
      dirs = argv.map { |dir| resolve_ref(dir) }
      dirs.include?(nil) ? nil : dirs
    rescue OptionParser::ParseError => e
      @err.puts e.message
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
      require "okf/registry"
      OKF::Registry.load
    rescue OKF::Error => e
      @err.puts "error: #{e.message}"
      nil
    end

    # Resolve one @ref through the registry under $OKF_HOME (default ~/.okf).
    # The slug part is normalized
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

    # Which slug each @ref resolved to, by absolute path — so a hub built from
    # refs mounts each bundle under its registered slug, not its dir basename.
    # Reset by every run; never memoized here, or a stale run would seed it.
    attr_reader :ref_slugs

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

    def print_validation(dir, result)
      counts = result.counts
      @out.puts "OKF v0.1 conformance — #{bundle_label(dir)}"
      @out.puts "  concepts: #{counts[:concepts]}   index.md: #{counts[:indexes]}   log.md: #{counts[:logs]}"
      result.errors.each { |e| @out.puts "  #{paint("✗ ERROR", 31)}  #{e[:path]}: #{e[:message]}" }
      result.warnings.each { |w| @out.puts "  #{paint("! warn", 33)}  #{w[:path]}: #{w[:message]}" }
      if result.valid? && result.warnings.empty?
        @out.puts "  #{paint("✓ conformant — no issues", 32)}"
      elsif result.valid?
        @out.puts "  #{paint("✓ conformant", 32)} (#{result.warnings.size} warning(s))"
      else
        @out.puts "  #{paint("✗ non-conformant", 31)} (#{result.errors.size} error(s))"
      end
    end

    def print_validation_json(dir, result)
      emit_json(bundle_head(dir).merge(
        "conformant" => result.valid?,
        "counts" => result.counts,
        "errors" => result.errors,
        "warnings" => result.warnings
      ))
    end

    def print_lint(dir, report)
      stats = report.stats
      @out.puts "OKF lint — #{bundle_label(dir)}"
      @out.puts "  concepts: #{stats[:concepts]}   edges: #{stats[:edges]}   index.md: #{stats[:indexes]}   log.md: #{stats[:logs]}"
      summary = lint_summary(stats)
      @out.puts "  #{summary}" unless summary.empty?

      LINT_CATEGORIES.each do |name, checks|
        findings = report.findings.select { |finding| checks.include?(finding[:check]) }
        next if findings.empty?

        @out.puts
        @out.puts "  #{name}"
        findings.each do |finding|
          @out.puts "    #{lint_glyph(finding)}  #{[ finding[:path], finding[:message] ].compact.join(": ")}"
        end
      end

      @out.puts
      @out.puts "  #{lint_verdict(report)}"
    end

    def print_lint_json(dir, report)
      emit_json(bundle_head(dir).merge(
        "healthy" => report.healthy?,
        "stats" => report.stats,
        "findings" => report.findings
      ))
    end

    # Degree-0 nodes as { id:, title:, dir: }, sorted by path — the same set lint's
    # `unlinked` check reports, resolved to titles/folders for display.
    def loose_files(graph)
      titles = graph.nodes.map { |node| [ node[:id], node[:title] ] }.to_h
      graph.unlinked_ids
           .map { |id| { id: id, title: titles[id], dir: File.dirname("#{id}.md") } }
           .sort_by { |file| file[:id] }
    end

    def print_loose(dir, files)
      @out.puts "Loose files — #{bundle_label(dir)} (#{files.size})"
      if files.empty?
        @out.puts "  #{paint("✓ none — every concept links or is linked", 32)}"
        return
      end

      files.group_by { |file| file[:dir] }.sort_by(&:first).each do |folder, group|
        width = group.map { |file| File.basename("#{file[:id]}.md").length }.max
        @out.puts
        @out.puts "  #{folder == "." ? "(root)" : "#{folder}/"}"
        group.each do |file|
          @out.puts "    #{File.basename("#{file[:id]}.md").ljust(width)}  #{file[:title]}"
        end
      end
    end

    def print_loose_json(dir, files)
      emit_json(bundle_head(dir).merge(
        "count" => files.size,
        "loose" => files.map { |file| stringify(file) }
      ))
    end

    def print_catalog(dir, entries, total)
      @out.puts "Catalog — #{bundle_label(dir)} (#{counted(entries.size, total, "concept")})"
      entries.group_by { |entry| entry[:area] }.sort_by(&:first).each do |area, group|
        @out.puts
        @out.puts "  #{area == "(root)" ? "(root)" : "#{area}/"} (#{group.size})"
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

    def print_stats(dir, stats)
      @out.puts "Stats — #{bundle_label(dir)}"
      @out.puts
      @out.puts "  concepts       #{stats[:concepts]}"
      @out.puts "  areas          #{stats[:areas]}"
      @out.puts "  concept types  #{stats[:types]}"
      @out.puts "  cross-links    #{stats[:cross_links]}"
      @out.puts "  distinct tags  #{stats[:tags]}"
      print_stat_breakdown("By type", stats[:by_type])
      print_stat_breakdown("By area", stats[:by_area])
    end

    def print_stat_breakdown(title, counts)
      return if counts.empty?

      width = counts.keys.map(&:length).max
      @out.puts
      @out.puts "  #{title}"
      counts.each { |label, count| @out.puts "    #{label.ljust(width)}  #{count}" }
    end

    def print_stats_json(dir, stats)
      emit_json(bundle_head(dir).merge(
        "concepts" => stats[:concepts], "areas" => stats[:areas],
        "concept_types" => stats[:types], "cross_links" => stats[:cross_links], "distinct_tags" => stats[:tags],
        "by_type" => stats[:by_type], "by_area" => stats[:by_area]
      ))
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

    def lint_summary(stats)
      parts = []
      hubs = stats[:hubs].map { |hub| "#{hub[:id]} (×#{hub[:in_degree]})" }.join(", ")
      types = stats[:types].map { |type, count| "#{type} #{count}" }.join(", ")
      parts << "hubs: #{hubs}" unless hubs.empty?
      parts << "types: #{types}" unless types.empty?
      parts.join("   ")
    end

    def lint_glyph(finding)
      finding[:severity] == :warn ? paint("! warn", 33) : "· info"
    end

    def lint_verdict(report)
      warnings = report.warnings.size
      infos = report.info.size
      return paint("✓ healthy — no issues", 32) if warnings.zero? && infos.zero?

      marker = warnings.zero? ? paint("✓", 32) : paint("⚠", 33)
      "#{marker} #{warnings} warn, #{infos} info"
    end

    def paint(text, code)
      return text unless @out.respond_to?(:tty?) && @out.tty?

      "\e[#{code}m#{text}\e[0m"
    end

    def usage(io)
      io.puts <<~USAGE
        okf <command> [options]

          skill     <dest> [--here] [--force]                     install the companion agent skill
          server    [DIR|@slug…] [-p PORT] [--bind ADDR] [...]    serve one bundle, or many behind a hub
          render    <dir|@slug> [-o FILE] [--layout NAME] [...]   write a static, self-contained HTML graph

          registry  list [--json]                                 list registered bundles (* marks the default)
          registry  set <dir|@slug> [--as SLUG] [--default]       add or update a bundle (a bare `server` serves them)
          registry  del <dir|@slug>                               remove a bundle from the registry
          registry  default <@slug>                               move a bundle to the front (the default)
          registry  rename <@slug> <new>                          rename a registered bundle (<new> is a new name, not a ref)

          lint      <dir|@slug> [--json] [--fail-on warn] [...]   report curation-quality issues
          loose     <dir|@slug> [--json]                          list files with no graph links, by folder
          validate  <dir|@slug> [--json]                          check OKF v0.1 conformance

          search    <dir|@slug…|@all> <term…> [-e] [...]          find concepts by text or regexp, ranked (@all: every bundle)
          index     <dir|@slug> [--json] [--area A] [--no-body]   the index map: dirs, their listings and rollups
          stats     <dir|@slug> [--json]                          bundle rollups (concepts, types, areas, links, tags)
          types     <dir|@slug> [--json] [filters]                list types with their concepts, by count
          tags      <dir|@slug> [--json] [--by DIM] [filters]     list tags with their concepts, by count
          files     <dir|@slug> [--json] [filters]                list files with titles, by folder
          catalog   <dir|@slug> [--json] [filters]                list concepts with metadata, by area

          graph     <dir|@slug> [--json] [--minimal] [--no-body]  print the knowledge graph

        @slug names a registered bundle instead of a path — the slug from
        `okf registry set`, or bare @ for the registry default. Anywhere a <dir>
        goes, an @slug goes: `okf lint @handbook`, `okf render @ -o graph.html`.
        The registry lives under $OKF_HOME (default ~/.okf); set it to point
        every verb at another one.
        search spans bundles: several leading @slugs, or @all for every registered one
        (@all skips a bundle whose directory is gone; a named @slug insists on it).

        [filters] narrow a view to matching concepts: --type TYPE, --area AREA, --tag TAG
        (each view takes the ones orthogonal to it; matching is case-insensitive).
        tags --by DIM regroups the tags per concept dimension — type or area — with
        within-group counts, the view for curating a tag vocabulary.
        --json emits compact JSON (the machine substrate); add --pretty to indent it.
        --fields / --except project the JSON to the properties you want (search/index/catalog/files).

        okf --version
      USAGE
    end
  end
end
