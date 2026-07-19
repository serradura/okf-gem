# frozen_string_literal: true

require_relative "cli_integration_case"

# `okf <command> --help` — the help a user reaches once they know the verb but
# not its grammar. `cli_help_test.rb` owns the top-level map; this file owns the
# per-command help every parser answers, and the two contracts holding it up:
#
#   1. It answers like every other command — on @out, with a status `run`
#      returns. OptionParser's officious --help does neither: it prints past the
#      injected streams to the process's own stdout, and ends with `exit` rather
#      than a return, which is why no test in this suite could ask a command for
#      help before #help_flag existed — the first one to try took the runner
#      down with it, mid-run and green.
#   2. It names the @slug its positional accepts. The top-level map explains that
#      grammar once, in prose at the bottom, which the reader who typed
#      `okf lint --help` has already walked past.
#
# Filed at the root because it names no bundle: `okf lint --help` answers before
# a positional is ever resolved, so it belongs beside `help`, not under the three
# folders that exist to vary a bundle's identity.
class CLICommandHelpTest < CLIIntegrationCase
  # Every command surface whose positional accepts an @slug, as the argv reaching
  # it. Two separate paths land here, and the banners must not care which:
  # `resolve_ref` for the verbs that read a bundle, and `registry_slug` for the
  # three that edit the registry (del/default/rename), which also take the slug
  # bare so they can still reach an entry whose directory is gone.
  SLUG_TAKING = [
    %w[validate], %w[lint], %w[loose], %w[search], %w[index], %w[stats],
    %w[types], %w[tags], %w[files], %w[catalog], %w[graph], %w[render],
    %w[server], %w[registry set], %w[registry del], %w[registry default],
    %w[registry rename]
  ].freeze

  # The two surfaces that name no bundle and no slug: help must still answer,
  # but there is no @slug to advertise. `registry list` takes nothing; `skill`
  # takes a destination to write, which the registry knows nothing about.
  BUNDLE_LESS = [ %w[registry list], %w[skill] ].freeze

  ALL = (SLUG_TAKING + BUNDLE_LESS).freeze

  test "every command answers --help on stdout, with a status" do
    ALL.each do |argv|
      result = okf(*argv, "--help")

      assert_equal 0, result.status, "okf #{argv.join(" ")} --help: asking for help is a success path"
      assert_empty result.err, "okf #{argv.join(" ")} --help: help asked for goes to stdout"
      assert_match(/\AUsage: okf #{argv.join(" ")}\b/, result.out,
        "okf #{argv.join(" ")} --help: help leads with the banner of the command asked about")
    end
  end

  test "every command's --help prints its options, not just its banner" do
    # The banner alone is what the no-args error path prints. --help is the
    # surface that must also enumerate the flags, or it is that error message
    # wearing a flag's name.
    { %w[lint] => "--fail-on", %w[render] => "--layout", %w[tags] => "--by",
      %w[skill] => "--here", %w[registry set] => "--as", %w[search] => "--regexp" }.each do |argv, flag|
      result = okf(*argv, "--help")

      assert_match(/^\s+.*#{Regexp.escape(flag)}\b/, result.out,
        "okf #{argv.join(" ")} --help should document #{flag}")
    end
  end

  test "every command lists -h among its options" do
    ALL.each do |argv|
      assert_match(/^\s+-h, --help\b/, okf(*argv, "--help").out,
        "okf #{argv.join(" ")} --help: help that does not list itself is help nobody finds twice")
    end
  end

  test "every command that takes an @slug says so in its own banner" do
    SLUG_TAKING.each do |argv|
      banner = okf(*argv, "--help").out.lines.first

      assert_match(/@slug/, banner,
        "okf #{argv.join(" ")} takes an @slug, so its banner must show one: #{banner.strip}")
    end
  end

  test "no bundle-less command invents an @slug it cannot take" do
    BUNDLE_LESS.each do |argv|
      banner = okf(*argv, "--help").out.lines.first

      refute_match(/@slug/, banner,
        "okf #{argv.join(" ")} resolves no bundle, so its banner must not promise an @slug: #{banner.strip}")
    end
  end

  test "-h is the same help as --help" do
    ALL.each do |argv|
      short = okf(*argv, "-h")
      long = okf(*argv, "--help")

      assert_equal 0, short.status, "okf #{argv.join(" ")} -h: asking for help is a success path"
      assert_equal long.out, short.out, "okf #{argv.join(" ")}: -h and --help must not drift apart"
    end
  end

  test "the banner an error prints is the one --help leads with" do
    # Two paths, one string: the banner printed to stderr when the positional is
    # missing, and the first line of --help. They drift the moment a hint is
    # added to one of them. `server` is absent because a bare `okf server` is not
    # an error — it serves the registry.
    (SLUG_TAKING - [ %w[server] ]).each do |argv|
      asked = okf(*argv, "--help").out.lines.first.strip
      thrust = okf(*argv)

      assert_equal 2, thrust.status, "okf #{argv.join(" ")} with no positional is a usage error"
      assert_includes thrust.err, asked, "okf #{argv.join(" ")}: the banner on error is the one --help shows"
    end
  end

  # `search` picks its engine from what the query needs, and says nothing about
  # it: no note on stderr, nothing in the header, and no --engine flag to
  # discover. That makes --help the *only* place the engine story is told, so
  # this attribution is load-bearing text rather than decoration. Drop it and the
  # scan engine — the one thing that still matches a phrase, an infix, or a
  # dotted identifier exactly — becomes unreachable in practice.
  ENGINE_BEARING = { "--regexp" => "scan", "--fuzzy" => "index" }.freeze

  test "search --help attributes each capability flag to the engine that answers it" do
    help = okf("search", "--help").out

    ENGINE_BEARING.each do |flag, engine|
      block = option_block(help, flag)

      refute_empty block, "search --help must document #{flag}"
      assert_includes block, "#{engine} engine",
        "routing is silent, so #{flag}'s own help is the only place its engine can be named"
    end
  end

  test "search --help names the exactness -e buys back, or the tradeoff is undiscoverable" do
    help = okf("search", "--help").out

    assert_match(/token/i, help, "the default engine matches tokens; help must say so")
    assert_match(/7\.2\.0|customer_id|dedup key/, help,
      "an abstract 'matches raw text' teaches nobody when to reach for -e; the help needs a concrete example")
  end

  test "the @slug the read views advertise is one they really take" do
    # Keeps SLUG_TAKING a claim about behavior rather than a transcription of the
    # banners — without it, a hint added to a verb that cannot resolve an @slug
    # would pass every assertion above. Only the read views are exercised here:
    # by_registry/ owns proving that each registry verb resolves one (they
    # mutate, so each needs its own registry), and this file owns the text.
    reads = SLUG_TAKING - [ %w[server], %w[search], %w[render] ] - SLUG_TAKING.select { |a| a.first == "registry" }
    with_registry("conformant") do
      reads.each do |argv|
        result = okf(*argv, "@conformant")

        refute_equal 2, result.status,
          "okf #{argv.join(" ")} @conformant: its banner promises an @slug, so it must resolve one — #{result.err.strip}"
      end

      assert_equal 0, okf("search", "@conformant", "orders").status, "search's banner promises an @slug"
      assert_equal 0, okf("render", "@conformant", "-o", File.join(@out_dir, "graph.html")).status,
        "render's banner promises an @slug"
    end
  end

  private

  # A flag's whole help entry: the line carrying the flag plus any continuation
  # lines OptionParser wrapped underneath it. Asserting on the block rather than
  # the single line keeps the guard about *what the help says* instead of how
  # wide the terminal was when it was written.
  def option_block(help, flag)
    lines = help.lines
    # Anchored to the options column: the banner names --regexp too, inside the
    # grammar, and matching that instead would assert against the wrong line.
    start = lines.index { |line| line.match?(/\A\s+(-\S,\s+)?#{Regexp.escape(flag)}\b/) }
    return "" if start.nil?

    block = [ lines[start] ]
    lines[(start + 1)..-1].to_a.each do |line|
      break if line.strip.empty? || line.match?(/\A\s{0,12}-/)

      block << line
    end
    block.join
  end
end
