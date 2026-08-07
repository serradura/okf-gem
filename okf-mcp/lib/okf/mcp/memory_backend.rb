# frozen_string_literal: true

module OKF
  module MCP
    # The residency cache and the corpus holder — the long-lived holder's branch
    # of the kernel's lifecycle asymmetry. One parsed bundle per registered
    # root, re-read only when the on-disk fingerprint (the markdown file list
    # plus the newest mtime) moves; bodies always come from this layer, live
    # from disk and canonical, whichever engine answers search. There is
    # deliberately no disk cache here — the process is the cache; disk-side
    # state is okf-sqlite3's territory.
    class MemoryBackend
      FILTER_KEYS = %i[type tag dir status].freeze

      # How many prepared corpora to hold at once, most-recently-used first.
      # It used to be unbounded, keyed on the queried subset — a long-lived
      # --http process answering `bundles: ["a","b"]`, then ["a","c"], then
      # ["b","c","d"] retained a full index for each of up to 2^n subsets until
      # the box swapped. Four covers the real pattern ("*" plus a couple of
      # working sets) and bounds the worst case at four indexes.
      MAX_CORPORA = 4

      def initialize
        @mutex = Mutex.new
        @cache = {}
        @corpus_mutex = Mutex.new
        @corpora = {}
      end

      def capabilities
        { name: "memory", ranked: false }
      end

      def refresh(root)
        folder(root)
        nil
      end

      # Engine doctrine, the CLI's exactly: the scan answers by default — no
      # tokenizer recall holes, milliseconds over a resident bundle — and the
      # index (BM25+, page parity) is opt-in by name or implied by fuzzy. The
      # kernel routes and refuses incompatible asks (regexp needs the scan,
      # fuzzy needs the index); those refusals surface as tool errors.
      #
      # Index queries go through a held corpus: one shared index over the whole
      # served set, so federated BM25 scores are comparable by construction
      # (Search.across's own argument). The corpus is built on the first index
      # query, not at boot, and dropped when any member bundle's fingerprint
      # moves — a held index outliving its set is a wrong answer, not a slow one.
      def search_pairs(pairs, terms, fields: nil, regexp: false, fuzzy: false, engine: nil)
        bundles = pairs.map { |slug, root| [ slug, folder(root).bundle ] }
        options = { fields: fields, regexp: regexp, fuzzy: fuzzy, engine: engine }
        if index_query?(engine, fuzzy: fuzzy)
          Bundle::Search.with(corpus_for(pairs), terms, **options)
        else
          Bundle::Search.across(bundles, terms, **options)
        end
      end

      def catalog(root, filters = {})
        folder(root).catalog.select { |row| matches?(row, filters) }
      end

      # Drop every parsed bundle the caller no longer serves. The residency was
      # bounded only by the served set being fixed at boot, and the registry
      # re-read ended that: an operator repointing entries (a checkout per
      # branch, rotating CI worktrees, remove-then-add) left every root the
      # registry had *ever* named keyed here, each holding a parsed bundle with
      # its id maps memoized, until the box swapped and every connected host
      # dropped at once. The sibling corpus cache has been capped since it was
      # written; this one lost its bound without gaining one.
      #
      # An LRU would be the obvious cap and the wrong one: the natural bound is
      # the served set, and a cap below it would thrash — re-parsing on every
      # call for any operator who registered more bundles than the number
      # guessed.
      def retain(roots)
        kept = {}
        roots.each { |root| kept[root] = true }
        @mutex.synchronize { @cache.delete_if { |root, _| !kept.key?(root) } }
        nil
      end

      # One unit of work, for the fingerprint memo below. The freshness check
      # belongs *between* requests: within one, a tool asks the engine for the
      # catalog and then reads the unparseable count off the same folder, and
      # each ask re-walked the whole tree — a glob plus a stat per markdown
      # file, all of it inside the lock.
      def during_request
        previous = Thread.current.thread_variable_get(:okf_mcp_prints)
        Thread.current.thread_variable_set(:okf_mcp_prints, {})
        yield
      ensure
        Thread.current.thread_variable_set(:okf_mcp_prints, previous)
      end

      # The disk handle behind read_concept, index and dirs — those stay on the
      # parsed bundle whichever engine answers search: bodies are read live from
      # disk (canonical), and the directory index needs the authored index.md
      # bodies no derived store carries.
      def folder(root)
        @mutex.synchronize do
          entry = @cache[root]
          print = print_for(root)
          unless entry && entry[:fingerprint] == print
            folder = Bundle::Folder.load(root)
            # The threaded HTTP transport can hit these lazy memos from two
            # threads at once; build them once here, under this lock.
            folder.bundle.concept_by_id(nil)
            folder.bundle.paths_by_id
            entry = { folder: folder, fingerprint: print }
            @cache[root] = entry
          end
          entry[:folder]
        end
      end

      private

      # The fingerprint, computed at most once per root per request. Outside a
      # request (a library caller, a warm-up `refresh`) there is no memo and
      # every call walks, which is the old behaviour and the safe default: a
      # memo that outlived its request would be a stale answer, and staleness is
      # the one thing this layer exists to prevent.
      def print_for(root)
        memo = Thread.current.thread_variable_get(:okf_mcp_prints)
        return fingerprint(root) if memo.nil?

        memo.key?(root) ? memo[root] : (memo[root] = fingerprint(root))
      end

      # Does this query need the prepared index? A named "index" engine, or
      # fuzzy with no engine named (the kernel would route it to the index
      # anyway). "scan" plus fuzzy deliberately skips the corpus so the kernel
      # can refuse it with its own sentence.
      def index_query?(engine, fuzzy:)
        engine.to_s == "index" || (fuzzy && OKF.blank?(engine))
      end

      # One corpus per served set, keyed by its roots and pinned to the exact
      # folder objects it was built from. #folder returns a new object only
      # when a fingerprint moved, so identity comparison is the staleness check.
      #
      # Both the key and the pinned folders are sorted, so `["a","b"]` and
      # `["b","a"]` are the same entry rather than two that evict each other on
      # every alternation. The cache is an LRU bounded at MAX_CORPORA: re-inserting
      # on a hit moves the entry to the end, and the oldest is dropped past the cap.
      def corpus_for(pairs)
        sorted = pairs.sort_by { |slug, root| [ root, slug.to_s ] }
        folders = sorted.map { |slug, root| [ slug, folder(root) ] }
        key = sorted.map { |_, root| root }
        @corpus_mutex.synchronize do
          held = @corpora.delete(key)
          held = nil unless held && held[:folders] == folders
          held ||= { corpus: Bundle::Search.prepare(folders.map { |slug, f| [ slug, f.bundle ] }, engine: "index"), folders: folders }
          @corpora[key] = held
          @corpora.shift while @corpora.size > MAX_CORPORA
          held[:corpus]
        end
      end

      def matches?(row, filters)
        FILTER_KEYS.all? do |key|
          wanted = filters[key]
          next true if OKF.blank?(wanted)

          case key
          when :tag then Array(row[:tags]).map { |tag| Filters.fold(tag) }.include?(Filters.fold(wanted))
          when :dir then Filters.under_dir?(row[:dir], wanted)
          else Filters.fold(row[key]) == Filters.fold(wanted)
          end
        end
      end

      # What the residency cache watches: every markdown file with its mtime
      # **and its size**.
      #
      # The size is what makes a same-second edit visible. mtime alone has
      # 1-second granularity on HFS+, NFS and Docker bind mounts, so a second
      # save inside one tick left the file list and the newest mtime unmoved
      # and the bundle was never re-read — against the server's own promise
      # that results reflect the current files. A same-second edit that also
      # preserves the byte count is still invisible; catching that needs a
      # content hash on every call, which is the whole cost this cache exists
      # to avoid.
      #
      # `stat` is rescued per path because the glob is a moment old by the time
      # it is walked: a `git checkout` or `rm` mid-call would otherwise raise
      # ENOENT and answer the tool with an errno instead of results. A file
      # that vanished simply drops out — which changes the fingerprint, which
      # is exactly the reload the disappearance should trigger.
      def fingerprint(root)
        Dir.glob(::File.join(root, "**", "*.md")).sort.map do |path|
          stat = begin
            ::File.stat(path)
          rescue SystemCallError
            next nil
          end
          [ path, stat.mtime.to_f, stat.size ]
        end.compact
      end
    end
  end
end
