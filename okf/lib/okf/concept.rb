# frozen_string_literal: true

module OKF
  class Concept
    # Reserved filenames (spec §3.1): defined at any level of the hierarchy and
    # never concept documents. The single source of truth for "concept vs
    # reserved" — OKF::Bundle and OKF::Bundle::Validator ask through Concept.reserved?.
    RESERVED_FILENAMES = %w[index.md log.md].freeze

    # The lint checks that apply to a single concept out of bundle context. The
    # rest (orphan, backlog, duplicate_title, broken_source, …) need the whole
    # bundle. Linter#selected_checks intersects silently, so a stale id here
    # quietly stops Concept#lint running the check — a test pins the list
    # against Linter::CHECKS.
    CONCEPT_SCOPED_CHECKS = %i[
      stub missing_title missing_description missing_generated
      expired uncited_external unattributed_claim unused_source
      missing_generated_by unprefixed_actor incomplete_computation
      legacy_timestamp legacy_citations
      self_link unused_reference_def undefined_reference
    ].freeze

    # The spec versions this gem has a reader for, newest first — what a root
    # `index.md`'s `okf_version` is checked against (§12). A document is always
    # read as the newest version, without sniffing its shape: §13.1 makes the
    # legacy fallbacks part of v0.2's own reading rule, so a v0.2 reader handed
    # a v0.1 document is the correct reader for it.
    KNOWN_SPEC_VERSIONS = %w[0.2 0.1].freeze

    # The prefix §7 reserves for a person, and the whole of what §5.3's tier
    # classifier keys off — which is why §7 makes producers MUST use it for
    # hand-authored or human-confirmed content.
    HUMAN_ACTOR = "human:"

    # §5.4. The three values the spec names. A producer MAY use another (§4.1),
    # and consumers MUST tolerate it, so this is what the validator warns
    # against — never what a reader rejects.
    STATUSES = %w[draft stable deprecated].freeze

    # §5.4: "Absent `status` ⇒ `stable`."
    DEFAULT_STATUS = "stable"

    # §10.1. The type that carries a sanctioned computation.
    ATTESTED_COMPUTATION = "Attested Computation"

    # Whether a bundle-relative path names a reserved file rather than a concept.
    # `::File` is explicit: OKF::Concept::File (the on-disk handle) shadows Ruby's
    # File inside this namespace.
    def self.reserved?(path)
      RESERVED_FILENAMES.include?(::File.basename(path))
    end

    attr_reader :path, :frontmatter, :body

    def initialize(path:, frontmatter:, body:)
      @path = Path.normalize_relative!(path)
      @frontmatter = Markdown::Frontmatter.stringify_keys(frontmatter)
      @body = body.to_s
    end

    # Stable node identity. A concept may pin an explicit `id` in its frontmatter
    # (any scalar; blank is ignored); otherwise it is the bundle-relative path with
    # the `.md` suffix stripped — i.e. "folder/filename". Because cross-links are
    # file paths, OKF::Bundle maps a resolved link path back to the concept there
    # and uses *its* id, so a custom id still resolves edges correctly.
    def id
      explicit = frontmatter["id"].to_s.strip
      explicit.empty? ? path.sub(/\.md\z/, "") : explicit
    end

    def type
      frontmatter["type"]
    end

    def title
      frontmatter["title"]
    end

    def description
      frontmatter["description"]
    end

    # Canonical URI of the underlying asset (spec §4.1), when the concept is bound
    # to one. Absent for concepts describing purely abstract ideas.
    def resource
      frontmatter["resource"]
    end

    def tags
      frontmatter["tags"]
    end

    # The raw v0.1 field, kept readable because §13.1 keeps it consumable; what
    # it *means* is #generated's business.
    def timestamp
      frontmatter["timestamp"]
    end

    def reserved?
      self.class.reserved?(path)
    end

    # ── §5.2 trust: generated, with §13.1's timestamp fallback ──

    # How the current content was produced, as { "by", "at" }. A lifted
    # `timestamp` yields no `by`: the v0.1 field never recorded an actor, and
    # inventing one — the running user, the gem — is exactly the false
    # provenance claim §5 exists to prevent. A non-mapping `generated` is
    # ignored rather than rejected (§11) and falls back like an absent one.
    def generated
      native = frontmatter["generated"]
      return Markdown::Frontmatter.stringify_keys(native) if native.is_a?(Hash)
      return nil if OKF.blank?(timestamp)

      { "at" => timestamp }
    end

    # The content's last meaningful change (ISO 8601). The fallback is per-key,
    # not per-mapping: a half-migrated document carrying `generated: { by: … }`
    # *plus* a legacy `timestamp` must not lose its date.
    def generated_at
      at = generated && generated["at"]
      return at unless OKF.blank?(at)

      timestamp unless OKF.blank?(timestamp)
    end

    def generated_by
      generated && generated["by"]
    end

    # Whether the document *declares* a `generated` mapping — raw-key detection,
    # never the fallback. The one predicate that distinguishes hand-written
    # (no provenance at all) from v0.1-with-timestamp, which #generated_at
    # alone conflates.
    def declared_generated?
      frontmatter.key?("generated")
    end

    # §5.2: "A single verifier MAY be written as one { by, at } mapping without
    # the list dash. Consumers MUST treat a bare mapping as a one-element list."
    # Entries that are not mappings are dropped here and warned about by the
    # validator; `verified: []` and all-entries-dropped fold into the key-absent
    # case — every degenerate shape reads as unverified.
    def verified
      raw = frontmatter["verified"]
      entries = raw.is_a?(Hash) ? [ raw ] : Array(raw)
      entries.grep(Hash).map { |entry| Markdown::Frontmatter.stringify_keys(entry) }
    end

    # §5.3 — derived, never stored. A stored tier would be subjective,
    # unportable between consumers, and stale the moment a verification lands,
    # so the spec has consumers infer it and OKF record only the events.
    def trust_tier
      events = verified
      return :unverified if events.empty?
      return :human_reviewed if events.any? { |event| event["by"].to_s.start_with?(HUMAN_ACTOR) }

      :machine_confirmed
    end

    # ── §5.1 provenance: sources, with §13.1's Citations fallback ──

    # The materials this concept derives from, as a list of mappings each
    # carrying at least a `resource`. The fallback to a legacy `# Citations`
    # body list fires when the native value yields *zero mappings* — absent,
    # non-list, or a list with no mapping entries — not merely when the key is
    # absent: `sources: [prod-db, warehouse]` has always been a legal free-form
    # key (§4.1), and it must not silently mask a document's real provenance.
    def sources
      native = frontmatter["sources"]
      if native.is_a?(Array)
        entries = native.grep(Hash)
        return entries.map { |entry| Markdown::Frontmatter.stringify_keys(entry) } unless entries.empty?
      end

      Markdown::Citations.entries(body).map do |entry|
        source = {}
        source["title"] = entry[:text] unless OKF.blank?(entry[:text])
        source["resource"] = entry[:target]
        source
      end
    end

    # §5.1. Written once as a sibling of `sources`, framing every `usage_count`
    # with a { from, to } range; an entry MAY override it (validated for shape,
    # deliberately consumed by nothing — see model/concept.md).
    def usage_window
      mapping("usage_window")
    end

    # ── §5.4/§5.5 lifecycle ──

    # The effective status, defaulted per §5.4. #declared_status keeps the raw
    # value for the surfaces that must not fabricate frontmatter a concept
    # never declared.
    def status
      OKF.blank?(declared_status) ? DEFAULT_STATUS : declared_status.to_s.strip
    end

    def declared_status
      frontmatter["status"]
    end

    # §5.5. An absolute date, not a relative TTL — which is what keeps staleness
    # a plain date comparison with no reference to when the concept was read.
    def stale_after
      frontmatter["stale_after"]
    end

    # The parsed `stale_after`, or nil when absent or unparseable — strict
    # YYYY-MM-DD, the one spelling §5.5 names. Psych may already have yielded a
    # Date; an unparseable string is a validator warning, never a read failure.
    def stale_after_date
      value = stale_after
      return value if value.is_a?(Date)

      text = value.to_s.strip
      return nil unless text.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      begin
        Date.iso8601(text)
      rescue ArgumentError
        nil
      end
    end

    # Pure: it takes the day rather than reading the clock. §5.5 puts the
    # boundary *on* the day itself: stale when `today >= stale_after`.
    def stale_on?(today)
      date = stale_after_date
      !date.nil? && today >= date
    end

    # ── §10 attested computation ──

    def attested_computation?
      type.to_s.strip == ATTESTED_COMPUTATION
    end

    # §10.2. REQUIRED for the type — but §11's conformance conditions are only
    # three, so its absence is a warning and never an error.
    def runtime
      frontmatter["runtime"]
    end

    # The typed, named holes an agent may fill (§10.3: bind values for declared
    # parameters only; never author or edit the computation).
    def parameters
      Array(frontmatter["parameters"]).grep(Hash)
                                      .map { |entry| Markdown::Frontmatter.stringify_keys(entry) }
    end

    # §10.3. A path to a file holding the computation, used instead of an inline
    # body fence. Absent ⇒ the `# Computation` fence is the computation.
    def computation
      frontmatter["computation"]
    end

    # §10.2. How the computation is run: `resource` names run instructions,
    # `receipt` declares the fields a run must return.
    def executor
      mapping("executor")
    end

    # §10.2. The deterministic (no-LLM) check that takes a receipt and returns a
    # verdict. Meant to run consumer-side.
    def attester
      mapping("attester")
    end

    # ── detection (lint's and the surfaces'; never reading's) ──

    def legacy_timestamp?
      frontmatter.key?("timestamp")
    end

    def legacy_citations?
      !Markdown::Citations.section(body).nil?
    end

    # ── analysis (pure; the same primitives the graph/linter use) ──

    # Raw markdown cross-link targets in the body, in document order (spec §6).
    def links
      Markdown::Links.extract(body)
    end

    # Body links that point outside the bundle — external URLs and mailto:.
    def external_links
      links.select { |raw| raw.match?(Markdown::Links::SCHEME) || raw.start_with?("mailto:") }
    end

    # Serialize back to a markdown document (frontmatter + body) — the inverse of
    # Markdown::Frontmatter.parse.
    def to_markdown
      Markdown::Frontmatter.dump(frontmatter, body)
    end

    # Lint this concept in isolation: the concept-scoped checks only (a lone
    # concept has no bundle to judge reachability, backlog, or duplicate titles).
    def lint(**options)
      Bundle.new(concepts: [ self ]).lint(only: CONCEPT_SCOPED_CHECKS, **options)
    end

    private

    # A frontmatter value that must be a mapping, with its keys stringified — or
    # nil when it is anything else. The validator warns about the "anything
    # else" case; readers just see nothing, per §11's tolerate-don't-reject.
    def mapping(key)
      value = frontmatter[key]
      value.is_a?(Hash) ? Markdown::Frontmatter.stringify_keys(value) : nil
    end
  end
end
