# frozen_string_literal: true

require "okf/bundle/search"

module OKF
  class Bundle
    class Search
      # The linear engine: terms matched against raw field text, one document at a
      # time. No index, so nothing is tokenized and nothing is normalized — a
      # phrase stays a phrase, `7.2.0` stays one string, and an infix matches.
      # That is the exactness a token index gives up, and the reason this engine
      # survived the swap.
      #
      # Two readings of a term, and the engine is the *raw text* half of the split
      # rather than the regexp half:
      #
      #   `regexp: false` — literal substring, which is what this engine did
      #                     before the index landed, and what `--engine scan`
      #                     restores. Terms are escaped, so `7.2.0` does not
      #                     match `7x2y0` and `[draft]` is not a character class.
      #   `regexp: true`  — the term is a pattern, opted into with `-e`.
      #
      # Conflating the two would make choosing the engine silently change what the
      # terms mean, and turn an ordinary term like `review (pending` into exit 2.
      #
      # Scoring is the summed weight of the fields that matched: absolute, and so
      # comparable across bundles without a corpus to normalize against.
      module Scan
        CAPABILITIES = %i[regexp].freeze

        class << self
          def id
            :scan
          end

          def capabilities
            CAPABILITIES
          end

          # No backing store to fail: the engine is Regexp and Enumerable.
          def available?
            true
          end

          # Raises RegexpError on an invalid pattern under `regexp: true` — the
          # caller owns turning that into a usage error. A literal term cannot
          # raise, because it is escaped before it is compiled. The hit's `terms`
          # are the compiled patterns, which is what the facade points its snippet
          # window at.
          def call(documents, terms, fields:, regexp: false, **_options)
            patterns = terms.map do |term|
              Regexp.new(regexp ? term : Regexp.escape(term), Regexp::IGNORECASE)
            end

            hits = []
            documents.each do |document|
              matched = matched_fields(document, patterns, fields)
              next if matched.nil?

              hits << {
                key: document["key"],
                matched: matched,
                score: matched.map { |field| WEIGHTS[field] }.reduce(0, :+),
                terms: patterns
              }
            end
            hits
          end

          private

          # The union of fields any pattern hit, in WEIGHTS order — or nil when
          # some pattern hit nothing (terms are ANDed).
          def matched_fields(document, patterns, fields)
            hits = patterns.map do |pattern|
              found = fields.select { |field| pattern.match?(document[field]) }
              return nil if found.empty?

              found
            end
            FIELDS.select { |field| hits.any? { |found| found.include?(field) } }
          end
        end

        Search.register(self)
      end
    end
  end
end
