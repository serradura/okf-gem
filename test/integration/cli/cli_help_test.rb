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

  # The commands the map shows taking a bundle — every row whose grammar must
  # carry the hint. `skill` is absent: its <dest> is a directory to write, which
  # the registry knows nothing about.
  BUNDLE_COMMANDS = %w[
    server render lint loose validate search index stats types tags files catalog graph
  ].freeze

  test "help explains the @slug grammar the verbs share" do
    result = okf("--help")

    assert_match(/@slug/, result.out, "every <dir> takes an @slug, so help must say so once")
    assert_match(/\$OKF_HOME/, result.out, "the registry's location is the first thing an @slug depends on")
  end

  test "the map shows @slug on every command that takes one" do
    # The grammar column is where a reader skimming the map learns what a verb
    # accepts. Explaining @slug only in the prose underneath asks them to read to
    # the bottom to discover that `lint <dir>` was never the whole truth.
    result = okf("--help")

    BUNDLE_COMMANDS.each do |command|
      row = result.out.lines.find { |l| l =~ /^\s+#{command}\s/ }
      refute_nil row, "help should list the `#{command}` command"
      assert_match(/@slug/, row, "the `#{command}` row takes an @slug, so its grammar must show one: #{row.strip}")
    end
  end

  test "the map's grammar column agrees with each command's own banner" do
    # Two places name the same grammar; both are read, and they drift silently.
    # `<dir|@slug>` is the shared spelling, so the map and the banner teach one
    # token rather than two.
    map = okf("--help").out

    (BUNDLE_COMMANDS - %w[server search]).each do |command|
      assert_match(/^\s+#{command}\s+<dir\|@slug>/, map, "the map spells #{command}'s bundle <dir|@slug>")
      assert_match(/\AUsage: okf #{command} <dir\|@slug>/, okf(command, "--help").out,
        "and #{command}'s own banner spells it the same way")
    end
  end

  test "every registry subcommand that names a bundle shows @slug in the map" do
    map = okf("--help").out

    { "set" => "<dir|@slug>", "del" => "<dir|@slug>",
      "default" => "<@slug>", "rename" => "<@slug> <new>" }.each do |subcommand, grammar|
      assert_match(/^\s+registry\s+#{subcommand} #{Regexp.escape(grammar)}/, map,
        "the map should spell `registry #{subcommand}` as #{grammar}")
    end
  end

  test "the note defines @slug, and both spellings of it" do
    # The map shows @slug on nearly every row, so the prose has to define the
    # token it uses — naming both the slug form and bare @, or the rows are
    # notation pointing at nothing.
    result = okf("--help")
    note = result.out.split(/^\n/).find { |para| para =~ /^@slug names/ }

    refute_nil note, "the map's @slug rows need a note defining the token"
    assert_match(/registry set/, note, "the note names where a slug comes from")
    assert_match(/bare @/, note, "and the bare @ that means the default")
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
