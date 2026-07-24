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
      # Raised when the query needs something the engine cannot do — either the
      # one that was named, or any that is available. Carries structured data
      # rather than a finished sentence, because the shell says "--regexp" where
      # the core says ":regexp"; the CLI formats it and exits 2.
      class UnsupportedQuery < OKF::Error
        attr_reader :missing, :engine

        def initialize(missing, engine: nil)
          @missing = missing
          @engine = engine
          super(build_message(missing, engine))
        end

        private

        def build_message(missing, engine)
          return "no search engine is available" if missing.empty?

          offered = missing.map { |name| ":#{name}" }.join(", ")
          engine.nil? ? "no available search engine offers #{offered}" : "engine #{engine} does not offer #{offered}"
        end
      end

      # Raised when `--engine` names something that is not on offer. An engine
      # registered but reporting `available? == false` is absent from the list for
      # the same reason it is absent from routing: it cannot answer. A future
      # addon whose native build failed will want a kinder message than this one.
      class UnknownEngine < OKF::Error
        attr_reader :name, :available

        def initialize(name, available)
          @name = name
          @available = available
          super("unknown search engine: #{name} (available: #{available.join(", ")})")
        end
      end

      # The **declarable** vocabulary: what an engine may claim about itself.
      # Frozen so an engine declaring `:regex` is refused at registration rather
      # than silently never selected — a typo in an addon would otherwise present
      # as "my engine is ignored".
      #
      # `:prefix` lives here and *not* in ROUTABLE on purpose. Nothing asks for
      # its absence, so it selects nothing; what it does is document that this
      # engine grows a term to the tokens it prefixes, which an FTS5 engine may
      # not do by default. Declarative, and honest about being declarative.
      CAPABILITIES = %i[regexp fuzzy prefix].freeze

      # The **routable** subset: the capabilities a query can actually require,
      # and therefore the only ones that pick an engine. Kept distinct from
      # CAPABILITIES because a capability nothing selects on, filed among the ones
      # that do, is documentation posing as code.
      #
      # Each entry is also the option name the facade hands an engine that
      # declares it — see #engine_options, which is what keeps a meaningful
      # option from reaching an engine that would quietly drop it.
      ROUTABLE = %i[regexp fuzzy].freeze

      # Chosen when the query requires nothing in particular, which is the
      # overwhelming majority of searches.
      #
      # The scan, not the index, because a one-shot CLI builds an index, asks one
      # question and exits — a build with a single query to amortize it over.
      # Measured end to end: 3.00s vs 0.24s at 1,000 concepts, 0.83s vs 0.18s at
      # 250, and the gap widens with the bundle. Raw-text matching also carries no
      # tokenizer, so the terms that are glued to symbols and therefore
      # unreachable by token (`minifts`, $OKF_HOME) stay findable by default.
      #
      # What it gives up is BM25+ ranking, reachable with `--engine index` — and
      # that is also the engine the browser page runs, so the two rank alike only
      # when the index is named. See .okf/design/search-engines.md.
      DEFAULT_ENGINE = :scan

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

      # The router. Naming an engine is an override, not a hint: it is how a
      # caller reaches semantics no capability flag asks for — `--engine scan`
      # means "match raw text", which the flags cannot express because there is
      # nothing to *require*. A named engine that cannot do what was also asked
      # is an error rather than a silent fallback, since falling back would answer
      # a different question than the one that was posed.
      #
      # Unnamed, the default engine leads, then registration order; the first
      # available engine offering *every* required capability answers. Partition
      # rather than sort_by, because sort_by is not stable and registration order
      # is the tie-break.
      def self.engine_for(required, engines: self.engines, name: nil)
        available = engines.select(&:available?)
        return named_engine(name, required, available) unless OKF.blank?(name)

        default, rest = available.partition { |engine| engine.id == DEFAULT_ENGINE }
        found = (default + rest).find { |engine| (required - engine.capabilities).empty? }
        return found if found

        raise UnsupportedQuery, required
      end

      def self.named_engine(name, required, available)
        wanted = name.to_s.downcase
        found = available.find { |engine| engine.id.to_s == wanted }
        raise UnknownEngine.new(name, available.map(&:id)) if found.nil?

        missing = required - found.capabilities
        raise UnsupportedQuery.new(missing, engine: found.id) unless missing.empty?

        found
      end
      private_class_method :named_engine

      def self.call(bundle, terms, fields: nil, regexp: false, fuzzy: false, engine: nil, engines: nil)
        new([ [ nil, bundle ] ], terms, fields: fields, regexp: regexp, fuzzy: fuzzy, engine: engine, engines: engines).results
      end

      # Several bundles as [ slug, bundle ] pairs, ranked into one list with every
      # row labeled by its slug. They share **one** index on purpose: BM25 weighs a
      # term by how rare it is in the corpus, so per-bundle indexes would score the
      # same match differently depending on which bundle it came from. One index
      # makes one corpus, and the merged ranking is comparable by construction.
      def self.across(bundles, terms, fields: nil, regexp: false, fuzzy: false, engine: nil, engines: nil)
        new(bundles, terms, fields: fields, regexp: regexp, fuzzy: fuzzy, engine: engine, engines: engines).results
      end

      # The searchable text of one concept, by field. Here rather than on an
      # instance because a Corpus builds documents with no query in hand.
      def self.field_texts(concept)
        {
          "id" => concept.id,
          "title" => concept.title.to_s,
          "type" => concept.type.to_s,
          "description" => concept.description.to_s,
          "tags" => Array(concept.tags).join(" "),
          "body" => concept.body
        }
      end

      # A corpus prepared once and queried many times: the documents, the key →
      # concept map, and each engine's built index.
      #
      # This is the asymmetry the engine choice was always argued from. A CLI
      # process loads a bundle, asks one question and exits, so an index build has
      # exactly one query to amortize over and the scan wins. A server is the
      # other case — the build is ~95% of the index path's cost, and paying it per
      # request made every search re-read the whole corpus. Held once, it is paid
      # once.
      #
      # Pure: it holds concepts, never disk. Which is also the cost — the corpus
      # is a snapshot, so a body edited after it was built is searchable only
      # after the holder drops it. That matches the graph, which is memoized the
      # same way and for the same reason.
      class Corpus
        attr_reader :bundles, :documents, :sources

        def initialize(bundles)
          @bundles = bundles
          @documents = []
          @sources = {}
          @indexes = {}
          bundles.each do |slug, bundle|
            bundle.concepts.each do |concept|
              key = "#{slug}#{KEY_SEPARATOR}#{concept.id}"
              @sources[key] = [ slug, concept ]
              @documents << Search.field_texts(concept).merge("key" => key)
            end
          end
        end

        # nil for an engine with nothing to prebuild — the scan reads raw text and
        # has no index to hold — so the option only ever reaches one that declared
        # it can. Memoized per engine id: two engines over one corpus is legal.
        def index_for(engine)
          return nil unless engine.respond_to?(:prepare)

          @indexes[engine.id] ||= engine.prepare(@documents)
        end
      end

      # Prepare a corpus for a long-lived caller. Hand the result back to .with
      # for every query.
      #
      # `engine:` builds that engine's index *now* rather than on the first query.
      # Without it the corpus holds only the documents, and the expensive half —
      # the index — is still built lazily, which puts the whole cost on whoever
      # searches first. A server knows its engine at boot, so it can pay there.
      def self.prepare(bundles, engine: nil, engines: nil)
        corpus = Corpus.new(bundles)
        return corpus if OKF.blank?(engine)

        corpus.index_for(engine_for([], engines: engines || self.engines, name: engine))
        corpus
      end

      # Query a prepared corpus. Same rows as .across, without rebuilding what the
      # corpus already holds.
      def self.with(corpus, terms, fields: nil, regexp: false, fuzzy: false, engine: nil, engines: nil)
        new(corpus.bundles, terms, fields: fields, regexp: regexp, fuzzy: fuzzy,
          engine: engine, engines: engines, corpus: corpus).results
      end

      # Raises RegexpError on an invalid pattern with `regexp: true`, and
      # UnsupportedQuery when no engine can answer — the caller owns turning
      # either into a usage error. `engines:` overrides the registry, which is how
      # the "nothing qualifies" path stays reachable without an addon installed.
      def initialize(bundles, terms, fields: nil, regexp: false, fuzzy: false, engine: nil, engines: nil, corpus: nil)
        @bundles = bundles
        @corpus = corpus
        @terms = Array(terms).reject { |term| OKF.blank?(term) }.map(&:to_s)
        @fields = fields.nil? || fields.empty? ? FIELDS : fields
        @regexp = regexp
        @fuzzy = fuzzy
        @engine = engine
        @engines = engines
        @sources = {}
      end

      # Ranked match rows, catalog-style identity plus where the terms hit:
      # [{ slug:, id:, title:, type:, dir:, top_dir:, tags:, matched: [field, …], score:, snippet: }, …]
      # ordered by score descending, then slug, then id. `slug` is present only
      # when searching across bundles. No terms means no matches.
      def results
        return [] if @terms.empty?

        chosen = engine
        rows = chosen.call(documents, @terms, **engine_options(chosen)).map do |hit|
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
        Search.engine_for(required_capabilities, engines: @engines || Search.engines, name: @engine)
      end

      # What the query requires, in the routable vocabulary. `:prefix` never
      # appears: it is declarable, not routable — nothing asks for its absence.
      def required_capabilities
        ROUTABLE.select { |capability| requested[capability] }
      end

      # `fields:` always, plus exactly the routable options the chosen engine
      # declared it understands.
      #
      # The facade used to hand every engine every option and trust it to ignore
      # what it could not use. Routing makes that harmless in practice — a fuzzy
      # query only ever reaches a :fuzzy engine — but "harmless because something
      # else prevents it" is precisely how an option comes to be dropped in
      # silence the day that something else changes. An engine now receives only
      # what it can act on, so there is nothing left for it to ignore.
      def engine_options(chosen)
        options = { fields: @fields }
        options[:prepared] = @corpus.index_for(chosen) if @corpus
        ROUTABLE.each do |capability|
          options[capability] = requested[capability] if chosen.capabilities.include?(capability)
        end
        options
      end

      def requested
        @requested ||= { regexp: @regexp, fuzzy: @fuzzy }
      end

      # Every concept as an indexable document, keyed uniquely across bundles.
      # @sources keeps the way back, so the index stores no fields of its own.
      def documents
        # The corpus already walked every concept and kept the map that turns a
        # hit back into a row; taking its sources is what makes that reuse whole.
        if @corpus
          @sources = @corpus.sources
          return @corpus.documents
        end

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
        Search.field_texts(concept)
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
          dir: OKF.dir_of(concept.id),
          top_dir: top_dir_of(concept.id),
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

      # A concept's top-level dir, mirroring the catalog's definition — the first
      # path segment. OKF.dir_of keeps the levels this one rolls up.
      def top_dir_of(id)
        id.include?("/") ? id.split("/").first : "(root)"
      end
    end
  end
end
