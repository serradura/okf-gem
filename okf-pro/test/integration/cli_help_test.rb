# frozen_string_literal: true

require "test_helper"

# `okf pro` with no command, and with `--help`.
#
# Every other okf verb answers `-h`/`--help` with its own usage, and this one
# answered "ENFORCEMENT MISCONFIGURED — no check named '--help'" — which is
# technically true and useless: a person looking for the command list is told
# their command list is not a check.
class CLIHelpTest < OKF::Pro::TestCase
  %w[--help -h help].each do |flag|
    test "#{flag} prints the usage on stdout and exits 0" do
      run = run_cli([ flag ])

      assert_equal OKF::Pro::PASS, run.status
      assert_empty run.err, "help is not an error, so it does not go to stderr"
      assert_match(/\AUsage: okf pro <command>/, run.out)
    end
  end

  test "the usage lists every verb a user can invoke" do
    out = run_cli([ "--help" ]).out

    OKF::Pro::CLI::SCAFFOLD.each { |verb| assert_match(/^\s+#{verb}\b/, out) }
    OKF::Pro::CLI::READERS.each { |verb| assert_match(/^\s+#{verb}\b/, out) }
    OKF::Pro::CLI::WRITERS.each { |verb| assert_match(/^\s+#{verb}\b/, out) }
    assert_match(/^\s+hook\b/, out)
  end

  # A verb absent from the usage does not exist to a reader, and the usage is
  # the only manual `okf pro` ships — `okf help` prints one row for the whole
  # gem. So the coupling runs both ways rather than as a list somebody
  # remembers to extend.
  test "the usage documents no verb the dispatcher does not answer to" do
    documented = OKF::Pro::CLI::USAGE.map(&:first) - [ "hook" ]

    assert_empty documented - OKF::Pro::CLI::NAMES
  end

  # The check names are the part nobody can guess, and the part a settings.json
  # is written from.
  test "the usage names every hook check" do
    out = run_cli([ "--help" ]).out

    OKF::Pro::CLI::HOOK_NAMES.each do |check|
      assert_match(/#{Regexp.escape(check)}/, out, "the usage omits the '#{check}' gate")
    end
  end

  # `parse_flags` tells a user that `okf pro --help` lists what each verb takes,
  # and for a while that was simply untrue — the usage named no flag at all. The
  # table is read from `FLAGS` rather than typed beside it, and this is the pin
  # that keeps a new flag from being invisible.
  test "the usage names every flag every verb accepts" do
    out = run_cli([ "--help" ]).out

    OKF::Pro::CLI::FLAGS.each do |verb, flags|
      line = out.lines.grep(/^\s+#{verb}\s+--/).first

      refute_nil line, "the usage lists no flags for #{verb}"
      flags.each do |flag|
        assert_includes line, OKF::Pro::CLI::FLAG_HELP.fetch(flag),
          "#{verb} accepts #{flag} and the usage does not say so"
      end
    end
  end

  test "the usage says the writers take none, so a flag there is content" do
    out = run_cli([ "--help" ]).out

    assert_match(/The writers take no flags at all/, out)
    # `audit --json` refuses with "`okf pro --help` lists what each verb takes",
    # and the Flags block simply omitted them — so the reader it sent here could
    # not confirm "none" from an absence.
    assert_match(/`audit` and `records` take none/, out)
    assert_match(/`--` is what escapes content that starts with a dash/, out)
  end

  # The two things that surprise people, and both cost something when they do:
  # a ref is not a path here, and `hook` does not speak this repo's exit codes.
  test "the usage states the addressing rule and the exit codes" do
    out = run_cli([ "--help" ]).out

    assert_match(/not an @slug/, out)
    assert_match(/0 pass, 2 block/, out)
    assert_match(/non-blocking/, out)
  end

  # No command is a usage error, not a pass: `okf pro` alone did nothing a
  # caller asked for, and exit 0 would say it did.
  test "no command at all prints the usage on stderr and exits 2" do
    run = run_cli([])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_empty run.out
    assert_match(/\AUsage: okf pro <command>/, run.err)
  end

  # `okf help` prints a map, not a manual. It gets ONE row from this gem — the
  # kernel takes only an extension's first — so the row must be a summary of the
  # verb rather than one of its commands, or the map advertises `pro setup`
  # and silently hides seven siblings.
  #
  # The command list lives here, behind `okf pro --help`, which is what the
  # extensions heading now tells the reader.
  test "the map row summarises the verb instead of naming one command" do
    require "okf/plugin"
    rows = OKF::CLI::Pro.help_rows

    assert_equal 1, rows.size, "the kernel prints the first row only; a second is a claim nobody sees"
    grammar, description = rows.first
    assert_match(/\Apro\s+<command>/, grammar, "the row's grammar is the verb, not a subcommand")

    named = OKF::Pro::CLI::USAGE.map(&:first).select { |verb| description.include?(verb) }
    assert_empty named, "the one visible row must not single out #{named.join(", ")} over its siblings"
  end

  # The map has to name the way out of itself, the same way `okf --help` ends
  # with `okf --version`.
  test "the usage names the version flag" do
    assert_match(/^okf pro --version$/, run_cli([ "--help" ]).out)
  end
end
