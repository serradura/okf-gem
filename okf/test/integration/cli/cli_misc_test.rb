# frozen_string_literal: true

require_relative "cli_integration_case"

# The dispatcher itself, before any command runs: the usage-error paths (unknown
# command, missing directory, bad flag, no command) and the contract that a
# rejected invocation leaves stdout clean. Each command has its own file, and
# `version`/`help` live in cli_version_test.rb / cli_help_test.rb.
class CLIMiscTest < CLIIntegrationCase
  test "an unknown command reports the error and usage on stderr (exit 2)" do
    result = okf("frobnicate")

    assert_equal 2, result.status
    assert_match(/unknown command 'frobnicate'/, result.err)
    assert_match(/okf <command> \[options\]/, result.err)
    assert_empty result.out
  end

  test "a missing directory is a usage error that names the ref grammar (exit 2)" do
    missing = File.join(BUNDLES, "does-not-exist")
    result = okf("validate", missing)

    assert_equal 2, result.status
    # The error is the natural teaching moment for @slug addressing: it must name
    # the target grammar (path | @slug | @) and point at the registry, not just
    # say "not a directory" — the friction that cost a consume session ~2.5k tokens.
    assert_match(/#{Regexp.escape(missing)} is not a directory or a registry ref/, result.err)
    assert_match(/@slug names a registered bundle/, result.err)
    assert_match(/okf registry list/, result.err)
  end

  test "an unknown flag is a usage error on stderr (exit 2)" do
    result = okf("validate", fixture("conformant"), "--bogus-flag")

    assert_equal 2, result.status
    assert_match(/invalid option: --bogus-flag/, result.err)
  end

  test "no command prints usage on stderr (exit 2)" do
    result = okf

    assert_equal 2, result.status
    assert_match(/okf <command> \[options\]/, result.err)
  end
end
