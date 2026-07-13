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

    private

    def validate(argv)
      options = { json: false }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf validate <bundle-dir> [--json]"
        json_flags(o, options, "emit a JSON report")
      end
      dir = positional_dir(parser, argv) or return 2

      result = OKF::Bundle::Folder.load(dir).validate
      options[:json] ? print_validation_json(dir, result) : print_validation(dir, result)
      result.valid? ? 0 : 1
    end

    def lint(argv)
      options = { json: false, min_body: OKF::Bundle::Linter::DEFAULT_MIN_BODY, stale_after: nil, only: nil, except: nil, fail_on: :never }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf lint <bundle-dir> [--json] [--min-body N] [--stale-after DUR] [--only a,b] [--except a,b] [--fail-on warn]"
        json_flags(o, options, "emit a JSON report")
        o.on("--min-body N", Integer, "stub threshold in body characters (default #{OKF::Bundle::Linter::DEFAULT_MIN_BODY})") { |v| options[:min_body] = v }
        o.on("--stale-after DUR", "flag concepts older than DUR (e.g. 90d, 12w, 2026-01-01)") { |v| options[:stale_after] = v }
        o.on("--only LIST", Array, "run only these checks (comma-separated)") { |v| options[:only] = v.map(&:to_sym) }
        o.on("--except LIST", Array, "skip these checks (comma-separated)") { |v| options[:except] = v.map(&:to_sym) }
        o.on("--fail-on LEVEL", %w[never warn], "exit 1 when a finding at LEVEL exists (never | warn)") { |v| options[:fail_on] = v.to_sym }
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
        o.banner = "Usage: okf loose <bundle-dir> [--json]"
        json_flags(o, options, "emit the loose files as JSON")
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
        o.banner = "Usage: okf search <bundle-dir> <term> [term ...] [--regexp] [--in FIELDS] [--type T] [--area A] [--tag T] [--json]"
        json_flags(o, options, "emit the matches as JSON")
        projection_flags(o, options)
        o.on("-e", "--regexp", "treat each term as a Ruby regular expression (case-insensitive)") { options[:regexp] = true }
        o.on("--in LIST", Array, "search only these fields (#{OKF::Bundle::Search::FIELDS.join(", ")})") { |v| options[:in] = v.map(&:downcase) }
        filter_flags(o, options, :type, :area, :tag)
      end
      dir = positional_dir(parser, argv) or return 2
      terms = argv
      if terms.empty?
        @err.puts parser.banner
        return 2
      end

      unknown = Array(options[:in]) - OKF::Bundle::Search::FIELDS
      return usage_error("unknown field(s): #{unknown.join(", ")} (searchable: #{OKF::Bundle::Search::FIELDS.join(", ")})") unless unknown.empty?

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

    def print_search(dir, terms, rows, total)
      @out.puts "Search — #{dir} · #{terms.join(" ")} (#{counted(rows.size, total, "concepts")})"
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

    def server(argv)
      require "okf/server/app"

      options = { port: 8808, bind: "127.0.0.1", title: nil, link: nil, layout: "cose" }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf server <bundle-dir> [-p PORT] [--bind ADDR] [--layout NAME] [-t title] [-l url]"
        o.on("-p", "--port PORT", Integer, "port to serve on (default #{options[:port]})") { |v| options[:port] = v }
        o.on("--bind ADDR", "address to bind (default #{options[:bind]})") { |v| options[:bind] = v }
        o.on("-t", "--title TITLE", "graph title (default: parent/bundle dir name)") { |v| options[:title] = v }
        o.on("-l", "--link URL", "source URL shown in the header") { |v| options[:link] = v }
        o.on("--layout NAME", OKF::Server::Graph::LAYOUTS, "initial layout (#{OKF::Server::Graph::LAYOUTS.join(", ")})") { |v| options[:layout] = v }
      end
      dir = positional_dir(parser, argv) or return 2

      folder = OKF::Bundle::Folder.load(dir)
      report_skipped(folder)
      run_server(folder, options)
      0
    end

    # Build the Rack app and hand it to the runner (WEBrick by default, injected so
    # tests drive this without a socket).
    def run_server(folder, options)
      app = OKF::Server::App.new(folder, title: options[:title] || folder.name, link: options[:link], layout: options[:layout])
      @out.puts "serving #{folder.graph.nodes.size} concepts at http://#{options[:bind]}:#{options[:port]} (Ctrl-C to stop)"
      @runner.call(app, options[:bind], options[:port])
    end

    def graph(argv)
      options = { json: false, minimal: false, body: true }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf graph <bundle-dir> [--json] [--minimal] [--no-body]"
        json_flags(o, options, "emit nodes and edges as JSON")
        o.on("--minimal", "leanest nodes (id + title); adds type/tag indexes") { options[:minimal] = true }
        o.on("--[no-]body", "include each concept's body (default: yes)") { |v| options[:body] = v }
      end
      dir = positional_dir(parser, argv) or return 2

      folder = OKF::Bundle::Folder.load(dir)
      graph = folder.graph(minimal: options[:minimal], body: options[:body])
      report_skipped(folder)
      if options[:json]
        payload = graph.to_h
        payload = payload.merge(types: graph.type_index, tags: graph.tag_index) if options[:minimal]
        emit_json(payload)
      else
        @out.puts "#{graph.nodes.size} concepts, #{graph.edges.size} links"
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
        o.banner = "Usage: okf index <bundle-dir> [--area AREA] [--no-body] [--json]"
        json_flags(o, options, "emit the index map as JSON")
        projection_flags(o, options)
        o.on("--area AREA", "only this directory/area (repeatable; `root` for the bundle root)") { |v| (options[:areas] ||= []) << v }
        o.on("--[no-]body", "include each index's prose body (default: yes)") { |v| options[:body] = v }
      end
      dir = positional_dir(parser, argv) or return 2

      folder = OKF::Bundle::Folder.load(dir)
      report_skipped(folder)
      entries = folder.directory_index
      selected = select_directories(entries, options[:areas])
      if options[:json]
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
      @out.puts "Index map — #{dir} (#{entries.size} #{noun})"
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
      count = "#{entry[:count]} #{entry[:count] == 1 ? "concept" : "concepts"}"
      types = entry[:types].map { |type, n| "#{type.empty? ? "Untyped" : type} #{n}" }.join(", ")
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
        o.banner = "Usage: okf catalog <bundle-dir> [--type T] [--area A] [--tag T] [--json]"
        json_flags(o, options, "emit the catalog as JSON")
        projection_flags(o, options)
        filter_flags(o, options, :type, :area, :tag)
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
        o.banner = "Usage: okf files <bundle-dir> [--type T] [--area A] [--tag T] [--json]"
        json_flags(o, options, "emit the file tree as JSON")
        projection_flags(o, options)
        filter_flags(o, options, :type, :area, :tag)
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
        o.banner = "Usage: okf tags <bundle-dir> [--by type|area] [--type T] [--area A] [--json]"
        json_flags(o, options, "emit the tag index as JSON")
        o.on("--by DIM", %w[type area], "group the tags by a concept dimension (type | area)") { |v| options[:by] = v.to_sym }
        filter_flags(o, options, :type, :area)
      end
      dir = positional_dir(parser, argv) or return 2

      return grouped_tags(dir, options) if options[:by]

      print_inverted_index(dir, "Tags", :tag, "tags", options)
    end

    def types(argv)
      options = { json: false }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf types <bundle-dir> [--area A] [--tag T] [--json]"
        json_flags(o, options, "emit the type index as JSON")
        filter_flags(o, options, :area, :tag)
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
      entry[:type].empty? ? "Untyped" : entry[:type]
    end

    def print_grouped_tags(dir, dim, groups, titles)
      @out.puts "Tags — #{dir} (#{distinct_tags(groups)} distinct, by #{dim})"
      groups.each do |key, rows|
        label = dim == :area && key != "(root)" ? "#{key}/" : key
        @out.puts
        @out.puts "  #{label} (#{rows.size} tags)"
        width = rows.map { |row| row[:tag].length }.max || 0
        rows.each do |row|
          names = row[:concepts].map { |id| titles[id] || id }.join(", ")
          @out.puts "    #{row[:tag].ljust(width)}  #{row[:count].to_s.rjust(3)}   #{truncate(names, 76)}"
        end
      end
    end

    def print_grouped_tags_json(dir, dim, groups)
      emit_json(
        "bundle" => dir, "count" => distinct_tags(groups), "by" => dim.to_s,
        "groups" => groups.map do |key, rows|
          { dim.to_s => key, "count" => rows.size, "tags" => index_rows_json(:tag, rows) }
        end
      )
    end

    def distinct_tags(groups)
      groups.flat_map { |_, rows| rows.map { |row| row[:tag] } }.uniq.size
    end

    def stats(argv)
      options = { json: false }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf stats <bundle-dir> [--json]"
        json_flags(o, options, "emit the stats as JSON")
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

    def note_skipped(count)
      return if count.nil? || count <= 0

      @err.puts "note: skipped #{count} file(s) with invalid frontmatter (run `okf validate` for details)"
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

    # Parse options, then require a single existing-directory positional argument.
    # Returns the directory, or nil (after reporting) so the caller returns 2.
    def positional_dir(parser, argv)
      parser.parse!(argv)
      dir = argv.shift
      if dir.nil?
        @err.puts parser.banner
        return nil
      end
      unless File.directory?(dir)
        @err.puts "error: #{dir} is not a directory"
        return nil
      end
      dir
    rescue OptionParser::ParseError => e
      @err.puts e.message
      nil
    end

    def print_validation(dir, result)
      counts = result.counts
      @out.puts "OKF v0.1 conformance — #{dir}"
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
      emit_json(
        "bundle" => dir,
        "conformant" => result.valid?,
        "counts" => result.counts,
        "errors" => result.errors,
        "warnings" => result.warnings
      )
    end

    def print_lint(dir, report)
      stats = report.stats
      @out.puts "OKF lint — #{dir}"
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
      emit_json(
        "bundle" => dir,
        "healthy" => report.healthy?,
        "stats" => report.stats,
        "findings" => report.findings
      )
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
      @out.puts "Loose files — #{dir} (#{files.size})"
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
      emit_json(
        "bundle" => dir,
        "count" => files.size,
        "loose" => files.map { |file| stringify(file) }
      )
    end

    def print_catalog(dir, entries, total)
      @out.puts "Catalog — #{dir} (#{counted(entries.size, total, "concepts")})"
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
      @out.puts "Files — #{dir} (#{counted(entries.size, total, "files")})"
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
      @out.puts "#{label} — #{dir} (#{rows.size} distinct)"
      @out.puts
      width = rows.map { |row| row[key].length }.max || 0
      rows.each do |row|
        names = row[:concepts].map { |id| titles[id] || id }.join(", ")
        @out.puts "  #{row[key].ljust(width)}  #{row[:count].to_s.rjust(3)}   #{truncate(names, 78)}"
      end
    end

    def print_index_json(dir, plural, key, rows)
      emit_json("bundle" => dir, "count" => rows.size, plural => index_rows_json(key, rows))
    end

    def index_rows_json(key, rows)
      rows.map { |row| { key.to_s => row[key], "count" => row[:count], "concepts" => row[:concepts] } }
    end

    def counted(size, total, noun)
      size == total ? "#{size} #{noun}" : "#{size} of #{total} #{noun}"
    end

    def print_stats(dir, stats)
      @out.puts "Stats — #{dir}"
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
      emit_json(
        "bundle" => dir, "concepts" => stats[:concepts], "areas" => stats[:areas],
        "concept_types" => stats[:types], "cross_links" => stats[:cross_links], "distinct_tags" => stats[:tags],
        "by_type" => stats[:by_type], "by_area" => stats[:by_area]
      )
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
    def emit_list_json(dir, key, items, options, extra = {})
      return usage_error("--fields and --except are mutually exclusive") if options[:fields] && options[:except]

      unknown = unknown_fields(items, options)
      return usage_error("unknown field(s): #{unknown.join(", ")} (available: #{available_fields(items).join(", ")})") unless unknown.empty?

      payload = { "bundle" => dir }.merge(extra)
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

    def available_fields(items)
      items.first ? items.first.keys.map(&:to_s) : []
    end

    # Requested field names that no item actually carries — a typo guard (exit 2),
    # matching how lint rejects unknown check names.
    def unknown_fields(items, options)
      requested = (Array(options[:fields]) + Array(options[:except])).map(&:downcase)
      return [] if requested.empty? || items.empty?

      known = available_fields(items).map(&:downcase)
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

          skill     <dest> [--here] [--force]               install the companion agent skill
          server    <dir> [-p PORT] [--bind ADDR] [...]     serve an interactive HTML graph

          lint      <dir> [--json] [--fail-on warn] [...]   report curation-quality issues
          loose     <dir> [--json]                          list files with no graph links, by folder
          validate  <dir> [--json]                          check OKF v0.1 conformance

          search    <dir> <term…> [-e] [--in FIELDS] [...]  find concepts by text or regexp, ranked
          index     <dir> [--json] [--area A] [--no-body]   the index map: dirs, their listings and rollups
          stats     <dir> [--json]                          bundle rollups (concepts, types, areas, links, tags)
          types     <dir> [--json] [filters]                list types with their concepts, by count
          tags      <dir> [--json] [--by DIM] [filters]     list tags with their concepts, by count
          files     <dir> [--json] [filters]                list files with titles, by folder
          catalog   <dir> [--json] [filters]                list concepts with metadata, by area

          graph     <dir> [--json] [--minimal] [--no-body]  print the knowledge graph

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
