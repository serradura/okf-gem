# frozen_string_literal: true

module OKF
  module Pro
    # The attestation surface, listed. This reports and never warns, on
    # purpose: absent `verified:` on a `generated:` concept is the truth, not
    # a defect — a warning that is always present trains its reader to skip
    # it, and the only way to silence it would be to type the one lie the
    # system guards against. The snapshot carries the count as a delta; this
    # carries the names, for an owner deciding what to read next.
    #
    # Corpus-wide, not reference/-scoped like the pairing check: a generated
    # learning or term awaits its read just as much as a briefing does, even
    # though only briefings owe the board a To-read line.
    module Attestation
      module_function

      # The fourth of the four sites §5.3 governs (see Pairing's comment over
      # `awaiting_read?`). It is here rather than in Pairing because it is
      # corpus-wide and Pairing's is briefing-scoped, but the rule is the same
      # one, asked through the same predicate — and this file used to ask it
      # differently, so a `process:`-verified concept dropped off the list an
      # owner reads to decide what to look at next while still owing the read.
      #
      # The tier is printed rather than merely used: "machine-confirmed" and
      # "unverified" are different states, and an owner deciding what to read
      # next is exactly the reader for whom that difference is the point.
      # `concepts:` is the same courtesy Pairing.failures and Snapshot.counters
      # already extend: a caller holding the parse hands it over. `okf pro
      # state --full` asks this, the pairing invariants and the live
      # unverified count in one breath, and without the seam it parsed the
      # bundle twice to answer one flag.
      def report(root, concepts: nil)
        render(rows(root, concepts: concepts))
      end

      # The same list, unrendered, for `--json` and for `okf pro state --full`.
      # Split from the rendering rather than parsed back out of it: a consumer
      # that had to take a sentence apart with a regex would break on the next
      # wording change, and the wording is prose written for a person.
      def rows(root, concepts: nil)
        concepts ||= ::OKF::Bundle::Reader.read(root).concepts
        concepts.map do |concept|
          next unless Pairing.awaiting_read?(concept)

          { "id" => concept.id, "by" => concept.generated_by,
            "at" => concept.generated_at&.to_s,
            "trust" => concept.trust.to_s }
        end.compact
      end

      # One renderer, so `okf pro unverified` and `okf pro state --full` say
      # the same sentence about the same concept.
      def render(rows)
        rows.map do |row|
          "  #{row["id"]}: generated#{" by #{row["by"]}" if row["by"]}#{" on #{row["at"]}" if row["at"]} " \
            "[#{row["trust"]}] — awaiting the owner's read"
        end
      end
    end
  end
end
