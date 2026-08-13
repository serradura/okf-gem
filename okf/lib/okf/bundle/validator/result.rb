# frozen_string_literal: true

module OKF
  class Bundle
    class Validator
      # The outcome of a §9 conformance check (see OKF::Bundle::Validator): hard `errors`,
      # soft `warnings`, and file `counts`. Conformant iff there are no errors.
      class Result
        attr_reader :errors, :warnings, :counts

        def initialize
          @errors = []
          @warnings = []
          @counts = { concepts: 0, indexes: 0, logs: 0 }
        end

        def valid?
          errors.empty?
        end

        def add_error(path, message)
          errors << { path: path, message: message }
        end

        # `check:` (a stable id) and `source:` (:spec | :convention) make a
        # warning machine-readable; errors keep their exact two-key shape —
        # consumers already read it, so new keys land on warnings only.
        def add_warning(path, message, check: nil, source: nil)
          warnings << { path: path, message: message, check: check, source: source }
        end

        def count(kind)
          @counts[kind] += 1 if @counts.key?(kind)
        end
      end
    end
  end
end
