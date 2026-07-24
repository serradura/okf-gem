# frozen_string_literal: true

module OKF
  class Concept
    # Reserved filenames (spec §3.1): defined at any level of the hierarchy and
    # never concept documents. The single source of truth for "concept vs
    # reserved" — OKF::Bundle and OKF::Bundle::Validator ask through Concept.reserved?.
    RESERVED_FILENAMES = %w[index.md log.md].freeze

    # The lint checks that apply to a single concept out of bundle context. The
    # rest (orphan, backlog, duplicate_title, …) need the whole bundle.
    CONCEPT_SCOPED_CHECKS = %i[
      stub missing_title missing_description missing_timestamp
      uncited_external self_link unused_reference_def undefined_reference
    ].freeze

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

    def timestamp
      frontmatter["timestamp"]
    end

    def reserved?
      self.class.reserved?(path)
    end

    # ── analysis (pure; the same primitives the graph/linter use) ──

    # Raw markdown cross-link targets in the body, in document order (spec §5).
    def links
      Markdown::Links.extract(body)
    end

    # Citation link targets under the `# Citations` section (spec §8), or [].
    def citations
      Markdown::Citations.targets(body)
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
  end
end
