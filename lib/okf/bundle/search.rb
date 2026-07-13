# frozen_string_literal: true

module OKF
  class Bundle
    # Deterministic text retrieval over an in-memory bundle — the browser page's
    # search brought server-side and extended to bodies. Terms are ANDed: every
    # term must hit at least one searched field, though not necessarily the same
    # one. A term is a case-insensitive substring, or a Ruby regular expression
    # with `regexp: true`. Matches rank by where they hit (a title hit outranks a
    # body hit) and carry one bounded context snippet, so answering "which concept
    # covers X?" costs a row, not a body read.
    #
    # Deliberately not fuzzy: the consuming agent is the fuzzy layer — synonyms
    # and vocabulary drift are judgment over the index map, not string distance.
    #
    # Pure — no disk, no stdio. The CLI's `okf search` and any embedding app share
    # it: OKF::Bundle::Search.call(bundle, [ "dedup", "key" ]).
    class Search
      # The searchable fields with their rank weight, strongest signal first.
      # A concept's score sums the weights of the fields that matched; hitting a
      # field twice does not stack. Tags match against the space-joined list,
      # mirroring the server page's haystack.
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

      def self.call(bundle, terms, fields: nil, regexp: false)
        new(bundle, terms, fields: fields, regexp: regexp).results
      end

      # Raises RegexpError on an invalid pattern with `regexp: true` — the caller
      # owns turning that into a usage error.
      def initialize(bundle, terms, fields: nil, regexp: false)
        @bundle = bundle
        raw = Array(terms).reject { |term| OKF.blank?(term) }
        @matchers = raw.map { |term| regexp ? Regexp.new(term.to_s, Regexp::IGNORECASE) : term.to_s.downcase }
        @fields = fields.nil? || fields.empty? ? FIELDS : fields
      end

      # Ranked match rows, catalog-style identity plus where the terms hit:
      # [{ id:, title:, type:, area:, tags:, matched: [field, …], score:, snippet: }, …]
      # ordered by score descending, then id. No terms means no matches.
      def results
        return [] if @matchers.empty?

        @bundle.concepts
               .map { |concept| match(concept) }
               .compact
               .sort_by { |row| [ -row[:score], row[:id] ] }
      end

      private

      def match(concept)
        texts = searchable_texts(concept)
        matched = matched_fields(texts)
        return nil if matched.nil?

        {
          id: concept.id,
          title: (concept.title || concept.id).to_s,
          type: concept.type.to_s,
          area: area_of(concept.id),
          tags: Array(concept.tags).map(&:to_s),
          matched: matched,
          score: matched.map { |field| WEIGHTS[field] }.reduce(0, :+),
          snippet: snippet(texts, matched)
        }
      end

      # { field => original-case text } for the fields this search reads.
      def searchable_texts(concept)
        texts = {
          "id" => concept.id,
          "title" => concept.title.to_s,
          "type" => concept.type.to_s,
          "description" => concept.description.to_s,
          "tags" => Array(concept.tags).join(" "),
          "body" => concept.body
        }
        texts.each_with_object({}) do |(field, text), acc|
          acc[field] = text if @fields.include?(field)
        end
      end

      # The union of fields any term hit, in WEIGHTS order — or nil when some term
      # hit nothing (terms are ANDed).
      def matched_fields(texts)
        hits = @matchers.map do |matcher|
          fields = texts.keys.select { |field| hit?(matcher, texts[field]) }
          return nil if fields.empty?

          fields
        end
        FIELDS.select { |field| hits.flatten.include?(field) }
      end

      def hit?(matcher, text)
        matcher.is_a?(Regexp) ? matcher.match?(text) : text.downcase.include?(matcher)
      end

      # One bounded context window around the first term that hit the strongest
      # snippet-worthy field; "" when the match needs no context (id/title/type/tags).
      def snippet(texts, matched)
        field = SNIPPET_FIELDS.find { |candidate| matched.include?(candidate) }
        return "" if field.nil?

        matcher = @matchers.find { |candidate| hit?(candidate, texts[field]) }
        context(texts[field], matcher)
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
