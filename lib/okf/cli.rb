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

    # The file a gem ships to add verbs to `okf`. Everything about the seam is in
    # this one constant: a gem that wants to extend the CLI puts `okf/plugin.rb`
    # on its load path and registers from it.
    #
    # A convention rather than a list the base gem keeps, because the alternative
    # is this gem naming its own addons — and the moment it does, adding an addon
    # means editing okf. `--engine` already set the precedent on the search side:
    # an addon shows up in help *without the CLI knowing it exists*.
    PLUGIN_FILE = "okf/plugin.rb"

    # Only gems named `okf-*` are loaded. `require` runs whatever it loads, and
    # while the trust boundary in Ruby is `gem install` rather than `require`,
    # that holds fully only for native extensions — those run `extconf.rb` at
    # install time. A **pure-Ruby** gem executes nothing until required, so
    # loading by convention alone would hand code a way to run that it did not
    # otherwise have.
    #
    # The prefix closes the case where the user chose nothing: a transitive
    # dependency shipping this file is discovered and skipped rather than run.
    # It cannot close a package deliberately installed under an `okf-` name —
    # `gem install` has already run by then, and no loader rule undoes that.
    PLUGIN_GEM_PREFIX = "okf-"

    # The map's shape: the order the groups print in, and the heading each one
    # carries. Only extensions get a heading — the built-in groups are separated
    # by a blank line and their verbs speak for themselves, which is how this map
    # has always read. A plugin's verbs are labelled because "where did this come
    # from?" is a question only an installed extension raises.
    GROUPS = [
      [ :act, nil ],
      [ :registry, nil ],
      [ :judge, nil ],
      [ :read, nil ],
      [ :graph, nil ],
      [ :extension, "  installed extensions:" ]
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

      # Load every installed extension, once. Returns the failures as
      # [ path, error ] pairs rather than printing them: this is a class method
      # with no streams, and the CLI's whole contract is that nothing writes
      # anywhere but the streams it was handed.
      #
      # A plugin that raises is *skipped and reported*, never fatal — the same
      # best-effort posture the reader takes with an unparseable file. One broken
      # addon must not cost a user their `okf lint`.
      def load_plugins
        return @plugin_failures if @plugins_loaded

        @plugins_loaded = true
        @plugin_failures = []
        @loaded_plugins = []
        plugin_paths.each do |path|
          begin
            require path
            @loaded_plugins << path
          rescue ::LoadError, ::StandardError => e
            @plugin_failures << [ path, e ]
          end
        end
        @plugin_failures
      end

      # Latest-version-only where RubyGems offers it, so two installed versions
      # of the same addon cannot both register. The fallback keeps the floor:
      # find_latest_files has been there since RubyGems 1.8, but the guard costs
      # nothing and says which method the behaviour depends on.
      #
      # Narrowed to gems named `okf-*` — the convention Jekyll (`jekyll-*`) and
      # Vagrant (`vagrant-*`) use for the same job, and the reason the rule is
      # here: it makes what counts as an okf extension explicit, and stops an
      # unrelated gem claiming the `okf/plugin.rb` path by accident.
      #
      # It is a mild guard as well, since `require` runs whatever it loads, but
      # the window it closes is nearly empty and calling it a **defence** would
      # invite the false confidence that is worse than having no rule at all. A
      # transitive dependency is required by its parent in normal use, so
      # `require "foo"` already runs foo's; under Bundler, discovery is
      # bundle-scoped, so the Gemfile is an allowlist already. What is left is a
      # pure-Ruby gem installed globally and then used by nothing — and nothing
      # here saves anyone from a package deliberately installed under an `okf-`
      # name, because `gem install` has already run on it.
      #
      # The rule underneath this one *is* load-bearing: naming a gem must never
      # load it. See `plugin_gem_name` below, and
      # .okf/design/extension-points.md for the argument in full.
      def plugin_paths
        found = if Gem.respond_to?(:find_latest_files)
                  Gem.find_latest_files(PLUGIN_FILE)
                else
                  Gem.find_files(PLUGIN_FILE)
                end

        @untrusted_plugins = []
        found.select do |path|
          name = plugin_gem_name(path)
          next true if name.nil? || name.start_with?(PLUGIN_GEM_PREFIX)

          @untrusted_plugins << [ path, name ]
          false
        end
      rescue ::StandardError
        []
      end

      # The gem a discovered path belongs to, or nil when it belongs to none —
      # a bare $LOAD_PATH entry, which is how a checkout and the suite's own
      # fixtures appear. Resolved from the spec's full_gem_path rather than by
      # loading anything: naming an extension must never mean running it.
      def plugin_gem_name(path)
        found = Gem::Specification.find do |spec|
          full = spec.full_gem_path
          path.start_with?(full.end_with?(File::SEPARATOR) ? full : "#{full}#{File::SEPARATOR}")
        end
        found&.name
      rescue ::StandardError
        nil
      end

      # Paths discovered but refused for their gem's name, as [ path, gem ]
      # pairs. Kept so the refusal can be *reported*: an extension that is
      # present and deliberately not run is exactly the thing a user needs told.
      def untrusted_plugins
        (@untrusted_plugins ||= []).dup.freeze
      end

      # Called once at the bottom of this file, after the built-ins have
      # registered. Everything registered after it is an extension — which makes
      # "built-in" a fact the CLI knows rather than a group a command claims,
      # and gives a test somewhere to roll back to.
      def seal_builtins!
        @builtins = commands
      end

      # The verbs this gem ships, frozen at seal time.
      def builtins
        (@builtins ||= []).dup.freeze
      end

      def extension?(command)
        !builtins.include?(command)
      end

      # Test seam: put the registry back to what shipped and forget the load
      # latch. Registration happens at require time, so without this a test that
      # installs a fake plugin would leak it into every test that runs after it.
      #
      # Dropping the files from $LOADED_FEATURES is not optional, and the reason
      # is worth stating: `require` is idempotent, so clearing the registry
      # alone leaves a plugin *unregistered and unloadable* — the next
      # load_plugins would find the file, require it, get `false`, and register
      # nothing. That only stays hidden while each test writes its plugin to a
      # fresh tmpdir; the moment one points at a real gem's lib/, the verb
      # vanishes after the first reset.
      def reset_plugins!
        Array(@loaded_plugins).each { |path| $LOADED_FEATURES.delete(path) }
        @loaded_plugins = []
        @commands = builtins.dup
        @plugins_loaded = false
        @plugin_failures = []
        @untrusted_plugins = []
        @declined = []
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
      @plugin_notes_reported = false
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

    # Built-ins answer without a plugin ever being loaded — the scan only
    # happens once a name misses, which is every run of `okf lint` and no run
    # of `okf tui`. Discovery is cheap (about 11ms on the 2.4 floor) but not
    # free, and a one-shot CLI that already refuses to build a search index for
    # a single query should not pay it to answer a verb it shipped with.
    def dispatch(name, argv)
      command = self.class.lookup(name) || begin
        report_plugin_failures(self.class.load_plugins)
        self.class.lookup(name)
      end
      return unknown(name) if command.nil?

      command.new(out: @out, err: @err, runner: @runner, input: @input).call(argv)
    end

    def unknown(name)
      @err.puts "okf: unknown command '#{name}'"
      usage(@err)
      2
    end

    # On stderr, so a `--json` run's stdout stays a clean machine substrate even
    # when an addon is broken — or when one was deliberately not run.
    #
    # A refused extension is *louder* than a broken one on purpose. A gem that
    # ships okf/plugin.rb under a name outside the okf- prefix is either an
    # honest mistake somebody needs told about, or something that wanted to run
    # code on a machine where nobody asked it to. Both want saying out loud.
    # Once per run, not once per caller. An unknown verb reaches this twice —
    # dispatch looks, misses, and then prints the map, which looks again — and a
    # warning repeated is a warning that reads like two problems.
    def report_plugin_failures(failures)
      return if @plugin_notes_reported

      @plugin_notes_reported = true
      Array(failures).each do |path, error|
        @err.puts "okf: extension at #{path} failed to load (#{error.class}: #{error.message})"
      end
      self.class.untrusted_plugins.each do |path, gem_name|
        @err.puts "okf: ignoring an extension shipped by `#{gem_name}` (#{path})"
        @err.puts "  extensions are loaded only from gems named #{PLUGIN_GEM_PREFIX}*, since loading one runs its code"
      end
    end

    def usage(io)
      # Help is the one place that must know about every verb, so it is the one
      # place besides an unknown name that pays for discovery.
      report_plugin_failures(self.class.load_plugins)
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

# The line between what ships and what is installed. Everything above is a
# built-in; everything registered after this point came from a plugin.
OKF::CLI.seal_builtins!
