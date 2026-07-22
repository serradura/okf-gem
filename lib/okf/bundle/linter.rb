# frozen_string_literal: true

module OKF
  class Bundle
    # Lints a bundle for curation quality — the deterministic subset of the
    # ingest → query → lint loop (overview.md): reachability, backlog, completeness,
    # freshness, provenance, and hygiene. Pure — it reads nothing from disk and works
    # entirely on the in-memory OKF::Bundle, mirroring OKF::Bundle::Validator.
    #
    # Unlike OKF::Bundle::Validator (the §9 conformance gate, which MUST NOT reject for broken
    # links or missing optional fields), lint never rejects a bundle: it reports
    # `:warn` and `:info` findings the spec marks as tolerable, and emits them as
    # structured data (OKF::Bundle::Linter::Report) for a human or agent to act on. Contradictions
    # and semantic staleness are NOT detected here — they need meaning, not structure;
    # the JSON report is the substrate an agent consumes for those passes.
    class Linter
      # All checks, in display/registry order. `--only`/`--except` select from these.
      CHECKS = %i[
        orphan not_in_index disconnected_component unlinked
        missing_concept broken_index_entry
        stub missing_title missing_description missing_timestamp
        stale
        uncited_external broken_citation
        duplicate_title unused_reference_def undefined_reference self_link
      ].freeze

      DEFAULT_MIN_BODY = 50
      HUB_LIMIT = 5

      def self.call(bundle, **options)
        new(bundle, **options).call
      end

      def initialize(bundle, min_body: DEFAULT_MIN_BODY, stale_before: nil, only: nil, except: nil)
        @bundle = bundle
        @min_body = min_body
        @stale_before = stale_before
        @only = only
        @except = except
        @report = Report.new
      end

      def call
        prepare
        selected_checks.each { |check| send("check_#{check}") }
        fill_stats
        @report
      end

      private

      # Shared derived data, computed once and reused by every check.
      def prepare
        @concepts = @bundle.concepts
        @graph = Graph.build(@bundle)
        @ids = @concepts.to_set(&:id)
        @existing = @bundle.paths.to_set
        @inbound = Hash.new(0)
        @graph.edges.each { |edge| @inbound[edge[:target]] += 1 }
        @indexed_ids = indexed_by_dir.values.reduce(Set.new, :|)
      end

      def selected_checks
        checks = CHECKS
        checks &= Array(@only).map(&:to_sym) if @only
        checks -= Array(@except).map(&:to_sym) if @except
        checks
      end

      # ── Reachability ─────────────────────────────────────────────────────────

      def check_orphan
        @concepts.each do |concept|
          next if @inbound[concept.id].positive? || @indexed_ids.include?(concept.id)

          @report.add_warning(:orphan, "#{concept.id}.md",
            "unreachable: no inbound links and not listed in any index.md")
        end
      end

      def check_not_in_index
        indexed_by_dir.each do |dir, listed|
          concepts_in(dir).each do |concept|
            next if listed.include?(concept.id)

            @report.add_warning(:not_in_index, "#{concept.id}.md",
              "not listed in its directory index (#{index_path_for(dir)})",
              metric: { index: index_path_for(dir) })
          end
        end
      end

      # Reports genuine multi-concept islands only. A size-1 component is either an
      # orphan (already flagged by check_orphan) or a lone indexed leaf, so reporting
      # every unlinked node here would just be noise.
      def check_disconnected_component
        groups = components
        return if groups.size <= 1

        main = groups.max_by(&:size)
        groups.each do |members|
          next if members.equal?(main) || members.size < 2

          @report.add_info(:disconnected_component, nil,
            "#{members.size} concepts form an island disconnected from the main graph",
            metric: { size: members.size, members: members.sort })
        end
      end

      # A concept with graph degree 0 — no cross-links in or out — floats in a
      # rendered graph, reachable only via its index listing (if any). Advisory
      # (info): a legitimately terminal leaf (a backlog item, a spec reference) is
      # fine; this just surfaces the set so a human/agent can judge intent. Unlike
      # :orphan, an index.md listing does NOT silence it — being *listed* is not
      # being *linked*, and it is the missing links this catches.
      def check_unlinked
        loose = @graph.unlinked_ids.to_set
        @concepts.each do |concept|
          next unless loose.include?(concept.id)

          @report.add_info(:unlinked, "#{concept.id}.md",
            "no cross-links (in or out); it floats in the graph")
        end
      end

      # ── Backlog ──────────────────────────────────────────────────────────────

      # NOTE: this must NOT reuse @graph.edges — the graph drops targets that do not
      # exist and dedups pairs, which would erase exactly this backlog. Count raw
      # link occurrences from Markdown::Links.extract instead.
      def check_missing_concept
        demand = Hash.new { |hash, key| hash[key] = { references: 0, sources: [] } }
        @concepts.each do |concept|
          Markdown::Links.extract(concept.body).each do |raw|
            target = Markdown::Links.resolve(raw, from: concept.path, bundle: @bundle.root)
            next if target.nil? || @existing.include?(target)

            entry = demand[target]
            entry[:references] += 1
            entry[:sources] << concept.id unless entry[:sources].include?(concept.id)
          end
        end

        demand.sort_by { |target, entry| [ -entry[:references], target ] }.each do |target, entry|
          @report.add_info(:missing_concept, target,
            "referenced by #{entry[:references]} link(s) across #{entry[:sources].size} concept(s) but does not exist",
            metric: { references: entry[:references], sources: entry[:sources] })
        end
      end

      def check_broken_index_entry
        @bundle.index_files.each do |path|
          Markdown::Links.extract(content_of(path)).each do |raw|
            target = Markdown::Links.resolve(raw, from: path, bundle: @bundle.root)
            next if target.nil? || @existing.include?(target)

            @report.add_warning(:broken_index_entry, path,
              "index links to missing concept `#{raw}`", metric: { target: target })
          end
        end
      end

      # ── Completeness ───────────────────────────────────────────────────────────

      def check_stub
        @concepts.each do |concept|
          length = concept.body.to_s.strip.length
          next if length >= @min_body

          @report.add_info(:stub, "#{concept.id}.md",
            "body is #{length} character(s) (under min-body #{@min_body})",
            metric: { chars: length, min: @min_body })
        end
      end

      def check_missing_title
        each_missing(:title, :missing_title, "title")
      end

      def check_missing_description
        each_missing(:description, :missing_description, "description")
      end

      def check_missing_timestamp
        @concepts.each do |concept|
          next unless concept.timestamp.nil?

          @report.add_info(:missing_timestamp, "#{concept.id}.md", "missing recommended field: timestamp")
        end
      end

      # ── Freshness (opt-in) ───────────────────────────────────────────────────────

      def check_stale
        return if @stale_before.nil?

        @concepts.each do |concept|
          at = parse_time(concept.timestamp)
          next if at.nil? || at >= @stale_before

          @report.add_warning(:stale, "#{concept.id}.md",
            "last updated #{concept.timestamp}; older than cutoff #{@stale_before}",
            metric: { timestamp: concept.timestamp.to_s, cutoff: @stale_before.to_s })
        end
      end

      # ── Provenance (§8) ──────────────────────────────────────────────────────────

      def check_uncited_external
        @concepts.each do |concept|
          externals = Markdown::Links.extract(concept.body).count { |raw| external?(raw) }
          next if externals.zero? || Markdown::Citations.section(concept.body)

          @report.add_info(:uncited_external, "#{concept.id}.md",
            "body has external link(s) but no # Citations section",
            metric: { external_count: externals })
        end
      end

      # Verifies .md citation targets only; §8 also permits non-.md references/ assets,
      # which the Bundle does not index and so cannot be checked here.
      def check_broken_citation
        @concepts.each do |concept|
          Markdown::Citations.targets(concept.body).each do |raw|
            target = Markdown::Links.resolve(raw, from: concept.path, bundle: @bundle.root)
            next if target.nil? || @existing.include?(target)

            @report.add_warning(:broken_citation, "#{concept.id}.md",
              "citation target `#{raw}` does not exist in the bundle", metric: { target: target })
          end
        end
      end

      # ── Hygiene ────────────────────────────────────────────────────────────────

      def check_duplicate_title
        @concepts.group_by { |concept| concept.title.to_s.strip.downcase }.each do |key, members|
          next if key.empty? || members.size < 2

          @report.add_info(:duplicate_title, nil,
            "title #{members.first.title.inspect} used by #{members.size} concepts",
            metric: { title: members.first.title, concepts: members.map(&:id).sort })
        end
      end

      def check_unused_reference_def
        @concepts.each do |concept|
          defined = Markdown::Links.reference_definitions(concept.body).keys
          (defined - reference_uses(concept.body)).each do |label|
            @report.add_info(:unused_reference_def, "#{concept.id}.md",
              "reference definition `[#{label}]` is defined but never used", metric: { label: label })
          end
        end
      end

      def check_undefined_reference
        @concepts.each do |concept|
          defined = Markdown::Links.reference_definitions(concept.body).keys
          (reference_uses(concept.body) - defined).each do |label|
            @report.add_warning(:undefined_reference, "#{concept.id}.md",
              "reference-style link `[#{label}]` has no matching definition (an invisible broken link)",
              metric: { label: label })
          end
        end
      end

      def check_self_link
        @concepts.each do |concept|
          count = Markdown::Links.extract(concept.body).count do |raw|
            target = Markdown::Links.resolve(raw, from: concept.path, bundle: @bundle.root)
            target && target.sub(/\.md\z/, "") == concept.id
          end
          next if count.zero?

          @report.add_info(:self_link, "#{concept.id}.md", "concept links to itself", metric: { count: count })
        end
      end

      # ── stats ────────────────────────────────────────────────────────────────────

      def fill_stats
        @report.stat(:concepts, @concepts.size)
        @report.stat(:edges, @graph.edges.size)
        @report.stat(:indexes, @bundle.index_files.size)
        @report.stat(:logs, @bundle.log_files.size)
        @report.stat(:skipped, @bundle.unparseable.size)
        @report.stat(:orphans, count_findings(:orphan))
        @report.stat(:loose, count_findings(:unlinked))
        @report.stat(:stubs, count_findings(:stub))
        @report.stat(:backlog, count_findings(:missing_concept))
        @report.stat(:components, components.size)
        @report.stat(:hubs, hubs)
        # Through Graph.default, not a second `|| "Untyped"`: §9.2 makes a
        # whitespace-only type as non-conformant as a missing one, so the two must
        # land in one bucket. Spelling the rule twice is how lint came to report a
        # `"  "` bucket that `types` and `graph` had never heard of — the same
        # concepts counted by both verbs, into inventories that will not reconcile.
        @report.stat(:types, frequency(@concepts.map { |c| Graph.default(c.type, "Untyped") }))
        @report.stat(:tags, frequency(@concepts.flat_map { |c| c.tags.is_a?(Array) ? c.tags : [] }))
      end

      # ── helpers ────────────────────────────────────────────────────────────────

      def each_missing(field, check, label)
        @concepts.each do |concept|
          next unless OKF.blank?(concept.public_send(field))

          @report.add_info(check, "#{concept.id}.md", "missing recommended field: #{label}")
        end
      end

      # dir (File.dirname of the index path; root index → ".") => Set of listed ids.
      def indexed_by_dir
        @indexed_by_dir ||= @bundle.index_files.each_with_object({}) do |path, map|
          map[File.dirname(path)] = resolved_ids(path)
        end
      end

      def resolved_ids(index_path)
        Markdown::Links.extract(content_of(index_path)).map do |raw|
          target = Markdown::Links.resolve(raw, from: index_path, bundle: @bundle.root)
          target&.sub(/\.md\z/, "")
        end.compact.to_set
      end

      def concepts_in(dir)
        @concepts.select { |concept| OKF.dir_of(concept.id) == dir }
      end

      def index_path_for(dir)
        dir == "." ? "index.md" : "#{dir}/index.md"
      end

      # Connected components of the concept graph, treating edges as undirected. Every
      # concept appears in exactly one component (isolated concepts are singletons).
      def components
        @components ||= begin
          adjacency = Hash.new { |hash, key| hash[key] = [] }
          @graph.edges.each do |edge|
            adjacency[edge[:source]] << edge[:target]
            adjacency[edge[:target]] << edge[:source]
          end
          seen = Set.new
          @ids.sort.each_with_object([]) do |id, groups|
            next if seen.include?(id)

            groups << reachable_from(id, adjacency, seen)
          end
        end
      end

      def reachable_from(start, adjacency, seen)
        queue = [ start ]
        seen << start
        members = []
        until queue.empty?
          node = queue.shift
          members << node
          adjacency[node].each do |neighbor|
            next if seen.include?(neighbor)

            seen << neighbor
            queue << neighbor
          end
        end
        members
      end

      def hubs
        @inbound.select { |_, degree| degree.positive? }
                .sort_by { |id, degree| [ -degree, id ] }
                .first(HUB_LIMIT)
                .map { |id, degree| { id: id, in_degree: degree } }
      end

      def frequency(values)
        counts = values.each_with_object(Hash.new(0)) { |value, hash| hash[value] += 1 }
        counts.sort_by { |value, count| [ -count, value.to_s ] }.to_h
      end

      def reference_uses(body)
        uses = []
        Markdown::Links.each_prose_line(body.to_s) do |line|
          line.scan(Markdown::Links::REFERENCE_LINK).each do |label, explicit|
            uses << (explicit.empty? ? label : explicit).strip.downcase
          end
        end
        uses.uniq
      end

      def external?(raw)
        raw.match?(Markdown::Links::SCHEME) || raw.start_with?("mailto:")
      end

      def count_findings(check)
        @report.findings.count { |finding| finding[:check] == check }
      end

      def content_of(path)
        @bundle.reserved_content(path)
      end

      def parse_time(value)
        return value.to_time if value.is_a?(Date)
        return value if value.is_a?(Time)
        return nil if value.nil?

        string = value.to_s
        begin
          Time.iso8601(string)
        rescue ArgumentError
          begin
            Date.iso8601(string).to_time
          rescue ArgumentError
            nil
          end
        end
      end
    end
  end
end
