# frozen_string_literal: true

module OKF
  module Pro
    # `okf validate` and `okf lint --fail-on warn`, in process. The CLI would
    # answer the same questions at the cost of two interpreter boots per edit;
    # the analyzers are pure and take the bundle directly.
    module Conformance
      module_function

      def check(target)
        return [] if target.nil?

        result = ::OKF::Bundle::Validator.call(target.bundle)
        unless result.valid?
          lines = result.errors.map { |e| "  #{e[:path]}: #{e[:message]}" }
          return [ "okf validate failed after your edit:\n#{lines.join("\n")}" ]
        end

        # §9 forbids the validator from REJECTING a soft problem, so these are
        # warnings rather than errors — and this gate used to read `errors` only
        # and drop every one of them on the floor.
        #
        # That is not a cosmetic loss. It is where the trust family goes wrong
        # in the worst direction: `verified: human:rod` written as a scalar
        # fires the attestation guard (the word is there), so the owner is asked
        # and approves — and then the reader drops the malformed value, the tier
        # stays `unverified`, and the To-read line is demanded forever. The
        # validator says exactly what is wrong — *verified should be a mapping
        # or a list of mappings* — and surfacing it fixes the whole class in one
        # line, where an okf-pro-side re-implementation of the grammar would be a
        # second parser to keep in step with okf's.
        #
        # They warn rather than refuse: §9's separation is the kernel's, and a
        # gate that turned the validator's warnings into errors would be
        # overruling it from outside.
        soft = warn_lines(result.warnings)

        # WHAT THIS GATE RUNS, AND WHY IT SAYS SO.
        #
        # Two of the linter's checks are clock-gated, and a default
        # `Linter.call(bundle)` runs neither. Measured on this gate's own path
        # before this line existed: `skipped_checks: [:expired, :stale]`,
        # `healthy?: true`. The gate reported clean over two checks it never
        # ran, and nothing said so — the contract's third clause broken by the
        # checker itself, in the one place nobody can notice.
        #
        # okf 2.0 confesses it in `stats[:skipped_checks]`, a field added for a
        # reader exactly like this one. The answer is not to relay the
        # confession as a refusal — a skipped check is not a finding, and a gate
        # that blocked every edit until someone supplied a cutoff would be off
        # within a day. It is to leave nothing skipped:
        #
        #   `today:`        the clock `expired` needs. It is `:info`, so this
        #                   adds no refusal — it removes a silence.
        #   `except: stale` a decision, stated. `stale` asks "untouched since
        #                   when?", and this gem has no cutoff policy and no
        #                   business inventing one — that is curation backlog,
        #                   which `okf lint` answers when a person runs it and
        #                   picks a date. An excluded check is excluded here in
        #                   source, which is the opposite of silent.
        #
        # `skipped_checks` is then empty, and `confession` below is a live guard
        # rather than a formality: the day okf adds a third clock-gated check,
        # this gate reports it instead of quietly not running it.
        report = ::OKF::Bundle::Linter.call(target.bundle, today: Date.today, except: [ :stale ])
        notes = confession(report) + soft
        return notes if report.healthy? && notes.empty?

        # Warnings only. Lint's `:info` findings are observations, and a gate
        # that refuses on an observation stops being read as a refusal.
        #
        # And the lint is bundle-WIDE while this gate fires on one edit, so
        # the report says which is which. Everything is still reported —
        # dropping the other files' warnings would hide the edit that
        # breaks a NEIGHBOUR (delete a concept its index still links, and
        # the warning lands on the index, not on the file you touched) —
        # but only the edited file's warnings are called yours. A single
        # pre-existing warning elsewhere used to arrive under the heading
        # "your edit" on every edit in the bundle, and a gate that blames
        # you for what you did not do is a gate people switch off.
        mine, theirs = report.warnings.partition { |w| same_file?(w[:path], target.rel) }
        parts = notes
        parts << "okf lint flagged your edit:\n#{format_warnings(mine)}" unless mine.empty?
        unless theirs.empty?
          parts << "okf lint findings elsewhere in the bundle — pre-existing, or a neighbour " \
                   "your edit affected:\n#{format_warnings(theirs)}"
        end
        [ parts.join("\n") ]
      end

      # What the linter did not run, said out loud. Empty in normal operation
      # (see the call above); non-empty means okf grew a check this gate does
      # not know how to supply, and the right answer then IS to stop — an
      # unchecked bundle reported as clean is the failure this whole file
      # exists to prevent, and a loud unknown beats a quiet one.
      def confession(report)
        skipped = Array(report.stats[:skipped_checks])
        return [] if skipped.empty?

        [ "okf lint could not run #{skipped.join(", ")} on this bundle (no cutoff supplied), " \
          "so those are unchecked rather than clean." ]
      end

      # The validator's soft findings, which are advice rather than a verdict.
      def warn_lines(warnings)
        return [] if warnings.empty?

        [ "okf validate accepted the bundle with #{warnings.size} warning(s) — conformant, but not " \
          "read the way you meant:\n" +
          warnings.map { |w| "  #{w[:path]}: #{w[:message]}" }.join("\n") ]
      end

      def format_warnings(warnings)
        warnings.map { |w| "  #{w[:path]}: #{w[:message]} (#{w[:check]})" }.join("\n")
      end

      # Lint reports a concept id, a bundle-absolute link or a path; the
      # target carries a bundle-relative one. Compared on the stem so the
      # three spellings of the same file agree.
      def same_file?(path, rel)
        stem = ->(s) { s.to_s.downcase.sub(/\A\//, "").sub(/\.md\z/, "") }
        stem.call(path) == stem.call(rel)
      end
    end
  end
end
