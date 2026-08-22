# frozen_string_literal: true

require "okf/tui"
require_relative "refs"

module OKF
  module TUI
    # `okf tui`'s front end, and the only layer that parses argv, prints, and
    # chooses the exit code. Everything beneath it returns data.
    #
    # There is one door: this gem ships no executable, and the plugin seam
    # (lib/okf/plugin.rb) hands argv and the streams straight here. So this is
    # the whole argument grammar, with nothing to keep a second one in step
    # with.
    #
    # The argument shape mirrors `okf server`: naming directories is an ad-hoc
    # look at them and never enrols them in the registry. Registering stays an
    # explicit act — here, the `a` key in the bundles view.
    #
    # Output streams are injected (out:/err:) so the whole surface is driven in
    # tests without a real terminal, the same contract OKF::CLI keeps.
    class CLI
      USAGE = <<~TEXT
        usage: okf tui [options] [DIR|@slug...]

            (no arguments)     every bundle in the registry
            DIR...             those bundles, ad-hoc — the registry is left alone
            @slug              a registered bundle; bare @ is the registry default
            @group             every bundle a registry group resolves to

        options:
            -v, --version      print the version
            -h, --help         print this message

        The registry is the project-local .okf.json when one is on the
        path up from here, and $OKF_HOME (default ~/.okf) otherwise — whichever
        one every other `okf` verb run from here resolves to. OKF_NO_DISCOVERY=1
        forces the global one.
      TEXT

      # Exit codes, the same contract the `okf` CLI keeps.
      OK = 0
      FAILURE = 1
      USAGE_ERROR = 2

      def self.run(argv, out: $stdout, err: $stderr, input: $stdin)
        new(argv, out: out, err: err, input: input).run
      end

      def initialize(argv, out: $stdout, err: $stderr, input: $stdin)
        @argv = argv.dup
        @out = out
        @err = err
        @input = input
      end

      def run
        refs = []

        until @argv.empty?
          argument = @argv.shift

          case argument
          when "-h", "--help" then return print_and_exit(USAGE, OK)
          when "-v", "--version" then return print_and_exit("okf-tui #{OKF::TUI::VERSION}\n", OK)
          else
            return usage_error("unknown option: #{argument}") if argument.start_with?("-")

            # Not checked here on purpose: a positional may be a directory or an
            # @ref, and only the registry can tell whether `@mkt` names anything.
            # Refs resolves them together, so one place decides and one place
            # reports.
            refs << argument
          end
        end

        start(refs)
      end

      private

      # No `home` to pass: $OKF_HOME is the only lever, so the registry is
      # located the same way here as it is for every `okf` verb. Workspace still
      # takes `home:` — that is for an embedding app and the tests, which should
      # not have to mutate a process-global to say which registry they mean.
      #
      # `cwd: Dir.pwd` is the other half of that: it is what opts this run into
      # registry discovery, mirroring okf's own rule that only its CLI passes a
      # cwd while a library caller stays global-only. Without it the TUI would be
      # the one okf verb that ignores a project-local `.okf.json` sitting
      # right beside the bundles it is being asked about.
      def start(refs)
        return incompatible_okf("cannot answer a search — OKF::Bundle::Search is missing across/prepare/with") unless
          OKF::TUI.search_capable?
        return incompatible_okf("does not speak OKF v0.2 — Bundle#okf_version or RowFilter.shows_trust? is missing") unless
          OKF::TUI.spec_capable?

        # okf has already said what was wrong with the ref on @err.
        resolver = Refs.new(out: @out, err: @err)
        dirs = resolver.resolve(refs)
        return USAGE_ERROR if dirs.nil?

        app = App.new(dirs: dirs, ref_slugs: resolver.slugs, cwd: Dir.pwd, output: @out)

        return empty_workspace(app) if app.workspace.empty?
        # A terminal is the whole point; without one there is nothing to drive.
        return usage_error("needs an interactive terminal") unless @input.respond_to?(:tty?) && @input.tty?

        app.run
        OK
      rescue OKF::Error => e
        @err.puts "okf-tui: #{e.message}"
        FAILURE
      rescue Interrupt
        OK
      end

      # Loud on purpose: the alternative is a search view that finds nothing and
      # gives no reason. It names the okf that answered, because the usual cause
      # is a second one installed ahead of the intended checkout on the load path.
      def incompatible_okf(reason)
        @err.puts "okf-tui: this okf #{reason}"
        @err.puts "  loaded okf #{OKF::VERSION} from #{okf_location}"
        FAILURE
      end

      # The file that actually answered, not a guess from the version number:
      # OKF.blank? is defined in okf.rb itself, so its source_location is the
      # library that got loaded.
      def okf_location
        OKF.method(:blank?).source_location.first
      rescue StandardError
        "an unknown location"
      end

      def empty_workspace(app)
        @err.puts "okf-tui: nothing to show — the registry at #{app.workspace.registry_path} is empty"
        @err.puts "  register a bundle with `okf registry set <dir>`, or pass a directory or an @slug"
        USAGE_ERROR
      end

      def print_and_exit(text, status)
        @out.print(text)
        status
      end

      def usage_error(message)
        @err.puts "okf-tui: #{message}"
        @err.puts USAGE
        USAGE_ERROR
      end
    end
  end
end
