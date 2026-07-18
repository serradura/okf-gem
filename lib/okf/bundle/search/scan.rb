# frozen_string_literal: true

require "okf/bundle/search"

module OKF
  class Bundle
    class Search
      # The linear engine: every term compiled to a case-insensitive Ruby regexp
      # and matched against raw field text, one document at a time. No index, so
      # nothing is tokenized and nothing is normalized — a phrase stays a phrase,
      # `7.2.0` stays one string, and an infix matches. That is the exactness a
      # token index gives up, and the reason this engine survived the swap.
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

          # Raises RegexpError on an invalid pattern — the caller owns turning
          # that into a usage error. The hit's `terms` are the compiled patterns,
          # which is what the facade points its snippet window at.
          def call(documents, terms, fields:, **_options)
            patterns = terms.map { |term| Regexp.new(term, Regexp::IGNORECASE) }

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
