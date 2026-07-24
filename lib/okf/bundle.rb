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

    def skeleton
      Skeleton.build(self)
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
          title: OKF.blank?(concept.title) ? File.basename(id) : concept.title.to_s,
          type: concept.type.to_s,
          description: concept.description.to_s,
          tags: Array(concept.tags).map(&:to_s),
          timestamp: concept.timestamp&.to_s,
          status: concept.frontmatter["status"]&.to_s,
          backlog_ref: concept.frontmatter["backlog_ref"]&.to_s,
          dir: OKF.dir_of(id),
          area: area_of(id),
          links_out: out_degree[id],
          links_in: in_degree[id]
        }
      end.sort_by { |entry| entry[:id] }
    end

    # Concepts ranked by inbound link degree, each with the areas its inbound
    # links come from — the evidence for "is this hub well-homed?": a hub whose
    # inbound majority is foreign to its own area is a move candidate, one with
    # a single dominant foreign area already names its better home. Only
    # concepts with at least one inbound link appear. Pure: derived from the
    # graph edges. Shared by the `okf graph --hubs` view.
    def hubs
      inbound = {}
      graph(minimal: true).edges.each do |edge|
        (inbound[edge[:target]] ||= Hash.new(0))[area_of(edge[:source])] += 1
      end

      inbound.map do |id, sources|
        by_area = sources.sort_by { |area, count| [ -count, area ] }.to_h
        { id: id, area: area_of(id), inbound: by_area.values.reduce(0, :+), by_area: by_area }
      end.sort_by { |row| [ -row[:inbound], row[:id] ] }
    end

    # The progressive-disclosure map (spec §6): one entry per directory that holds
    # concepts or carries an index.md, sorted with the root (".") first. Each entry
    # gives the authored index body (frontmatter stripped) when an index.md is
    # present, a type/tag rollup over the concepts that live *directly* in the
    # directory, its immediate child directories, and the concept listing an
    # index.md there would enumerate. A directory with concepts but no index.md has
    # `present: false` and still carries the listing, so a consumer can synthesize
    # the map on the fly (§6 permits exactly that). Grouped by the concept's file
    # path — index files are physical directory listings, so a custom frontmatter
    # `id` must not move a concept out of the directory it lives in. Pure: derived
    # from the concepts and the reserved index text, no disk. Shared by the
    # `okf index` view and the server's Index panel (/index).
    def directory_index
      by_dir = concepts.group_by { |concept| File.dirname(concept.path) }
      dirs = directory_set(by_dir.keys)

      dirs.map do |dir|
        here = (by_dir[dir] || []).sort_by(&:id)
        index_path = dir == "." ? "index.md" : "#{dir}/index.md"
        present = index_files.include?(index_path)
        {
          dir: dir,
          index_path: index_path,
          present: present,
          synthesized: !present,
          body: present ? strip_frontmatter(reserved_content(index_path)) : nil,
          count: here.size,
          types: tally(here.map { |concept| concept.type.to_s }),
          tags: tally(here.flat_map { |concept| Array(concept.tags).map(&:to_s) }),
          subdirs: dirs.select { |other| other != dir && File.dirname(other) == dir },
          listing: here.map do |concept|
            {
              id: concept.id,
              title: OKF.blank?(concept.title) ? File.basename(concept.id) : concept.title.to_s,
              description: concept.description.to_s,
              type: concept.type.to_s,
              tags: Array(concept.tags).map(&:to_s)
            }
          end
        }
      end
    end

    private

    # A concept's top-level area, derived from its id — the same derivation the
    # catalog exposes, so every grouped view labels the bundle root "(root)".
    def area_of(id)
      id.include?("/") ? id.split("/").first : "(root)"
    end

    # Every directory to show: those holding concepts or an index.md, plus each of
    # their ancestors up to the root, so the subdir tree stays connected even when
    # an intermediate directory holds nothing directly. Sorted with "." first.
    def directory_set(concept_dirs)
      seed = concept_dirs + index_files.map { |path| File.dirname(path) }
      dirs = {}
      seed.each do |dir|
        current = dir
        loop do
          dirs[current] = true
          break if current == "."

          current = File.dirname(current)
        end
      end
      dirs.keys.sort_by { |dir| dir == "." ? "" : dir }
    end

    # { value => count }, ordered by count descending then value.
    def tally(values)
      counts = values.each_with_object(Hash.new(0)) { |value, acc| acc[value] += 1 }
      counts.sort_by { |value, count| [ -count, value ] }.to_h
    end

    # The index body with a leading frontmatter block removed (the bundle-root
    # index carries okf_version; nested indexes carry none). Returns the content
    # unchanged when it has no parseable frontmatter — the common case for a nested
    # index — rather than raising.
    def strip_frontmatter(content)
      Markdown::Frontmatter.parse(content).last
    rescue Markdown::Frontmatter::ParseError
      content
    end

    def concepts_by_id
      @concepts_by_id ||= @concepts.map { |concept| [ concept.id, concept ] }.to_h
    end

    def reserved_paths(basename)
      @reserved.map(&:path).select { |path| File.basename(path) == basename }
    end
  end
end
