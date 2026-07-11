# frozen_string_literal: true

module OKF
  # Command-line front end: `okf graph|validate|lint|loose|catalog|files|tags|stats|server <dir>`.
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
    end

    def run(argv)
      argv = argv.dup
      case (command = argv.shift)
      when "graph" then graph(argv)
      when "validate" then validate(argv)
      when "lint" then lint(argv)
      when "loose" then loose(argv)
      when "catalog" then catalog(argv)
      when "files" then files(argv)
      when "tags" then tags(argv)
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
        o.on("--json", "emit a JSON report") { options[:json] = true }
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
        o.on("--json", "emit a JSON report") { options[:json] = true }
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
        o.on("--json", "emit the loose files as JSON") { options[:json] = true }
      end
      dir = positional_dir(parser, argv) or return 2

      folder = OKF::Bundle::Folder.load(dir)
      report_skipped(folder)
      files = loose_files(folder.graph(minimal: true))
      options[:json] ? print_loose_json(dir, files) : print_loose(dir, files)
      0
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
        o.on("--json", "emit nodes and edges as JSON") { options[:json] = true }
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
        @out.puts JSON.pretty_generate(payload)
      else
        @out.puts "#{graph.nodes.size} concepts, #{graph.edges.size} links"
      end
      0
    end

    # The Catalog / Files / Tags / Stats views the server renders in the browser,
    # reproduced on the CLI so an agent can read the same knowledge without one.
    # Each prints a scannable human view by default and machine JSON with --json;
    # all are advisory reads (exit 0). They share OKF::Bundle#catalog for their data.

    def catalog(argv)
      options = { json: false }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf catalog <bundle-dir> [--json]"
        o.on("--json", "emit the catalog as JSON") { options[:json] = true }
      end
      dir = positional_dir(parser, argv) or return 2

      folder = OKF::Bundle::Folder.load(dir)
      report_skipped(folder)
      entries = folder.catalog
      options[:json] ? print_catalog_json(dir, entries) : print_catalog(dir, entries)
      0
    end

    def files(argv)
      options = { json: false }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf files <bundle-dir> [--json]"
        o.on("--json", "emit the file tree as JSON") { options[:json] = true }
      end
      dir = positional_dir(parser, argv) or return 2

      folder = OKF::Bundle::Folder.load(dir)
      report_skipped(folder)
      entries = folder.catalog
      options[:json] ? print_files_json(dir, entries) : print_files(dir, entries)
      0
    end

    def tags(argv)
      options = { json: false }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf tags <bundle-dir> [--json]"
        o.on("--json", "emit the tag index as JSON") { options[:json] = true }
      end
      dir = positional_dir(parser, argv) or return 2

      folder = OKF::Bundle::Folder.load(dir)
      report_skipped(folder)
      graph = folder.graph(minimal: true)
      titles = graph.nodes.map { |node| [ node[:id], node[:title] ] }.to_h
      rows = graph.tag_index.map { |tag, ids| { tag: tag, count: ids.length, concepts: ids } }
                            .sort_by { |row| [ -row[:count], row[:tag] ] }
      options[:json] ? print_tags_json(dir, rows) : print_tags(dir, rows, titles)
      0
    end

    def stats(argv)
      options = { json: false }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf stats <bundle-dir> [--json]"
        o.on("--json", "emit the stats as JSON") { options[:json] = true }
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

    # Install this gem's companion agent skill into a destination directory. The
    # destination is required (no magic default) and must be given explicitly so a
    # user always decides where their agent picks the skill up (e.g.
    # .claude/skills/okf for Claude Code, .agents/skills/okf for agent-agnostic).
    def skill(argv)
      options = { force: false }
      parser = OptionParser.new do |o|
        o.banner = "Usage: okf skill <dest-dir> [--force]"
        o.on("--force", "overwrite a non-empty destination") { options[:force] = true }
      end
      parser.parse!(argv)
      dest = argv.shift
      if dest.nil?
        @err.puts parser.banner
        return 2
      end

      files = OKF::Skill.install(dest, force: options[:force])
      @out.puts "installed the okf skill (#{files.size} files) -> #{dest}"
      files.each { |f| @out.puts "  #{f}" }
      @out.puts "your agent picks it up from #{dest} (needs the `okf` CLI, which you already have)."
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
      @out.puts JSON.pretty_generate(
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
      @out.puts JSON.pretty_generate(
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
      @out.puts JSON.pretty_generate(
        "bundle" => dir,
        "count" => files.size,
        "loose" => files.map { |file| stringify(file) }
      )
    end

    def print_catalog(dir, entries)
      @out.puts "Catalog — #{dir} (#{entries.size} concepts)"
      entries.group_by { |entry| entry[:area] }.sort_by(&:first).each do |area, group|
        @out.puts
        @out.puts "  #{area}/ (#{group.size})"
        group.each do |entry|
          links = entry[:links_out] + entry[:links_in]
          meta = [ entry[:type], (links.positive? ? "↳#{links}" : nil), entry[:status] ].compact.join("  ·  ")
          @out.puts "    #{entry[:title]}  ·  #{meta}"
          @out.puts "      #{truncate(entry[:description], 92)}" unless entry[:description].empty?
        end
      end
    end

    def print_catalog_json(dir, entries)
      @out.puts JSON.pretty_generate("bundle" => dir, "count" => entries.size, "concepts" => entries.map { |entry| stringify(entry) })
    end

    def print_files(dir, entries)
      @out.puts "Files — #{dir} (#{entries.size} files)"
      entries.group_by { |entry| entry[:dir] }.sort_by(&:first).each do |folder, group|
        width = group.map { |entry| File.basename("#{entry[:id]}.md").length }.max
        @out.puts
        @out.puts "  #{folder == "." ? "(root)" : "#{folder}/"}"
        group.each do |entry|
          @out.puts "    #{File.basename("#{entry[:id]}.md").ljust(width)}  #{entry[:title]}"
        end
      end
    end

    def print_files_json(dir, entries)
      files = entries.map do |entry|
        { "path" => "#{entry[:id]}.md", "id" => entry[:id], "dir" => entry[:dir], "type" => entry[:type], "title" => entry[:title],
          "description" => entry[:description] }
      end
      @out.puts JSON.pretty_generate("bundle" => dir, "count" => files.size, "files" => files)
    end

    def print_tags(dir, rows, titles)
      @out.puts "Tags — #{dir} (#{rows.size} distinct)"
      @out.puts
      width = rows.map { |row| row[:tag].length }.max || 0
      rows.each do |row|
        names = row[:concepts].map { |id| titles[id] || id }.join(", ")
        @out.puts "  #{row[:tag].ljust(width)}  #{row[:count].to_s.rjust(3)}   #{truncate(names, 78)}"
      end
    end

    def print_tags_json(dir, rows)
      @out.puts JSON.pretty_generate(
        "bundle" => dir, "count" => rows.size,
        "tags" => rows.map { |row| { "tag" => row[:tag], "count" => row[:count], "concepts" => row[:concepts] } }
      )
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
      @out.puts JSON.pretty_generate(
        "bundle" => dir, "concepts" => stats[:concepts], "areas" => stats[:areas],
        "concept_types" => stats[:types], "cross_links" => stats[:cross_links], "distinct_tags" => stats[:tags],
        "by_type" => stats[:by_type], "by_area" => stats[:by_area]
      )
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

          skill     <dest> [--force]                        install the companion agent skill
          server    <dir> [-p PORT] [--bind ADDR] [...]     serve an interactive HTML graph

          lint      <dir> [--json] [--fail-on warn] [...]   report curation-quality issues
          loose     <dir> [--json]                          list files with no graph links, by folder
          validate  <dir> [--json]                          check OKF v0.1 conformance

          stats     <dir> [--json]                          bundle rollups (concepts, types, areas, links, tags)
          tags      <dir> [--json]                          list tags with their concepts, by count
          files     <dir> [--json]                          list files with titles, by folder
          catalog   <dir> [--json]                          list concepts with metadata, by area

          graph     <dir> [--json] [--minimal] [--no-body]  print the knowledge graph

        okf --version
      USAGE
    end
  end
end
