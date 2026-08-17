# frozen_string_literal: true

require "test_helper"

# `okf pro --version` — the smallest command, and the one a script parses.
#
# It prints the bare semantic version, which is what `okf --version` and
# `okf mcp --version` already print. The caller has already named the extension
# on the command line, so a name in the output buys nothing and costs a script
# a `cut`.
class CLIVersionTest < OKF::Pro::TestCase
  test "every spelling of version answers identically" do
    printed = %w[version --version -v].map do |spelling|
      run = run_cli([ spelling ])

      assert_equal OKF::Pro::PASS, run.status, "`okf pro #{spelling}` is a success path"
      assert_empty run.err, "the version goes to stdout, so a script can read it"
      run.out
    end

    assert_equal 1, printed.uniq.size, "the three spellings must not drift apart"
    assert_equal "#{OKF::Pro::VERSION}\n", printed.first, "it prints the gem's own constant"
  end

  test "the version is the gem's, not the kernel's" do
    out = run_cli([ "--version" ]).out

    refute_equal "#{OKF::VERSION}\n", out,
      "`okf pro --version` must answer for okf-pro; the kernel's version is `okf --version`"
  end

  test "it prints nothing but the version" do
    assert_match(/\A\d+\.\d+\.\d+\n\z/, run_cli([ "--version" ]).out)
  end

  # The hook door takes a check name and nothing else. Its exit 0 means "the
  # gate ran and found nothing", so a `--version` that answered there would be a
  # gate reporting clean without looking at anything.
  test "the hook door does not answer version" do
    refute_includes OKF::Pro::CLI::HOOK_NAMES, "--version"
    refute_includes OKF::Pro::CLI::HOOK_NAMES, "-v"
  end
end
