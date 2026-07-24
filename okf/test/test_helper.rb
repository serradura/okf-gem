# frozen_string_literal: true

# SimpleCov needs Ruby 2.5+; the suite itself runs down to 2.4, so coverage is
# simply skipped where it cannot load.
begin
  require "simplecov"

  gem_root = File.expand_path("..", __dir__)   # okf/
  repo_root = File.expand_path("..", gem_root) # the monorepo root

  SimpleCov.start do
    enable_coverage :branch
    # The repo root, not this gem: SimpleCov tracks nothing outside its root, and
    # the plugin's curation hook (../plugin/hooks/scripts/curate.rb) is a
    # repo-level file this suite tests. Left at the default, moving the gem into
    # a subdirectory dropped its ~100 lines out of the report — the coverage
    # percentage went *up* while the thing being measured got smaller, which is
    # the one way a coverage figure lies without anything failing.
    root repo_root
    add_filter "/test/"
    # The report itself stays inside the gem, though: it is this gem's report,
    # and `root` above only says what may be *counted*. Absolute, because a
    # relative coverage_dir resolves against root and would land it at the
    # repo root.
    #
    # `rake test:integration` points these at a separate report, so the
    # integration-only figure — the honest one, since it only counts what a user
    # can reach through the CLI — never overwrites the full suite's.
    coverage_dir File.join(gem_root, ENV["OKF_COVERAGE_DIR"] || "coverage")
    command_name ENV["OKF_COVERAGE_NAME"] if ENV["OKF_COVERAGE_NAME"]
  end
  # Generate the coverage report *after* the Minitest suite finishes rather than
  # when SimpleCov's own at_exit fires. Under `rake test`, the test task requires
  # minitest/autorun before this file, which (via LIFO at_exit ordering) would
  # otherwise let SimpleCov freeze an empty report before any test runs.
  SimpleCov.external_at_exit = true
rescue LoadError
  # no coverage on this Ruby
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "okf"

require "minitest/autorun"

Minitest.after_run { SimpleCov.at_exit_behavior } if defined?(SimpleCov)

module OKF
  # The suite's base class: plain Minitest plus the three bits of declarative
  # sugar the tests use (`test "..."`, block `setup`/`teardown`) — so not even
  # the tests need ActiveSupport.
  class TestCase < Minitest::Test
    def self.test(name, &block)
      method_name = "test_#{name.gsub(/\W+/, "_")}"
      raise ArgumentError, "duplicate test name: #{name}" if method_defined?(method_name)

      define_method(method_name, &block)
    end

    def self.setup(&block)
      define_method(:setup) do
        super()
        instance_exec(&block)
      end
    end

    def self.teardown(&block)
      define_method(:teardown) do
        instance_exec(&block)
        super()
      end
    end

    # The one non-Minitest assertion the suite uses (an ActiveSupport::TestCase
    # extra): the block must run without raising.
    def assert_nothing_raised
      yield
      assert true
    end
  end
end
