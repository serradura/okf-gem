# frozen_string_literal: true

require "test_helper"
require "okf/tui/cli"

module Integration
  # `okf tui`'s surface, driven straight: real argv, real streams, real exit
  # codes. It keeps the same contract as the `okf` CLI — 0 ok, 1 a failure, 2 a
  # usage error.
  #
  # This calls CLI.run itself rather than going through okf's dispatcher, which
  # plugin_test.rb does. The pair is deliberate and the split is where the risk
  # is: the dispatcher must add nothing but streams, so proving the grammar here
  # and the wiring there keeps each failure legible.
  class CLITest < OKF::TUI::TestCase
    test "--help prints the usage and exits 0" do
      status, out, = run_cli("--help")

      assert_equal OKF::TUI::CLI::OK, status
      assert_includes out, "usage: okf tui"
      assert_includes out, "$OKF_HOME"
    end

    test "--version prints the version" do
      status, out, = run_cli("--version")

      assert_equal OKF::TUI::CLI::OK, status
      assert_includes out, OKF::TUI::VERSION
    end

    test "an unknown option is a usage error" do
      status, _out, err = run_cli("--nope")

      assert_equal OKF::TUI::CLI::USAGE_ERROR, status
      assert_includes err, "unknown option: --nope"
    end

    test "a directory that is not one is a usage error" do
      status, _out, err = run_cli("/no/such/bundle")

      assert_equal OKF::TUI::CLI::USAGE_ERROR, status
      assert_includes err, "not a directory"
    end

    test "an empty registry says so and names the file it read" do
      with_empty_registry do
        status, _out, err = run_cli

        assert_equal OKF::TUI::CLI::USAGE_ERROR, status
        assert_includes err, "the registry at"
        assert_includes err, "is empty"
        assert_includes err, "okf registry set"
      end
    end

    # A terminal is the whole point; without one there is nothing to drive. This
    # is what keeps `okf tui | cat` from hanging on a read that never comes.
    test "it refuses to run without a terminal" do
      with_registry("okf-docs") do
        status, _out, err = run_cli

        assert_equal OKF::TUI::CLI::USAGE_ERROR, status
        assert_includes err, "needs an interactive terminal"
      end
    end

    # The search view needs more of okf than an older gem carries. When that is
    # missing the failure is invisible: Workspace#search rescues it and every
    # query answers "no matches", which reads as an empty bundle rather than a
    # broken install. Refusing to boot is the only honest answer — this is the
    # difference between a wrong screen and a message.
    test "an okf without the search facade refuses to boot instead of finding nothing" do
      with_registry("okf-docs") do
        OKF::TUI.stub(:search_capable?, false) do
          status, _out, err = run_cli

          assert_equal OKF::TUI::CLI::FAILURE, status
          assert_includes err, "OKF::Bundle::Search"
        end
      end
    end

    # The guard covers the prepared corpus too, not just the facade it started
    # with: a `prepare` that is not there fails the same silent way — rescued into
    # "no matches" — so it has to be part of the same refusal.
    test "the capability check names every method search actually calls" do
      assert OKF::TUI.search_capable?, "the resolved okf should satisfy it"

      %i[across prepare with].each do |name|
        assert OKF::Bundle::Search.respond_to?(name),
          "Workspace#search calls Search.#{name}; the boot check has to require it"
      end
    end

    private

    # StringIO is not a tty, which is exactly the point for every case above.
    def run_cli(*argv)
      out = StringIO.new
      err = StringIO.new
      status = OKF::TUI::CLI.run(argv, out: out, err: err, input: StringIO.new)
      [ status, out.string, err.string ]
    end
  end
end
