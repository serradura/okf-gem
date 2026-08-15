# frozen_string_literal: true

module OKF
  class Bundle
    # Lints a bundle for curation quality — the deterministic subset of the
    # ingest → query → lint loop (overview.md): reachability, backlog, completeness,
    # freshness, provenance, attestation, migration, and hygiene. Pure — it reads
    # nothing from disk and works entirely on the in-memory OKF::Bundle, mirroring
    # OKF::Bundle::Validator.
    #
    # Unlike OKF::Bundle::Validator (the §11 conformance gate, which MUST NOT reject for
    # broken links or missing optional fields), lint never rejects a bundle: it reports
    # `:warn` and `:info` findings the spec marks as tolerable, and emits them as
    # structured data (OKF::Bundle::Linter::Report) for a human or agent to act on. Contradictions
    # and semantic staleness are NOT detected here — they need meaning, not structure;
    # the JSON report is the substrate an agent consumes for those passes.
    class Linter
      # Severity is API: machine consumers gate edits and CI on `:warn` and drop
      # `:info`, so an id changing level changes its behavior for them — this map
      # is pinned by a test, and a new gateable state gets a flag (`--fail-on
      # info`), never a severity promotion. Two calls worth their one sentence:
      # `unattributed_claim` warns while its join-twin `unused_source` informs,
      # because a dangling footnote misattributes a claim — a correctness defect —
      # while an uncited source is only slack. And `expired` informs rather than
      # warns: a `stale_after` passes on the calendar, not on a change, so a warn
      # would fail a `--fail-on warn` gate on a morning nobody chose.
      SEVERITIES = {
        orphan: :warn, not_in_index: :warn, disconnected_component: :info, unlinked: :info,
        missing_concept: :info, broken_index_entry: :warn,
        stub: :info, missing_title: :info, missing_description: :info, missing_generated: :info,
        expired: :info, stale: :warn,
        uncited_external: :info, broken_source: :warn, unattributed_claim: :warn,
        unused_source: :info, unprefixed_actor: :info,
        incomplete_computation: :warn, broken_attestation_ref: :warn,
        legacy_timestamp: :info, legacy_citations: :info,
        duplicate_title: :info, unused_reference_def: :info, undefined_reference: :warn, self_link: :info,
        log_order: :info
      }.freeze

      # All checks, in display/registry order — derived from the severity map
      # (insertion-ordered) rather than hand-listed twice: two parallel lists
      # of the same 25 ids needed a test just to police their sync.
      # `--only`/`--except` select from these.
      CHECKS = SEVERITIES.keys.freeze

      # An ATX heading naming the §10.3 computation section.
      COMPUTATION_HEADING = /\A\#{1,6}\s+Computation\s*\z/i.freeze

      # §7's three actor forms: `<producer>/<version>`, `human:<id>`, `process:<id>`.
      ACTOR_FORMS = [ %r{\A\S+/\S+\z}, /\Ahuman:\S+\z/, /\Aprocess:\S+\z/ ].freeze

      DEFAULT_MIN_BODY = 50
      HUB_LIMIT = 5

      def self.call(bundle, **options)
        new(bundle, **options).call
      end

      # `today` is injected for the same reason `stale_before` is: the linter is
      # pure and never reads the clock. Without it `expired` cannot know whether
      # a `stale_after` has passed and does not run — and confesses, in
      # stats[:skipped_checks], because a gate that is sometimes absent and does
      # not say so converts "unchecked" into "checked and fine". The CLI always
      # passes today; a library caller that wants the check passes `today:`.
      def initialize(bundle, min_body: DEFAULT_MIN_BODY, stale_before: nil, today: nil, only: nil, except: nil)
        @bundle = bundle
        @min_body = min_body
        @stale_before = stale_before
        @today = coerce_today(today)
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

      # An id outside CHECKS refuses by name rather than intersecting to
      # nothing: a caller pinned to a renamed id would otherwise get an empty,
      # healthy report with skipped_checks: [] — "checked and fine" over a run
      # that ran nothing, the exact silence skipped_checks exists to prevent.
      # The CLI and the MCP shell validate first and exit 2; this is the same
      # refusal for the library caller who has no argv layer in front.
      def selected_checks
        unknown = (Array(@only) + Array(@except)).map(&:to_sym) - CHECKS
        raise ArgumentError, "unknown check(s): #{unknown.uniq.join(", ")} (checks: #{CHECKS.join(", ")})" unless unknown.empty?

        checks = CHECKS
        checks &= Array(@only).map(&:to_sym) if @only
        checks -= Array(@except).map(&:to_sym) if @except
        checks
      end

      # The documented contract is a Date, but the comment above *invites*
      # library callers to pass one — so a Time or an ISO string coerces
      # instead of detonating inside Concept#stale_on? halfway through a run,
      # and anything else fails fast, here, with the contract named.
      def coerce_today(value)
        case value
        when nil then nil
        when DateTime, Time then value.to_date
        when Date then value
        when String then parse_today(value)
        else raise ArgumentError, "today: must be a Date (got #{value.class})"
        end
      end

      # The rescue belongs to the parse alone. Wrapping the whole `case` put it
      # around its own `else` too, so the refusal that names the class was
      # caught and rewritten into the string message on its way out — a branch
      # that could not be reached from any caller.
      def parse_today(value)
        raise ArgumentError, "not YYYY-MM-DD" unless value.match?(Concept::ISO_DATE)

        Date.iso8601(value)
      rescue ArgumentError
        raise ArgumentError, "today: must be a Date or a YYYY-MM-DD string (got #{value.inspect})"
      end

      # Every finding lands through here, so a check's severity has exactly one
      # home — the SEVERITIES map — and cannot drift per call site.
      def add(check, path, message, metric: nil)
        if SEVERITIES.fetch(check) == :warn
          @report.add_warning(check, path, message, metric: metric)
        else
          @report.add_info(check, path, message, metric: metric)
        end
      end

      # ── Reachability ─────────────────────────────────────────────────────────

      def check_orphan
        @concepts.each do |concept|
          next if @inbound[concept.id].positive? || @indexed_ids.include?(concept.id)

          add(:orphan, "#{concept.id}.md",
            "unreachable: no inbound links and not listed in any index.md")
        end
      end

      def check_not_in_index
        indexed_by_dir.each do |dir, listed|
          concepts_in(dir).each do |concept|
            next if listed.include?(concept.id)

            add(:not_in_index, "#{concept.id}.md",
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

          add(:disconnected_component, nil,
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

          add(:unlinked, "#{concept.id}.md",
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
          add(:missing_concept, target,
            "referenced by #{entry[:references]} link(s) across #{entry[:sources].size} concept(s) but does not exist",
            metric: { references: entry[:references], sources: entry[:sources] })
        end
      end

      def check_broken_index_entry
        @bundle.index_files.each do |path|
          Markdown::Links.extract(content_of(path)).each do |raw|
            target = Markdown::Links.resolve(raw, from: path, bundle: @bundle.root)
            next if target.nil? || @existing.include?(target)

            add(:broken_index_entry, path,
              "index links to missing concept `#{raw}`", metric: { target: target })
          end
        end
      end

      # ── Completeness ───────────────────────────────────────────────────────────

      def check_stub
        @concepts.each do |concept|
          length = concept.body.to_s.strip.length
          next if length >= @min_body

          add(:stub, "#{concept.id}.md",
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

      # Raw keys, not the accessor: a v0.1 `timestamp` is a recorded change time
      # (§13.1 reads it), so the check is quiet on either spelling — it fires
      # only when a document records nothing at all.
      def check_missing_generated
        @concepts.each do |concept|
          next if concept.declared_generated? || concept.legacy_timestamp?

          add(:missing_generated, "#{concept.id}.md", "missing recommended field: generated")
        end
      end

      # ── Freshness ────────────────────────────────────────────────────────────────

      # §5.5 — the author's own declared expiry, clock-gated: it runs only when
      # the caller supplies a day to compare against, exactly the opt-in shape
      # :stale has. Deliberately separate from :stale, which is a
      # reader-supplied cutoff over `generated_at`: merging them would make a
      # bundle's own contract depend on a CLI flag.
      def check_expired
        return if @today.nil?

        @concepts.each do |concept|
          next unless concept.stale_on?(@today)

          add(:expired, "#{concept.id}.md",
            "expired on #{concept.stale_after_date} (stale_after)",
            metric: { stale_after: concept.stale_after_date.to_s,
                      days_past: (@today - concept.stale_after_date).to_i })
        end
      end

      # Opt-in, and the operator's opinion rather than the bundle's: a cutoff
      # supplied at the command line, compared against the last-change time.
      def check_stale
        return if @stale_before.nil?

        @concepts.each do |concept|
          at = parse_time(concept.generated_at)
          next if at.nil? || at >= @stale_before

          add(:stale, "#{concept.id}.md",
            "last updated #{concept.generated_at}; older than cutoff #{@stale_before}",
            metric: { generated_at: concept.generated_at.to_s, cutoff: @stale_before.to_s })
        end
      end

      # ── Provenance (§5.1/§5.2) ───────────────────────────────────────────────────

      # Asks `#sources` — the one place lint deliberately reads through the
      # fallback-carrying accessor — so a v0.1 `# Citations` silences it and a
      # migrated `sources` block silences it too. The section check beside it
      # is not redundant: a prose-only `# Citations` ("See the Q3 report")
      # yields no lifted mappings, and firing on it would fault a v0.1 concept
      # that did record provenance — just not as links.
      def check_uncited_external
        @concepts.each do |concept|
          # Memoized guards first: the link extraction is the expensive pass,
          # and a sourced concept never needs it run.
          next if concept.sources.any? || concept.legacy_citations?

          externals = Markdown::Links.extract(concept.body).count { |raw| external?(raw) }
          next if externals.zero?

          add(:uncited_external, "#{concept.id}.md",
            "body has external link(s) but no sources",
            metric: { external_count: externals })
        end
      end

      # The resolver is the discriminator: `Links.resolve` accepts only an
      # in-bundle `.md` path, so URLs, scope descriptors, and non-`.md` assets
      # (`references/attesters/revenue.py`) are exempt by construction — §5.1
      # permits all three, and the Bundle does not index them.
      #
      # A leftover `# Citations` section is checked *beside* the native list,
      # not only through the fallback: on a half-migrated concept the native
      # entries win #sources, but §13.1 keeps the section readable, and its
      # broken target was a warn before migration started — adopting `sources:`
      # must not downgrade that gate to the info-level backlog checks. When the
      # fallback did fire, the lifted entries and the section are the same
      # values, deduplicated below.
      def check_broken_source
        @concepts.each do |concept|
          resources = concept.sources.map { |source| source["resource"].to_s }
          resources += concept.citation_entries.map { |entry| entry[:target].to_s } if concept.legacy_citations?
          resources.uniq.each do |raw|
            target = Markdown::Links.resolve(raw, from: concept.path, bundle: @bundle.root)
            next if target.nil? || @existing.include?(target)

            add(:broken_source, "#{concept.id}.md",
              "source target `#{raw}` does not exist in the bundle", metric: { target: target })
          end
        end
      end

      # §5.1's keyed attribution, checked in both directions. A dangling footnote
      # misattributes a claim, so it warns; an uncited source (below) is only
      # slack, so it informs. Two boundaries on the join: a concept with no
      # sources[].id at all has not adopted keyed attribution — §5.1 does not
      # reserve footnotes for it, and an ordinary GFM footnote is prose, not a
      # fault — and the label↔id comparison folds case the way GFM resolves
      # footnotes and reference_definitions already folds labels.
      def check_unattributed_claim
        @concepts.each do |concept|
          ids = source_ids(concept).map(&:downcase)
          next if ids.empty?

          defined = Markdown::Links.footnote_definitions(concept.body).map(&:downcase)
          footnote_labels(concept).each do |label|
            next if ids.include?(label.downcase)
            # A label with its own definition is an ordinary GFM content
            # footnote — it renders complete, and §5.1 never reserves the
            # label space for attribution. The dangling ones (no id, no
            # definition) are the misattributions this check exists for.
            next if defined.include?(label.downcase)

            add(:unattributed_claim, "#{concept.id}.md",
              "footnote `[^#{label}]` has no matching sources[].id", metric: { label: label })
          end
        end
      end

      # Sources with no `id` never participate — a lifted v0.1 citation has
      # none, and it would be wrong to fault a bundle for not having adopted
      # keyed attribution. The same case fold, and the same guard-first order,
      # as its join-twin above: without them every concept of a non-adopting
      # bundle paid a full body scan to compare against an empty set.
      def check_unused_source
        @concepts.each do |concept|
          ids = source_ids(concept)
          next if ids.empty?

          labels = footnote_labels(concept).to_set(&:downcase)
          ids.each do |id|
            next if labels.include?(id.downcase)

            add(:unused_source, "#{concept.id}.md",
              "source `#{id}` is never cited by a footnote", metric: { id: id })
          end
        end
      end

      # A missing `generated.by` is deliberately NOT a lint check: §5.2 marks
      # `by` REQUIRED within the mapping, REQUIRED-within is the validator's
      # side of the split, and the validator's :generated_by warning already
      # reports it — a lint twin double-counted one defect with two severities,
      # exactly what the parallel `verified[].by` family never did.

      # The two fields §7 gives the actor convention to. `verified[].by` is
      # where the misread bites — §5.3 derives the tier from it, so a bare
      # `by: owner` silently reads as machine-confirmed. `generated.by` feeds
      # no tier, but it is the field §7 names first, and a form nothing can
      # classify leaves a provenance reader unable to tell a person from a
      # process — so it earns the finding with its own consequence. Still not
      # `sources[].author` (the SPEC's own examples use `team:<id>` there),
      # and a *missing* `generated.by` stays the validator's warning.
      # Info is load-bearing: it must inform, never block.
      def check_unprefixed_actor
        @concepts.each do |concept|
          fields = []
          generated_by = concept.generated && concept.generated["by"]
          fields << [ "generated.by", generated_by, generated_consequence ]
          concept.verified.each { |event| fields << [ "verified.by", event["by"], nil ] }
          fields.each do |field, raw, consequence|
            actor = raw.to_s.strip
            next if actor.empty? || ACTOR_FORMS.any? { |form| actor.match?(form) }

            add(:unprefixed_actor, "#{concept.id}.md",
              "#{field} `#{actor}` matches none of §7's forms (`<producer>/<version>`, `human:<id>`, " \
              "`process:<id>`)#{consequence || actor_consequence(actor)}",
              metric: { by: actor, field: field })
          end
        end
      end

      # §5.3 reads the tier off the `human:` prefix and nothing else, so an
      # actor that carries it is already human-reviewed however malformed the
      # id is — and the same report's trust stat says so. Telling that reader
      # it "reads as machine-confirmed" contradicted the run they were reading
      # and pointed the fix at a tier that was never wrong; the id is what
      # needs the edit.
      def actor_consequence(actor)
        return " — the `human:` prefix already reads as human-reviewed, but the id is not a bare token" \
          if actor.start_with?(Concept::HUMAN_ACTOR)

        " and reads as machine-confirmed; use `human:<id>` if a person confirmed this"
      end

      # §5.3 never reads `generated.by`, so unlike a verified actor nothing is
      # misclassified — the cost is the audit trail: nobody downstream can say
      # what kind of actor produced the text.
      def generated_consequence
        " — no trust tier reads it (§5.3 keys off verified), but a reader cannot tell a person from a process"
      end

      # §9 describes the log as date-grouped entries, newest first — prose, not
      # an RFC keyword, so disorder is curation slack rather than a §11 error:
      # exactly lint's side of the split. Only shape-valid headings are
      # compared; a malformed date is already the validator's error, and
      # double-reporting it here as disorder would name one defect twice.
      def check_log_order
        @bundle.log_files.each do |path|
          dates = @bundle.reserved_content(path).each_line
                         .select { |line| line.start_with?("## ") }
                         .map { |line| line.sub(/\A## /, "").strip }
                         .grep(/\A\d{4}-\d{2}-\d{2}\z/)
          next if dates == dates.sort.reverse

          add(:log_order, path,
            "date headings are not newest-first (§9): #{dates.join(", ")}",
            metric: { dates: dates })
        end
      end

      # ── Attestation (§10) ────────────────────────────────────────────────────────

      # `incomplete_computation` asks whether the contract *names* its
      # computation; this asks whether what it names is there. A §10 contract
      # is an instruction to run something, so a path resolving to nothing is
      # not slack the way an uncited source is — it is a contract no consumer
      # can follow, which is why it warns like `broken_source` rather than
      # informing. Same exemption by construction as `broken_source`: Links.resolve
      # yields nil for a URL or a non-`.md` asset, so a `references/*.sql`
      # computation and an `https://` runbook are both silently fine.
      def check_broken_attestation_ref
        @concepts.each do |concept|
          # Gated on the type, like check_incomplete_computation: §4.1 lets a
          # producer put `computation:` or `executor:` on anything and mean
          # their own thing by it, and §10 governs those keys only here. An
          # ungated check would fail a --fail-on warn gate over a key it has
          # no standing to read.
          next unless concept.attested_computation?

          attestation_refs(concept).each do |field, raw|
            target = Markdown::Links.resolve(raw.to_s, from: concept.path, bundle: @bundle.root)
            next if target.nil? || @existing.include?(target)

            add(:broken_attestation_ref, "#{concept.id}.md",
              "#{field} `#{raw}` does not exist in the bundle", metric: { field: field, target: target })
          end
        end
      end

      # The §10 fields that name a file: `computation` (§10.3's path form) and
      # the `resource` of `executor`/`attester` (§10.2), in the order a reader
      # meets them so two dangling paths on one concept report predictably.
      # #executor/#attester are nil unless the value is a mapping, so a
      # malformed `executor: <path>` reads as absent here — its shape is the
      # validator's finding, not a second report of the same defect.
      def attestation_refs(concept)
        [
          [ "computation", concept.computation ],
          [ "executor.resource", concept.executor && concept.executor["resource"] ],
          [ "attester.resource", concept.attester && concept.attester["resource"] ]
        ]
      end

      # §10.2/§10.3: the computation is provided exactly one way — a body
      # `# Computation` fence *or* a `computation` path ("used instead of").
      # Neither is a contract with nothing to run; both is two candidate
      # computations and no rule for which one was sanctioned. Missing `runtime`
      # is the validator's (shape/REQUIRED-within is its side of the split).
      def check_incomplete_computation
        @concepts.each do |concept|
          next unless concept.attested_computation?

          inline = computation_heading?(concept.body)
          declared = !OKF.blank?(concept.computation)
          if !inline && !declared
            add(:incomplete_computation, "#{concept.id}.md",
              "Attested Computation with no computation (neither a computation: path nor a # Computation section)",
              metric: { provided: [] })
          elsif inline && declared
            add(:incomplete_computation, "#{concept.id}.md",
              "Attested Computation provides its computation twice (§10.3: a computation: path is used " \
              "instead of a # Computation section — keep one)",
              metric: { provided: %w[computation body] })
          end
        end
      end

      # ── Migration (§13.1) ────────────────────────────────────────────────────────

      # What replaces a version gate. An operator running lint on a v0.1 bundle is
      # *told*, in the tool that already exists for telling them things, and is
      # never blocked — both are info, because §13 says the bundle is consumable
      # forever and `--fail-on warn` must not turn red on it. A migration
      # campaign gates explicitly: `--only legacy_timestamp,legacy_citations
      # --fail-on info`.
      #
      # One finding per *bundle*, not per concept: a v0.1 bundle is v0.1 in every
      # file, so a per-concept finding would print the same sentence once per
      # document. `path` is nil and the members live in `metric`, exactly as
      # :disconnected_component and :duplicate_title do.
      def check_legacy_timestamp
        report_legacy(:legacy_timestamp,
          "the retired v0.1 `timestamp`; move the value under `generated: { by: <actor>, at: <the timestamp> }` " \
          "— the actor is yours to supply, no tool can derive it", &:legacy_timestamp?)
      end

      def check_legacy_citations
        report_legacy(:legacy_citations,
          "the retired v0.1 `# Citations` section; move provenance into a `sources:` list " \
          "(`resource` plus optional `id`/`title`), key claims with `[^id]` footnotes, then delete the section",
          &:legacy_citations?)
      end

      # ── Hygiene ────────────────────────────────────────────────────────────────

      def check_duplicate_title
        @concepts.group_by { |concept| concept.title.to_s.strip.downcase }.each do |key, members|
          next if key.empty? || members.size < 2

          add(:duplicate_title, nil,
            "title #{members.first.title.inspect} used by #{members.size} concepts",
            metric: { title: members.first.title, concepts: members.map(&:id).sort })
        end
      end

      def check_unused_reference_def
        @concepts.each do |concept|
          defined = Markdown::Links.reference_definitions(concept.body).keys
          (defined - reference_uses(concept.body)).each do |label|
            add(:unused_reference_def, "#{concept.id}.md",
              "reference definition `[#{label}]` is defined but never used", metric: { label: label })
          end
        end
      end

      def check_undefined_reference
        @concepts.each do |concept|
          defined = Markdown::Links.reference_definitions(concept.body).keys
          (reference_uses(concept.body) - defined).each do |label|
            add(:undefined_reference, "#{concept.id}.md",
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

          add(:self_link, "#{concept.id}.md", "concept links to itself", metric: { count: count })
        end
      end

      # ── stats ────────────────────────────────────────────────────────────────────

      def fill_stats
        @report.stat(:concepts, @concepts.size)
        @report.stat(:edges, @graph.edges.size)
        @report.stat(:indexes, @bundle.index_files.size)
        @report.stat(:logs, @bundle.log_files.size)
        @report.stat(:skipped, @bundle.unparseable.size)
        @report.stat(:skipped_checks, skipped_checks)
        @report.stat(:orphans, count_findings(:orphan))
        @report.stat(:loose, count_findings(:unlinked))
        @report.stat(:stubs, count_findings(:stub))
        @report.stat(:backlog, count_findings(:missing_concept))
        @report.stat(:components, components.size)
        @report.stat(:hubs, hubs)
        # Through Graph.default, not a second `|| "Untyped"`: §11.2 makes a
        # whitespace-only type as non-conformant as a missing one, so the two must
        # land in one bucket. Spelling the rule twice is how lint came to report a
        # `"  "` bucket that `types` and `graph` had never heard of — the same
        # concepts counted by both verbs, into inventories that will not reconcile.
        @report.stat(:types, frequency(@concepts.map { |c| Graph.default(c.type, "Untyped") }))
        @report.stat(:tags, frequency(@concepts.flat_map { |c| c.tags.is_a?(Array) ? c.tags : [] }))
        @report.stat(:trust, trust_distribution)
        # Folded through the same rule --status narrows by, or the posture
        # inventory cannot reconcile with the filter that acts on it.
        @report.stat(:status, frequency(@concepts.map { |c| Concept.effective_status(c.declared_status) }))
      end

      # The clock-gated checks that were selected and could not run — named,
      # never silent: a gate that is sometimes absent and does not confess
      # converts "unchecked" into "checked and fine". This also makes :stale
      # honest; it has been silently opt-in since it shipped.
      def skipped_checks
        skipped = []
        selected = selected_checks
        skipped << :expired if selected.include?(:expired) && @today.nil?
        skipped << :stale if selected.include?(:stale) && @stale_before.nil?
        skipped
      end

      # §5.3's three tiers, counted, in the wire spelling the rows use. A
      # per-concept `unverified` *check* would fire on every concept of every
      # bundle that has not adopted `verified`, so the posture is a distribution
      # instead of noise. All three keys are always present, zeroes included: a
      # missing key reads as "not measured" where 0 reads as "none", and only
      # one of those is true.
      def trust_distribution
        counts = { "unverified" => 0, "machine-confirmed" => 0, "human-reviewed" => 0 }
        @concepts.each { |concept| counts[concept.trust] += 1 }
        counts
      end

      # ── helpers ────────────────────────────────────────────────────────────────

      def each_missing(field, check, label)
        @concepts.each do |concept|
          next unless OKF.blank?(concept.public_send(field))

          add(check, "#{concept.id}.md", "missing recommended field: #{label}")
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
            key = (explicit.empty? ? label : explicit).strip.downcase
            # A caret label is footnote space (§5.1) — the exclusion DEFINITION
            # already makes. Adjacent footnotes (`[^a][^b]`) match the
            # reference-link grammar, and counting them here turned a
            # well-formed document into an undefined_reference warn.
            uses << key unless key.start_with?("^")
          end
        end
        uses.uniq
      end

      def source_ids(concept)
        concept.sources.map { |source| source["id"].to_s.strip }.reject(&:empty?)
      end

      # One body scan per concept, however many joins ask — the two keyed-
      # attribution checks read the same labels, and the scan is a real
      # per-line pass (CODE_SPAN blanking included).
      def footnote_labels(concept)
        @footnote_labels ||= {}
        # Keyed on the path, which is unique by construction — two files may
        # pin the same custom `id`, and an id-keyed cache cross-contaminated
        # their joins.
        @footnote_labels[concept.path] ||= Markdown::Links.footnote_references(concept.body)
      end

      # Whether the body carries a §10.3 `# Computation` section, fence-aware.
      # §10.3's inline form is "a single fenced code block in the body under
      # `# Computation`" — so inline is proven by the fence, not the heading. A
      # heading over prose used to count as provided, and a contract with
      # nothing an executor could run lint'd clean. Walked raw (not through
      # each_prose_line, which blanks fences): a fence line while the section
      # is open is the answer, and a heading inside an earlier fence is text.
      def computation_heading?(body)
        in_fence = false
        in_section = false
        body.to_s.each_line do |line|
          stripped = line.strip
          if stripped.start_with?("```", "~~~")
            return true if in_section && !in_fence

            in_fence = !in_fence
            next
          end
          next if in_fence

          if COMPUTATION_HEADING.match?(stripped)
            in_section = true
          elsif in_section && stripped.match?(/\A\#{1,6}\s/)
            in_section = false
          end
        end
        false
      end

      # One bundle-level finding naming how many concepts carry a retired
      # spelling, with the file list in the metric for whatever will rewrite them.
      def report_legacy(check, description, &spelling)
        members = @concepts.select(&spelling).map { |concept| "#{concept.id}.md" }
        return if members.empty?

        add(check, nil,
          "#{members.size} concept(s) still use #{description}",
          metric: { concepts: members.sort })
      end

      def external?(raw)
        raw.match?(Markdown::Links::SCHEME) || raw.match?(Markdown::Links::MAILTO)
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
