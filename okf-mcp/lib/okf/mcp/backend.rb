# frozen_string_literal: true

module OKF
  module MCP
    # The seam between the shell and the optional okf-sqlite3 engine. One
    # `require` answers both "is it installed?" and "does the native extension
    # load?" — a broken sqlite3 build degrades to the memory backend instead
    # of crashing the server, silently except in the boot line and
    # list_bundles.backend. Feature detection, not version pinning: the engine
    # only has to answer the duck type below, so the gems release
    # independently. Backends speak symbol-keyed rows in the kernel's catalog
    # and search shapes; `score` and `snippet` are optional extras.
    module Backend
      ENGINE_METHODS = %i[refresh search catalog capabilities].freeze

      def self.detect
        engine = build_engine
        suitable?(engine) ? engine : MemoryBackend.new
      rescue LoadError, StandardError
        MemoryBackend.new
      end

      # Both ways the optional engine can fail are on this side of the seam, so
      # the one rescue above covers both: the `require` (absent gem, native
      # extension that will not load) and the construction (a connection it
      # cannot open, a schema check, a constant renamed out from under us).
      # Catching only LoadError left the second half fatal, which is exactly
      # what "degrades instead of crashing the server" promises it is not.
      def self.build_engine
        require "okf/sqlite3"
        OKF::Sqlite3::Backend.new
      end

      def self.suitable?(engine)
        ENGINE_METHODS.all? { |name| engine.respond_to?(name) }
      end
    end
  end
end
