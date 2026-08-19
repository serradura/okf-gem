# frozen_string_literal: true

require "test_helper"
require "okf/cli"

module Integration
  # The seam itself: `okf tui`, reached through the base gem's dispatcher. This
  # gem ships no executable, so that dispatcher is the only way a user gets here
  # and this file covers the whole entry point rather than half of it.
  #
  # Installing this gem is the whole installation. There is no configuration
  # step, no registration to remember — okf finds `okf/plugin.rb` on the load
  # path, which is where this gem's lib/ already is.
  class PluginTest < OKF::TUI::TestCase
    # These used to skip when the resolved okf had no command registry, because the
    # seam was newer than any release. It is not any more — `OKF::CLI.register`
    # shipped in okf 1.10.0 and the gemspec floor now names 1.13 — so the skip is
    # gone, on its own instruction: it was to be deleted once the floor could name
    # the okf that ships the seam, "not left to rot into a suite that quietly tests
    # nothing". Resolution now guarantees the registry, so its absence is a failure
    # to hear about rather than a condition to tolerate.
    setup do
      OKF::CLI.reset_plugins!
    end

    teardown do
      OKF::CLI.reset_plugins!
    end

    test "okf discovers this gem and answers `tui`" do
      OKF::CLI.load_plugins

      command = OKF::CLI.lookup("tui")

      refute_nil command, "okf/plugin.rb is on the load path, so `okf tui` must resolve"
      assert_equal :tui, command.id
      assert OKF::CLI.extension?(command), "and it is an extension, not something the base gem shipped"
    end

    test "the verb appears in okf's map, under the extensions heading" do
      status, out, = run_okf("--help")

      assert_equal 0, status
      assert_match(/^\s+installed extensions/, out)
      assert_match(/^\s+tui\s+.*full-screen terminal UI/, out)
    end

    test "`okf tui --help` is this gem's own usage, not okf's" do
      status, out, = run_okf("tui", "--help")

      assert_equal OKF::TUI::CLI::OK, status
      assert_includes out, "usage: okf tui"
    end

    test "`okf tui --version` reports this gem, not the base one" do
      status, out, = run_okf("tui", "--version")

      assert_equal OKF::TUI::CLI::OK, status
      assert_includes out, OKF::TUI::VERSION
    end

    # The gap this closes: help_rows has advertised `[DIR|@slug…]` since the verb
    # was registered, while the CLI accepted directories only — so the one
    # invocation okf's own map promises was the one that errored. Asserting the
    # advertisement and the behaviour together is what keeps them in step.
    test "the usage okf advertises is the usage that works" do
      OKF::CLI.load_plugins
      rows = OKF::CLI.lookup("tui").help_rows.flatten.join(" ")

      assert_includes rows, "@slug", "okf's map promises @slug — keep this and the CLI in step"

      with_registry("conformant") do
        _status, _out, err = run_okf("tui", "@conformant")

        refute_includes err, "not a directory",
          "`okf tui @slug` is advertised in okf's own help; it must not read as a path"
        assert_includes err, "needs an interactive terminal",
          "and it should get all the way to the terminal gate, past resolution"
      end
    end

    test "a bad argument is a usage error, with the same exit code as everywhere else" do
      status, _out, err = run_okf("tui", "/no/such/bundle")

      assert_equal OKF::TUI::CLI::USAGE_ERROR, status
      assert_includes err, "not a directory"
    end

    # The reason Command carries `input:` at all. Reaching for $stdin behind the
    # dispatcher's back would make this unassertable — the refusal only works
    # because the stream okf injected is the one the TUI checks.
    test "it refuses to run without a terminal, through okf too" do
      with_registry("okf-docs") do
        status, _out, err = run_okf("tui")

        assert_equal OKF::TUI::CLI::USAGE_ERROR, status
        assert_includes err, "needs an interactive terminal"
      end
    end

    # The dispatcher must add nothing but streams. There is no second door to
    # disagree with any more — the executable that used to be one is gone — but
    # the adapter can still get between argv and the CLI, and this is what says
    # it does not: the same run reached through okf and reached directly has to
    # give the same answer, down to the message.
    test "going through okf's dispatcher changes nothing but the streams" do
      with_empty_registry do
        through_okf = run_okf("tui")
        direct = run_cli_directly

        assert_equal direct[0], through_okf[0], "same exit code"
        assert_equal direct[2], through_okf[2], "and the same message — the adapter carries argv, nothing else"
      end
    end

    # Registration must stay cheap: `okf/plugin.rb` is read whenever a verb
    # misses or `okf help` runs, and the TTY toolkit (plus kramdown and rouge) is
    # a real cost to pay for a run that only wanted `okf lint`.
    #
    # A subprocess, because the suite has long since loaded tty-box by the time
    # this runs — asking in-process would assert nothing.
    test "loading the plugin does not drag in the terminal toolkit" do
      script = <<~RUBY
        require "okf"
        require "okf/cli"
        OKF::CLI.load_plugins
        raise "tui did not register" unless OKF::CLI.lookup("tui")
        puts defined?(TTY::Box) ? "LOADED" : "not-loaded"
      RUBY

      lib = File.expand_path("../../lib", __dir__)
      file = File.join(Dir.mktmpdir("okf-tui-probe"), "probe.rb")
      File.write(file, script)
      out = `#{RbConfig.ruby} -I#{lib} #{file} 2>&1`.strip
      FileUtils.remove_entry(File.dirname(file))

      assert_equal "not-loaded", out,
        "registering a command must not build one — the heavy require belongs in #call"
    end

    private

    def run_okf(*argv)
      out = StringIO.new
      err = StringIO.new
      status = OKF::CLI.start(argv, out: out, err: err, input: StringIO.new)
      [ status, out.string, err.string ]
    end

    def run_cli_directly(*argv)
      require "okf/tui/cli"
      out = StringIO.new
      err = StringIO.new
      status = OKF::TUI::CLI.run(argv, out: out, err: err, input: StringIO.new)
      [ status, out.string, err.string ]
    end
  end
end
