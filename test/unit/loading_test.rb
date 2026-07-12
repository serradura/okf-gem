# frozen_string_literal: true

require "test_helper"
require "rbconfig"

# Loading contract: `require "okf"` pulls in the pure library only. The CLI and
# the skill installer — the two optparse/argv-facing shells — load on demand
# (from `exe/okf`, or an explicit `require`), so embedding the library in another
# app never drags in the command-line machinery.
class OKF::LoadingTest < OKF::TestCase
  LIB = File.expand_path("../../lib", __dir__)

  test "require \"okf\" loads the library but not the CLI or skill shells" do
    assert_equal "core", probe(<<~RUBY)
      require "okf"
      shells = defined?(OKF::CLI) || defined?(OKF::Skill)
      print(defined?(OKF::Bundle) && !shells ? "core" : "leaked")
    RUBY
  end

  test "the CLI and skill shells load on an explicit require" do
    assert_equal "ok", probe(<<~RUBY)
      require "okf"
      require "okf/cli"
      require "okf/skill"
      print(defined?(OKF::CLI) && defined?(OKF::Skill) ? "ok" : "missing")
    RUBY
  end

  private

  # Run the snippet in a clean Ruby process against the checkout's lib and return
  # its stdout — the in-process suite has already required the shells, so only a
  # fresh interpreter can observe what a bare `require "okf"` loads.
  def probe(source)
    IO.popen([ RbConfig.ruby, "-I", LIB, "-e", source ], &:read)
  end
end
