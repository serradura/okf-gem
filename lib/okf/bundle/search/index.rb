# frozen_string_literal: true

require "minifts"
require "okf/bundle/search"

module OKF
  class Bundle
    class Search
      # The default engine: a MiniFTS full-text index — the same engine, and the
      # same BM25+ arithmetic, the browser page already runs as MiniSearch, so a
      # Ruby-built index and the page's rank identically.
      #
      # Matching is by *token*: a term matches a whole word or a word it prefixes
      # ("dedup" reaches "deduplication"), and `fuzzy:` opts into typo tolerance.
      # The index is built per call — see .okf/capabilities/search.md for why that
      # ceiling stands and what lifts it.
      module Index
        CAPABILITIES = %i[fuzzy prefix].freeze

        class << self
          def id
            :index
          end

          def capabilities
            CAPABILITIES
          end

          # minifts is a hard runtime dependency with no native extension, so it
          # is here whenever the gem is. An addon backed by a native build is the
          # case this predicate exists for.
          def available?
            true
          end

          # `fields:` narrows where a term may hit, so a field the caller excluded
          # can neither match nor be credited. The hit's `terms` are MiniFTS's
          # matched *document* terms — already lowercased, and present in the text
          # verbatim even when the query only prefixed them.
          def call(documents, terms, fields:, fuzzy: false, **_options)
            index = MiniFTS.new(fields: FIELDS, id_field: "key")
            index.add_all(documents)

            options = { combine_with: "AND", prefix: true, boost: WEIGHTS, fields: fields }
            options[:fuzzy] = FUZZY_DISTANCE if fuzzy

            index.search(terms.join(" "), options).map do |hit|
              { key: hit[:id], matched: matched_in(hit), score: hit[:score], terms: hit[:terms] }
            end
          end

          private

          # The union of fields any term hit, in WEIGHTS order. MiniFTS reports it
          # per query term as { term => [field, …] }.
          def matched_in(hit)
            FIELDS.select { |field| hit[:match].any? { |_term, found| found.include?(field) } }
          end
        end

        Search.register(self)
      end
    end
  end
end
