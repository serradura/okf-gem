# frozen_string_literal: true

require "test_helper"

# How a verb is told which tree to work on — and the two ways of getting it
# wrong that must never be answered quietly.
#
# `okf help` promises "Anywhere a `<dir>` goes, an `@slug` goes". That promise
# is the kernel's, and this gem does not keep it: the registry answers where a
# BUNDLE is, and a brain is the repository AROUND one — the hooks, the git
# hooks, the workflow — which a ref does not name. So a leading `@` is refused
# by name rather than reaching the filesystem and coming back "no such
# directory", which is the failure okf-tui already shipped once and records.
#
# A second positional is refused for the reason ../AGENTS.md gives against
# `okf lint a b`: reading the first and ignoring the rest is a wrong answer
# carrying a clean exit code.
class CLIAddressingTest < OKF::Pro::TestCase
  # Every verb that takes a directory. `hook` and `session-context` are absent
  # because they take a check name and read their subject from the event.
  DIR_VERBS = %w[audit records snapshot unverified state board friction setup upgrade skill].freeze

  # The writers take what to act on FIRST and the directory second, so their
  # addressing is proven with that argument in place — the two failures are the
  # same, and a `@slug` reaching the filesystem behind a selector is no better
  # than one reaching it alone. Each verb's own file carries these too; this is
  # the table that cannot be forgotten when a verb is added.
  WRITE_VERBS = { "capture" => "a thing", "promote" => "alpha", "demote" => "alpha", "close" => "alpha" }.freeze

  DIR_VERBS.each do |verb|
    test "#{verb} refuses a registry ref by name" do
      run = run_cli([ verb, "@handbook" ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/registry ref/, run.err, "#{verb} must say what is wrong, not fail on a missing directory")
    end

    test "#{verb} refuses a second positional rather than ignoring it" do
      Dir.mktmpdir do |a|
        Dir.mktmpdir do |b|
          run = run_cli([ verb, a, b ])

          assert_equal OKF::Pro::BLOCK, run.status
          assert_match(/takes one directory/, run.err)
        end
      end
    end
  end

  WRITE_VERBS.each do |verb, argument|
    test "#{verb} refuses a registry ref by name" do
      run = run_cli([ verb, argument, "@handbook" ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/registry ref/, run.err)
    end

    test "#{verb} refuses a second positional rather than ignoring it" do
      Dir.mktmpdir do |a|
        Dir.mktmpdir do |b|
          run = run_cli([ verb, argument, a, b ])

          assert_equal OKF::Pro::BLOCK, run.status
          assert_match(/takes one directory/, run.err)
        end
      end
    end
  end

  # `journal` is the one verb whose first argument is a subcommand rather than
  # a selector, so its addressing sits behind `open`.
  test "journal open refuses a registry ref by name" do
    run = run_cli(%w[journal open @handbook])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/registry ref/, run.err)
  end

  # Every name the dispatcher answers to is either a check, a hook name, or a
  # verb with a row in the usage. A name in NAMES with no row is a surface a
  # reader cannot find; a row naming no name is a promise nothing keeps.
  test "every dispatchable verb has a usage row and every row is dispatchable" do
    rows = OKF::Pro::CLI::USAGE.map(&:first)
    verbs = OKF::Pro::CLI::READERS + OKF::Pro::CLI::WRITERS + OKF::Pro::CLI::SCAFFOLD

    assert_empty verbs - rows, "dispatchable and undocumented"
    assert_empty rows - verbs - [ "hook" ], "documented and undispatchable"
  end

  # The readers and writers are NOT hook checks: a CI verb reads no stdin and
  # cannot block, so a settings.json typo naming one would install a gate that
  # always reports fine.
  test "no reader or writer is accepted at the hook door" do
    (OKF::Pro::CLI::READERS + OKF::Pro::CLI::WRITERS).each do |verb|
      refute_includes OKF::Pro::CLI::HOOK_NAMES, verb,
        "`okf pro hook #{verb}` would be a gate that reads no event and never blocks"
    end
  end

  # The bundle-reading verbs default to the working directory; the generator's
  # do too, except `skill`, which has no sensible default destination.
  test "a bundle verb with no argument reads the working directory" do
    with_bundle do |b|
      Dir.chdir(b.path) do
        assert_equal OKF::Pro::PASS, run_cli([ "audit" ]).status
      end
    end
  end

  test "setup with no argument writes into the working directory" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        assert_equal OKF::Pro::PASS, run_cli([ "setup" ]).status
      end
      assert File.file?(File.join(dir, ".okf", "board.md"))
    end
  end

  # An unknown verb is enforcement that did not run. The shell dispatcher this
  # replaced fell off the end of its `case` and exited 0 on a typo — silence in
  # the one place the contract names.
  test "an unknown verb refuses and lists what it knows" do
    run = run_cli([ "audti", "." ])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/ENFORCEMENT MISCONFIGURED/, run.err)
    assert_match(/no check named 'audti'/, run.err)
    assert_match(/audit/, run.err)
  end

  # No verb at all now prints the usage rather than complaining that the empty
  # string is not a check. It still exits 2 — see cli_help_test, which owns that
  # surface.
end
