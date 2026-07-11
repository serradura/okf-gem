# frozen_string_literal: true

module OKF
  # A knowledge bundle held in memory (spec §2), Concept-first: parsed concepts
  # plus the raw text of reserved index/log files and any files whose frontmatter
  # failed to parse. Pure — it performs no disk access.
  #
  # Build one straight from data (the Rails path — no markdown round-trip):
  #
  #   OKF::Bundle.new(concepts: [OKF::Concept.new(...)])
  #
  # or let OKF::Bundle::Reader parse a directory into one. OKF::Bundle::Validator,
  # OKF::Bundle::Linter, and OKF::Bundle::Graph consume it; the convenience methods below forward
  # to them, so `bundle.validate` / `bundle.lint` / `bundle.graph` work on any
  # in-memory bundle.
  #
  # `root` is the bundle path kept purely as data — it seeds bundle-relative link
  # resolution (§5.1) and report messages, never I/O. A bundle built in memory
  # without a real directory gets VIRTUAL_ROOT so relative-link math still works.
  class Bundle
    # Raw text of one markdown file. `error` is set only for unparseable entries
    # (the ParseError message), nil for reserved files.
    class Entry
      attr_reader :path, :content, :error

      def initialize(path:, content:, error: nil)
        @path = path
        @content = content
        @error = error
      end
    end

    # Stand-in absolute root for bundles built in memory (no directory). Only ever
    # the base for pure path arithmetic in Links.resolve; the paths it yields are
    # bundle-relative regardless of its value.
    VIRTUAL_ROOT = "/okf"

    attr_reader :concepts, :reserved, :unparseable, :root

    def initialize(concepts: [], reserved: [], unparseable: [], root: nil)
      @concepts = concepts
      @reserved = reserved
      @unparseable = unparseable
      @root = root || VIRTUAL_ROOT
    end

    # Bundle-relative paths of every markdown file — concepts, reserved, and
    # unparseable — sorted.
    def paths
      (@concepts.map(&:path) + @reserved.map(&:path) + @unparseable.map(&:path)).sort
    end

    def index_files
      reserved_paths("index.md")
    end

    def log_files
      reserved_paths("log.md")
    end

    # Raw content of a reserved file (index.md/log.md) by bundle-relative path, or
    # "" when absent. Reserved structure is validated as text, and index links are
    # extracted from it, so its raw form is retained.
    def reserved_content(path)
      entry = @reserved.find { |candidate| candidate.path == path }
      entry ? entry.content.to_s : ""
    end

    # ── id ↔ path (the single source of "which concept an id names") ──
    # A concept's id may be a frontmatter `id`, so it is not derivable from the path
    # alone. These maps let the shell resolve an id back to its file (the server's
    # per-node lookup) and the graph map a resolved link path to the target's id.

    # The Concept with this id, or nil. Last wins on a (rare) duplicate id.
    def concept_by_id(id)
      concepts_by_id[id]
    end

    # { id => bundle-relative path }.
    def paths_by_id
      @paths_by_id ||= @concepts.map { |concept| [ concept.id, concept.path ] }.to_h
    end

    # ── analysis (pure; forwards to the core analyzers) ──

    def validate
      Validator.call(self)
    end

    def lint(**options)
      Linter.call(self, **options)
    end

    def graph(minimal: false, body: true)
      Graph.build(self, minimal: minimal, body: body)
    end

    # Rich per-concept metadata the catalog / files / stats consumers want but the
    # lean graph omits — the descriptive frontmatter fields plus in/out link degree
    # taken from the graph edges. Pure: derived from the concepts and their links,
    # sorted by id. Shared by the CLI views and the server's /catalog endpoint.
    def catalog
      out_degree = Hash.new(0)
      in_degree = Hash.new(0)
      graph(minimal: true).edges.each do |edge|
        out_degree[edge[:source]] += 1
        in_degree[edge[:target]] += 1
      end

      concepts.map do |concept|
        id = concept.id
        {
          id: id,
          title: (concept.title || id).to_s,
          type: concept.type.to_s,
          description: concept.description.to_s,
          tags: Array(concept.tags).map(&:to_s),
          timestamp: concept.timestamp&.to_s,
          status: concept.frontmatter["status"]&.to_s,
          backlog_ref: concept.frontmatter["backlog_ref"]&.to_s,
          dir: File.dirname("#{id}.md"),
          area: id.include?("/") ? id.split("/").first : "(root)",
          links_out: out_degree[id],
          links_in: in_degree[id]
        }
      end.sort_by { |entry| entry[:id] }
    end

    private

    def concepts_by_id
      @concepts_by_id ||= @concepts.map { |concept| [ concept.id, concept ] }.to_h
    end

    def reserved_paths(basename)
      @reserved.map(&:path).select { |path| File.basename(path) == basename }
    end
  end
end
