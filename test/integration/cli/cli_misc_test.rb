# frozen_string_literal: true

require_relative "cli_integration_case"

# `okf` top-level behavior that isn't tied to one command: version, help, and the
# usage-error paths (unknown command, missing directory, bad flag, no command).
class CLIMiscTest < CLIIntegrationCase
  test "version prints just the semantic version" do
    status = nil
    assert_output(/\A\d+\.\d+\.\d+\n\z/, "") { status = start_cli("--version") }
    assert_equal 0, status
  end

  test "help lists every command with a description" do
    result = okf("--help")

    assert_equal 0, result.status
    assert_match(/okf <command> \[options\]/, result.out)
    %w[skill server validate lint loose catalog files tags stats graph].each do |command|
      assert_match(/^\s+#{command}\s+\S.*/, result.out, "help should list the `#{command}` command")
    end
  end

  test "an unknown command reports the error and usage on stderr (exit 2)" do
    result = okf("frobnicate")

    assert_equal 2, result.status
    assert_match(/unknown command 'frobnicate'/, result.err)
    assert_match(/okf <command> \[options\]/, result.err)
    assert_empty result.out
  end

  test "a missing directory is a usage error on stderr (exit 2)" do
    result = okf("validate", File.join(BUNDLES, "does-not-exist"))

    assert_equal 2, result.status
    assert_match(/is not a directory/, result.err)
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
