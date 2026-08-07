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
        require "okf/sqlite3"
        engine = OKF::Sqlite3::Backend.new
        suitable?(engine) ? engine : MemoryBackend.new
      rescue LoadError
        MemoryBackend.new
      end

      def self.suitable?(engine)
        ENGINE_METHODS.all? { |name| engine.respond_to?(name) }
      end
    end
  end
end
