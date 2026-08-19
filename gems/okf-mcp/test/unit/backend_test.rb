# frozen_string_literal: true

require "test_helper"

class BackendTest < OKF::TestCase
  test "detect degrades to the memory backend when okf-sqlite3 is absent" do
    skip "okf-sqlite3 is installed; the absence path is not testable here" if sqlite3_loaded?

    assert_instance_of OKF::MCP::MemoryBackend, OKF::MCP::Backend.detect
  end

  # "A broken sqlite3 build degrades to the memory backend instead of crashing
  # the server" was only ever true of the `require`. An engine that loads and
  # then fails to construct — a connection it cannot open, a schema check, a
  # constant renamed out from under us — took the server down at boot, which is
  # the one thing the fallback exists to prevent.
  test "detect degrades when the engine loads but cannot be constructed" do
    [ RuntimeError, NameError, Errno::EACCES ].each do |failure|
      OKF::MCP::Backend.stub(:build_engine, -> { raise failure, "engine is broken" }) do
        assert_instance_of OKF::MCP::MemoryBackend, OKF::MCP::Backend.detect,
          "#{failure} at construction was fatal instead of degrading"
      end
    end
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
