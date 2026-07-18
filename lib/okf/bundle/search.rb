# frozen_string_literal: true

module OKF
  class Bundle
    # Ranked text retrieval over one or more in-memory bundles. Terms are ANDed:
    # every term must hit at least one searched field, though not necessarily the
    # same one. Rows carry the fields each term hit, so a result stays explainable
    # rather than being a bare relevance number.
    #
    # This class is a *facade*. It owns everything that defines what a result is —
    # the documents, the row and its key order, the snippet window, the final sort
    # — and delegates only "which documents match, how well, and where" to an
    # engine (Search::Index by default, Search::Scan for regexp). An engine that
    # built its own rows could disagree about what a match is; this split makes
    # that unrepresentable.
    #
    # Pure — no disk, no stdio. The CLI's `okf search` and any embedding app
    # share it: OKF::Bundle::Search.call(bundle, [ "dedup", "key" ]).
    class Search
      # Raised when the query needs something no available engine offers. The CLI
      # turns it into a usage error (exit 2). Unreachable with only the built-ins
      # — minifts is a hard dependency, so :fuzzy is always answerable — it exists
      # for the addon case, where an engine's backing store can be missing.
      class UnsupportedQuery < OKF::Error
        attr_reader :missing

        def initialize(missing)
          @missing = missing
          super(if missing.empty?
                  "no search engine is available"
                else
                  "no available search engine offers #{missing.map { |name| ":#{name}" }.join(", ")}"
                end)
        end
      end

      # The declarable capability vocabulary. Frozen so an engine that declares
      # `:regex` is refused at registration rather than silently never selected —
      # a typo in an addon would otherwise present as "my engine is ignored".
      CAPABILITIES = %i[regexp fuzzy prefix].freeze

      # Chosen when the query requires nothing in particular, which is the
      # overwhelming majority of searches.
      DEFAULT_ENGINE = :index

      # The searchable fields with their rank weight, strongest signal first.
      # In the index engine these ride as MiniFTS per-field `boost`; the scan
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

      # Append-only and idempotent by id: a second registration of an id already
      # present is a no-op, so a double `require` cannot double the registry and
      # an addon cannot quietly displace a built-in. Deliberately the same shape
      # as the Linter's planned register hook — two extension points, one idiom.
      def self.register(engine)
        rogue = engine.capabilities - CAPABILITIES
        raise ArgumentError, "unknown search capability: #{rogue.join(", ")}" unless rogue.empty?

        @engines ||= []
        @engines << engine unless @engines.any? { |registered| registered.id == engine.id }
        engine
      end

      # A frozen snapshot in registration order. Frozen because the registry is
      # only meant to grow through .register, where the vocabulary is checked.
      def self.engines
        (@engines ||= []).dup.freeze
      end

      # The router. The default engine leads, then registration order; the first
      # available engine offering *every* required capability answers. Partition
      # rather than sort_by, because sort_by is not stable and registration order
      # is the tie-break.
      def self.engine_for(required, engines: self.engines)
        default, rest = engines.select(&:available?).partition { |engine| engine.id == DEFAULT_ENGINE }
        found = (default + rest).find { |engine| (required - engine.capabilities).empty? }
        return found if found

        raise UnsupportedQuery, required
      end

      def self.call(bundle, terms, fields: nil, regexp: false, fuzzy: false, engines: nil)
        new([ [ nil, bundle ] ], terms, fields: fields, regexp: regexp, fuzzy: fuzzy, engines: engines).results
      end

      # Several bundles as [ slug, bundle ] pairs, ranked into one list with every
      # row labeled by its slug. They share **one** index on purpose: BM25 weighs a
      # term by how rare it is in the corpus, so per-bundle indexes would score the
      # same match differently depending on which bundle it came from. One index
      # makes one corpus, and the merged ranking is comparable by construction.
      def self.across(bundles, terms, fields: nil, regexp: false, fuzzy: false, engines: nil)
        new(bundles, terms, fields: fields, regexp: regexp, fuzzy: fuzzy, engines: engines).results
      end

      # Raises RegexpError on an invalid pattern with `regexp: true`, and
      # UnsupportedQuery when no engine can answer — the caller owns turning
      # either into a usage error. `engines:` overrides the registry, which is how
      # the "nothing qualifies" path stays reachable without an addon installed.
      def initialize(bundles, terms, fields: nil, regexp: false, fuzzy: false, engines: nil)
        @bundles = bundles
        @terms = Array(terms).reject { |term| OKF.blank?(term) }.map(&:to_s)
        @fields = fields.nil? || fields.empty? ? FIELDS : fields
        @regexp = regexp
        @fuzzy = fuzzy
        @engines = engines
        @sources = {}
      end

      # Ranked match rows, catalog-style identity plus where the terms hit:
      # [{ slug:, id:, title:, type:, area:, tags:, matched: [field, …], score:, snippet: }, …]
      # ordered by score descending, then slug, then id. `slug` is present only
      # when searching across bundles. No terms means no matches.
      def results
        return [] if @terms.empty?

        rows = engine.call(documents, @terms, fields: @fields, fuzzy: @fuzzy).map do |hit|
          slug, concept = @sources[hit[:key]]
          row(slug, concept, hit[:matched], hit[:score], hit[:terms])
        end
        rows.sort_by { |row| [ -row[:score], row[:slug].to_s, row[:id] ] }
      end

      private

      # The engine is chosen by what the query needs, not by a flag naming one.
      # `-e` unambiguously means "regexp semantics", so it routes on its own and
      # says nothing about it — there is no --engine flag to reconcile with.
      def engine
        Search.engine_for(required_capabilities, engines: @engines || Search.engines)
      end

      # Options translated into the capability vocabulary. `:prefix` is never
      # required: the index offers it and nothing asks for its absence.
      def required_capabilities
        required = []
        required << :regexp if @regexp
        required << :fuzzy if @fuzzy
        required
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

      # What to point the window at: the first of the engine's reported matchers
      # that this text actually contains. Engine-agnostic on purpose — the scan
      # reports compiled patterns, the index reports lowercased document terms,
      # and both are things `locate` can find again in the flattened text.
      def snippet_matcher(text, terms)
        down = text.downcase
        Array(terms).find do |term|
          term.is_a?(Regexp) ? term.match?(text) : down.include?(term)
        end
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
