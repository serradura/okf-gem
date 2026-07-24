# frozen_string_literal: true

require_relative "cli_integration_case"

# `okf version` — the smallest command, and the one a script parses. It prints
# the semantic version and nothing else, under every spelling.
class CLIVersionTest < CLIIntegrationCase
  test "version prints just the semantic version" do
    status = nil
    assert_output(/\A\d+\.\d+\.\d+\n\z/, "") { status = start_cli("--version") }
    assert_equal 0, status
  end

  test "every spelling of version answers identically" do
    printed = %w[version --version -v].map do |spelling|
      result = okf(spelling)
      assert_equal 0, result.status, "`okf #{spelling}` is a success path"
      assert_empty result.err, "the version goes to stdout, so a script can read it"
      result.out
    end

    assert_equal 1, printed.uniq.size, "the three spellings must not drift apart"
    assert_equal "#{OKF::VERSION}\n", printed.first, "it prints the gem's own constant"
  end
end
