# frozen_string_literal: true

require "test_helper"

class BackendTest < OKF::TestCase
  test "detect degrades to the memory backend when okf-sqlite3 is absent" do
    skip "okf-sqlite3 is installed; the absence path is not testable here" if sqlite3_loaded?

    assert_instance_of OKF::MCP::MemoryBackend, OKF::MCP::Backend.detect
  end

  test "suitable? is the duck type, not a version pin" do
    quacking = Class.new do
      def refresh(_root); end

      def search(_root, _terms, _filters); end

      def catalog(_root, _filters); end

      def capabilities; end
    end
    assert OKF::MCP::Backend.suitable?(quacking.new)
    refute OKF::MCP::Backend.suitable?(Object.new)
  end
end
