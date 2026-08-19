# frozen_string_literal: true

# Minitest's progress dots go through a pipe on CI, where stdout is block-
# buffered — so a run that wedges flushes nothing and the log cannot say which
# test it stopped after. That cost several rounds of guessing; syncing makes a
# hang name itself.
$stdout.sync = true

begin
  require "simplecov"

  gem_root = File.expand_path("..", __dir__) # okf-mcp/

  SimpleCov.start do
    enable_coverage :branch
    root gem_root
    add_filter "/test/"
    # `rake test:integration` points this at a separate report, so the
    # integration-only figure — the honest one, since it only counts what a
    # host can reach through the protocol — never overwrites the full suite's.
    coverage_dir File.expand_path(ENV["OKF_MCP_COVERAGE_DIR"] || "coverage", gem_root)
    command_name ENV["OKF_MCP_COVERAGE_NAME"] if ENV["OKF_MCP_COVERAGE_NAME"]
  end
  SimpleCov.external_at_exit = true
rescue LoadError
  # no coverage on this Ruby
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "okf/mcp"

require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "fileutils"

Minitest.after_run { SimpleCov.at_exit_behavior } if defined?(SimpleCov)

module OKF
  # The kernel's declarative Minitest sugar, ported so the suites read alike
  # across the monorepo: `test "name" do ... end` plus block setup/teardown.
  class TestCase < Minitest::Test
    def self.test(name, &block)
      method_name = "test_#{name.gsub(/\s+/, "_")}"
      raise ArgumentError, "duplicate test name: #{name}" if method_defined?(method_name)

      define_method(method_name, &block)
    end

    def self.setup(&block)
      define_method(:setup) do
        super()
        instance_eval(&block)
      end
    end

    def self.teardown(&block)
      define_method(:teardown) do
        instance_eval(&block)
        super()
      end
    end

    def sqlite3_loaded?
      require "okf/sqlite3"
      true
    rescue LoadError
      false
    end
  end
end
