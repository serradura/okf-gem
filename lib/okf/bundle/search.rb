# frozen_string_literal: true

require "minifts"

module OKF
  class Bundle
    # Ranked text retrieval over one or more in-memory bundles, backed by a
    # MiniFTS full-text index — the same engine, and the same BM25+ arithmetic,
    # the browser page already runs as MiniSearch. Terms are ANDed: every term
    # must hit at least one searched field, though not necessarily the same one.
    # Rows carry the fields each term hit, so a result stays explainable rather
    # than being a bare relevance number.
    #
    # Matching is by *token*, not substring: a term matches a whole word or a
    # word it prefixes ("dedup" reaches "deduplication"), and `fuzzy: true` opts
    # into typo tolerance. An infix is the one recall a token index gives up —
    # `regexp: true` is the escape hatch, and the one query language an inverted
    # index cannot answer, so it runs as a linear scan over the same fields.
    #
    # Pure — no disk, no stdio. The CLI's `okf search` and any embedding app
    # share it: OKF::Bundle::Search.call(bundle, [ "dedup", "key" ]).
    class Search
      # The searchable fields with their rank weight, strongest signal first.
      # In the index path these ride as MiniFTS per-field `boost`; a regexp scan
      # sums the weights of the fields that matched instead.
      WEIGHTS = {
        "title" => 5,
        "id" => 4,
        "tags" => 3,
        "type" => 2,
        "description" => 2,
        "body" => 1
      }.freeze

      FIELDS = WEIGHTS.keys.freeze

      # Fields whose match is only meaningful with surrounding context. The other
      # fields already appear whole on the result row.
      SNIPPET_FIELDS = %w[description body].freeze

      # Characters of context kept on each side of the first matched term.
      SNIPPET_RADIUS = 44

      # Edit distance as a fraction of term length, under `fuzzy: true` — the
      # same 0.2 the browser page passes, so both forgive the same typos.
      FUZZY_DISTANCE = 0.2

      # The unique document key is "<slug>\0<id>": ids are only unique *within* a
      # bundle, and a merge that collided two bundles' same-named concepts would
      # silently drop one.
      KEY_SEPARATOR = "\0"

      def self.call(bundle, terms, fields: nil, regexp: false, fuzzy: false)
        new([ [ nil, bundle ] ], terms, fields: fields, regexp: regexp, fuzzy: fuzzy).results
      end

      # Several bundles as [ slug, bundle ] pairs, ranked into one list with every
      # row labeled by its slug. They share **one** index on purpose: BM25 weighs a
      # term by how rare it is in the corpus, so per-bundle indexes would score the
      # same match differently depending on which bundle it came from. One index
      # makes one corpus, and the merged ranking is comparable by construction.
      def self.across(bundles, terms, fields: nil, regexp: false, fuzzy: false)
        new(bundles, terms, fields: fields, regexp: regexp, fuzzy: fuzzy).results
      end

      # Raises RegexpError on an invalid pattern with `regexp: true` — the caller
      # owns turning that into a usage error.
      def initialize(bundles, terms, fields: nil, regexp: false, fuzzy: false)
        @bundles = bundles
        @terms = Array(terms).reject { |term| OKF.blank?(term) }.map(&:to_s)
        @fields = fields.nil? || fields.empty? ? FIELDS : fields
        @regexp = regexp
        @fuzzy = fuzzy
        @sources = {}
        @patterns = @terms.map { |term| Regexp.new(term, Regexp::IGNORECASE) } if regexp
      end

      # Ranked match rows, catalog-style identity plus where the terms hit:
      # [{ slug:, id:, title:, type:, area:, tags:, matched: [field, …], score:, snippet: }, …]
      # ordered by score descending, then slug, then id. `slug` is present only
      # when searching across bundles. No terms means no matches.
      def results
        return [] if @terms.empty?

        (@regexp ? scan : lookup).sort_by { |row| [ -row[:score], row[:slug].to_s, row[:id] ] }
      end

      private

      # The index path: one MiniFTS over every searched bundle. `fields:` narrows
      # where a term may hit, so a field the caller excluded can neither match nor
      # be credited.
      def lookup
        index = MiniFTS.new(fields: FIELDS, id_field: "key")
        index.add_all(documents)

        options = { combine_with: "AND", prefix: true, boost: WEIGHTS, fields: @fields }
        options[:fuzzy] = FUZZY_DISTANCE if @fuzzy

        index.search(@terms.join(" "), options).map do |hit|
          slug, concept = @sources[hit[:id]]
          row(slug, concept, matched_in(hit), hit[:score], hit[:terms])
        end
      end

      # Every concept as an indexable document, keyed uniquely across bundles.
      # @sources keeps the way back, so the index stores no fields of its own.
      def documents
        docs = []
        @bundles.each do |slug, bundle|
          bundle.concepts.each do |concept|
            key = "#{slug}#{KEY_SEPARATOR}#{concept.id}"
            @sources[key] = [ slug, concept ]
            docs << field_texts(concept).merge("key" => key)
          end
        end
        docs
      end

      # The union of fields any term hit, in WEIGHTS order. MiniFTS reports it per
      # query term as { term => [field, …] }.
      def matched_in(hit)
        FIELDS.select { |field| hit[:match].any? { |_term, fields| fields.include?(field) } }
      end

      # The regexp path: a linear scan, because a pattern cannot be looked up in a
      # token index. Scores stay absolute field weights, which compare across
      # bundles without an index to normalize them.
      def scan
        rows = []
        @bundles.each do |slug, bundle|
          bundle.concepts.each do |concept|
            texts = field_texts(concept)
            matched = matched_fields(texts)
            next if matched.nil?

            rows << row(slug, concept, matched, matched.map { |field| WEIGHTS[field] }.reduce(0, :+), nil)
          end
        end
        rows
      end

      # The union of fields any pattern hit, in WEIGHTS order — or nil when some
      # pattern hit nothing (terms are ANDed).
      def matched_fields(texts)
        hits = @patterns.map do |pattern|
          fields = @fields.select { |field| pattern.match?(texts[field]) }
          return nil if fields.empty?

          fields
        end
        FIELDS.select { |field| hits.any? { |fields| fields.include?(field) } }
      end

      # { field => original-case text } for every searchable field. The index reads
      # all of them; `fields:` narrows the search, not the document.
      def field_texts(concept)
        {
          "id" => concept.id,
          "title" => concept.title.to_s,
          "type" => concept.type.to_s,
          "description" => concept.description.to_s,
          "tags" => Array(concept.tags).join(" "),
          "body" => concept.body
        }
      end

      # `slug` leads the row so a merged result reads bundle-first, and drops
      # entirely for a single bundle, which has no slug to carry.
      def row(slug, concept, matched, score, terms)
        texts = field_texts(concept)
        built = {
          slug: slug,
          id: concept.id,
          title: (concept.title || concept.id).to_s,
          type: concept.type.to_s,
          area: area_of(concept.id),
          tags: Array(concept.tags).map(&:to_s),
          matched: matched,
          score: score.round(4),
          snippet: snippet(texts, matched, terms)
        }
        built.delete(:slug) if slug.nil?
        built
      end

      # One bounded context window around the first term that hit the strongest
      # snippet-worthy field; "" when the match needs no context (id/title/type/tags).
      def snippet(texts, matched, terms)
        field = SNIPPET_FIELDS.find { |candidate| matched.include?(candidate) }
        return "" if field.nil?

        matcher = snippet_matcher(texts[field], terms)
        matcher.nil? ? "" : context(texts[field], matcher)
      end

      # What to point the window at: the pattern that hit under `regexp`, otherwise
      # the first *document* term MiniFTS matched — already lowercased, and present
      # in the text verbatim even when the query only prefixed it.
      def snippet_matcher(text, terms)
        return @patterns.find { |pattern| pattern.match?(text) } if @regexp

        down = text.downcase
        Array(terms).find { |term| down.include?(term) }
      end

      def context(text, matcher)
        flat = text.gsub(/\s+/, " ").strip
        at, length = locate(flat, matcher)
        from = [ at - SNIPPET_RADIUS, 0 ].max
        to = at + length + SNIPPET_RADIUS
        clip = flat[from, to - from].to_s.strip
        clip = "…#{clip}" if from.positive?
        clip = "#{clip}…" if to < flat.length
        clip
      end

      # [ position, length ] of the matcher's first hit in the flattened text —
      # [ 0, 0 ] when a pattern that hit the raw text cannot be found again after
      # whitespace collapsing (e.g. an explicit \n), so the window opens at the top.
      def locate(flat, matcher)
        if matcher.is_a?(Regexp)
          found = matcher.match(flat)
          found ? [ found.begin(0), found[0].length ] : [ 0, 0 ]
        else
          [ flat.downcase.index(matcher) || 0, matcher.length ]
        end
      end

      # A concept's top-level area, mirroring the catalog's definition.
      def area_of(id)
        id.include?("/") ? id.split("/").first : "(root)"
      end
    end
  end
end
