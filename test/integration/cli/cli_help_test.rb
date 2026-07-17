# frozen_string_literal: true

require_relative "cli_integration_case"

# `okf help` — the map an agent reads before it knows anything else. Its job is
# to be complete: a verb the dispatcher answers but help never mentions is a
# feature nobody finds.
class CLIHelpTest < CLIIntegrationCase
  # Every verb `run` dispatches, minus the two that are their own help.
  COMMANDS = %w[
    skill server render registry lint loose validate search index stats types tags files catalog graph
  ].freeze

  test "help lists every command with a description" do
    result = okf("--help")

    assert_equal 0, result.status
    assert_match(/okf <command> \[options\]/, result.out)
    COMMANDS.each do |command|
      assert_match(/^\s+#{command}\s+\S.*/, result.out, "help should list the `#{command}` command")
    end
  end

  test "help documents the registry subcommands, not just the umbrella" do
    result = okf("--help")

    %w[list set del default rename].each do |subcommand|
      assert_match(/^\s+registry\s+.*\b#{subcommand}\b/, result.out,
        "help should reach `registry #{subcommand}` — an unlisted subcommand is unfindable")
    end
  end

  test "help explains the @ref grammar the verbs share" do
    result = okf("--help")

    assert_match(/@slug/, result.out, "every <dir> takes an @ref, so help must say so once")
    assert_match(/\$OKF_HOME/, result.out, "the registry's location is the first thing a ref depends on")
  end

  test "every spelling of help answers identically, on stdout" do
    printed = %w[help --help -h].map do |spelling|
      result = okf(spelling)
      assert_equal 0, result.status, "asking for help is a success path"
      assert_empty result.err, "help asked for goes to stdout; only help *thrust upon you* goes to stderr"
      result.out
    end

    assert_equal 1, printed.uniq.size, "the three spellings must not drift apart"
  end

  test "help is the same text the usage errors print to stderr" do
    asked = okf("--help").out
    thrust = okf("frobnicate").err

    assert_equal 2, okf("frobnicate").status
    assert_includes thrust, asked.lines.first.strip, "the banner a user is shown on error is the one they can ask for"
  end
end
