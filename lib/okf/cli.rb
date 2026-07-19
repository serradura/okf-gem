# frozen_string_literal: true

require "optparse"

module OKF
  # Command-line front end: `okf <command> [options]`.
  #
  # This file is the dispatcher and the registry; the verbs themselves live one
  # per file under `okf/cli/`, each a Command subclass that registers itself at
  # load. It is still the only layer that parses argv, prints, writes files and
  # decides exit codes — the lib classes below it just return data. Streams are
  # injectable for testing.
  #
  # Exit codes: 0 success, 1 non-conformant / failing bundle, 2 usage error.
  class CLI
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

    # Runs a Rack app under WEBrick until interrupted. Injected into the CLI so
    # tests can drive `server` without opening a socket; the runner loads here
    # (not at require time) so `require "okf"` and a Rails mount of the server stay
    # light.
    WEBRICK = lambda do |app, host, port|
      require "okf/server/runner"
      OKF::Server::Runner.run(app, host: host, port: port)
    end

    # The map's shape: the order the groups print in, and the heading each one
    # carries. The groups are separated by a blank
    # line and their verbs speak for themselves.
    GROUPS = [
      [ :act, nil ],
      [ :registry, nil ],
      [ :judge, nil ],
      [ :read, nil ],
      [ :graph, nil ]
    ].freeze

    # Everything the map's grammar column cannot say for itself. A test finds the
    # `@slug names` paragraph by its opening words, so the wording is load-bearing.
    NOTE = <<~NOTE
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
    NOTE

    class << self
      # Append-only and idempotent by id: a second registration of an id already
      # present is a no-op, so a double `require` cannot double the registry and
      # **an addon cannot quietly displace a built-in**. Deliberately the same
      # shape as Search.register — three extension points, one idiom.
      #
      # The duck type is checked here rather than at dispatch, so a malformed
      # command fails where it is installed instead of the first time somebody
      # types its verb.
      def register(command)
        missing = Command::DUCK_TYPE.reject { |message| command.respond_to?(message) }
        raise ArgumentError, "#{command} cannot be a command: it does not answer #{missing.join(", ")}" unless missing.empty?

        @commands ||= []
        existing = @commands.find { |registered| registered.id == command.id }
        return register_declined(command, existing) if existing

        @commands << command
        command
      end

      # A frozen snapshot in registration order — which, for the built-ins, is
      # the order this file requires them in at the bottom, and therefore the
      # order `okf help` lists them in.
      def commands
        (@commands ||= []).dup.freeze
      end

      def lookup(name)
        return nil if OKF.blank?(name)

        commands.find { |command| command.id.to_s == name.to_s }
      end

      # Registrations refused because the id was taken. Kept so the refusal can
      # be *reported* — Search can no-op in silence because an engine nobody
      # selected is invisible either way, but a verb that silently does nothing
      # is a bug report waiting to happen.
      def declined
        (@declined ||= []).dup.freeze
      end

      private

      def register_declined(command, existing)
        (@declined ||= []) << [ command, existing ] unless existing.equal?(command)
        existing
      end
    end

    def self.start(argv, out: $stdout, err: $stderr, input: $stdin)
      new(out: out, err: err, input: input).run(argv)
    end

    def initialize(out: $stdout, err: $stderr, runner: WEBRICK, input: $stdin)
      @out = out
      @err = err
      @runner = runner
      @input = input
    end

    def run(argv)
      argv = argv.dup
      # -h/--help is answered wherever a parser sees it — deep inside
      # positional_dir, where returning would only mean "usage error, exit 2".
      # Thrown here instead, so help keeps the contract every other path keeps:
      # a status this method returns. See Command#help_flag.
      catch(:help) do
        case (name = argv.shift)
        when "version", "--version", "-v" then @out.puts(OKF::VERSION); 0
        when "help", "--help", "-h" then usage(@out); 0
        when nil then usage(@err); 2
        else dispatch(name, argv)
        end
      end
    end

    private

    def dispatch(name, argv)
      command = self.class.lookup(name)
      return unknown(name) if command.nil?

      command.new(out: @out, err: @err, runner: @runner, input: @input).call(argv)
    end

    def unknown(name)
      @err.puts "okf: unknown command '#{name}'"
      usage(@err)
      2
    end

    def usage(io)
      io.puts "okf <command> [options]"
      io.puts
      GROUPS.each { |group, heading| print_group(io, group, heading) }
      io.puts NOTE
    end

    def print_group(io, group, heading)
      rows = self.class.commands.reject(&:hidden?).select { |command| command.group == group }.flat_map(&:help_rows)
      return if rows.empty?

      io.puts heading if heading
      rows.each { |left, desc| io.puts "  #{left.to_s.ljust(56)}#{desc}" }
      io.puts
    end
  end
end

require "okf/cli/command"

# ── These requires ARE the order `okf help` lists the verbs in ──
# Registration happens at load, `CLI.commands` is registration order, and the
# map walks the groups in GROUPS order and the verbs within a group in this
# one. Reordering these reorders the map. A test pins the result so the
# coupling cannot drift unnoticed, but the coupling is here, not there.
require "okf/cli/skill"
require "okf/cli/server"
require "okf/cli/render"
require "okf/cli/registry"
require "okf/cli/lint"
require "okf/cli/loose"
require "okf/cli/validate"
require "okf/cli/search"
require "okf/cli/index"
require "okf/cli/stats"
require "okf/cli/types"
require "okf/cli/tags"
require "okf/cli/files"
require "okf/cli/catalog"
require "okf/cli/graph"
