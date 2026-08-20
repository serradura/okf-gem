# frozen_string_literal: true

require "set"

module OKF
  class Bundle
    # The §6.3 inventory, pure: every file under `references/` — handed in by
    # the shell as +files+, because the reader models concepts and this model
    # performs no disk access — with which concepts cite each one through the
    # §6.2 path-valued fields (resource, sources[].resource, computation,
    # executor.resource, attester.resource), plus the pointers into
    # `references/` that resolve to nothing.
    #
    # The bare-path trap is what the dangling list exists to surface: §6.2
    # resolves a bare path relative to the concept, so `references/x` works
    # from the bundle root and silently misses one directory down. When the
    # missed spelling would have hit with a leading slash, the entry says so.
    #
    # Scope is the folder, by design. §6.3 is "a naming convention, not a
    # requirement", and a computation stored beside its concept is legal —
    # and deliberately not this inventory's to list.
    class References
      def self.build(bundle, files:)
        new(bundle, files: files)
      end

      # Files under references/, sorted by path, each
      # { path:, dir:, kind:, referenced_by: [ { id:, field: } ] } — kind is
      # "concept" when the file is a parsed concept (§6.3 allows both), "file"
      # otherwise. referenced_by is ordered by citing concept id.
      attr_reader :entries

      # Pointers into references/ that resolve to no file, ordered by concept
      # id then field position, each { id:, field:, raw:, resolved:, hint: } —
      # hint names the leading-slash fix when the bare spelling exists at the
      # root, nil otherwise.
      attr_reader :dangling

      def initialize(bundle, files:)
        @bundle = bundle
        @files = files.sort
        @existing = @files.to_set
        build!
      end

      private

      def build!
        concept_paths = @bundle.concepts.to_set(&:path)
        cited = {}
        @dangling = []

        @bundle.concepts.sort_by(&:id).each do |concept|
          path_fields(concept).each do |field, raw|
            target = Markdown::Links.resolve_path(raw, from: concept.path, bundle: @bundle.root)
            next if target.nil? # external, empty, or a directory — not a file pointer

            if @existing.include?(target)
              (cited[target] ||= []) << { id: concept.id, field: field }
            elsif under_references?(target) || bare_references?(raw)
              @dangling << dangling_row(concept, field, raw, target)
            end
          end
        end

        @entries = @files.map do |path|
          { path: path, dir: File.dirname(path),
            kind: concept_paths.include?(path) ? "concept" : "file",
            referenced_by: cited[path] || [] }
        end
      end

      # Every §6.2 path-valued field this concept carries, as
      # [ field-label, raw ] pairs. sources includes §13.1's lifted Citations —
      # when the fallback is a concept's provenance, its pointers are too.
      def path_fields(concept)
        fields = [
          [ "resource", concept.frontmatter["resource"] ],
          [ "computation", concept.computation ],
          [ "executor.resource", concept.executor && concept.executor["resource"] ],
          [ "attester.resource", concept.attester && concept.attester["resource"] ]
        ]
        concept.sources.each_with_index do |source, index|
          fields << [ "sources[#{index}].resource", source["resource"] ]
        end
        fields.reject { |_field, raw| OKF.blank?(raw) }
      end

      def under_references?(path)
        path.to_s.start_with?("references/")
      end

      # The bare spelling of the trap: a raw that *names* references/ without
      # the leading slash, which §6.2 resolves relative to the concept. From a
      # subdirectory the resolved path leaves references/, so the target check
      # above no longer sees it — the raw is what still does.
      def bare_references?(raw)
        raw.to_s.split("#", 2).first.to_s.start_with?("references/")
      end

      def dangling_row(concept, field, raw, target)
        bare = raw.to_s.split("#", 2).first.to_s
        hint = nil
        if !bare.start_with?("/") && bare != target && @existing.include?(bare)
          hint = "/#{bare} exists — missing leading slash?"
        end
        { id: concept.id, field: field, raw: raw.to_s, resolved: target, hint: hint }
      end
    end
  end
end
