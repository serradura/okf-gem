# frozen_string_literal: true

module OKF
  class Bundle
    # Checks an OKF::Bundle against the OKF v0.1 conformance rules (§9), which has
    # three conditions — all hard errors:
    #
    #   §9.1  every non-reserved file has a parseable YAML frontmatter block;
    #   §9.2  every such block has a non-empty `type`;
    #   §9.3  every index.md/log.md present follows the §6/§7 structure — a nested
    #         index.md has no frontmatter, a root index.md carries only okf_version,
    #         and log.md date headings are ISO `YYYY-MM-DD`.
    #
    # Everything the spec marks as soft guidance is a warning and never makes a
    # bundle non-conformant: missing recommended fields, non-list tags, an
    # unparseable timestamp, and broken cross-links (§5.3), which consumers MUST
    # tolerate. Pure — it reads nothing from disk; it works entirely on the
    # in-memory bundle.
    class Validator
      def self.call(bundle)
        new(bundle).call
      end

      def initialize(bundle)
        @bundle = bundle
        @result = Result.new
      end

      def call
        @existing = @bundle.paths.to_set
        @bundle.concepts.each { |concept| validate_concept(concept) }
        @bundle.reserved.each { |entry| validate_reserved(entry) }
        @bundle.unparseable.each { |entry| validate_unparseable(entry) }
        @result
      end

      private

      # §9.2 (non-empty type) is the only hard error here; the missing recommended
      # fields, non-list tags, and bad timestamp are soft warnings (never
      # non-conformant). A parsed concept is valid UTF-8 by construction.
      def validate_concept(concept)
        @result.count(:concepts)
        @result.add_error(concept.path, "frontmatter must include a non-empty type") if OKF.blank?(concept.type)
        @result.add_warning(concept.path, "frontmatter should include title") if OKF.blank?(concept.title)
        @result.add_warning(concept.path, "frontmatter should include description") if OKF.blank?(concept.description)
        @result.add_warning(concept.path, "tags should be a list") if concept.frontmatter.key?("tags") && !concept.tags.is_a?(Array)
        validate_timestamp(concept.path, concept.timestamp) if concept.frontmatter.key?("timestamp")
        check_links(concept.path, concept.body)
      end

      # §9.1: a concept-position file whose frontmatter did not parse. The message is
      # the ParseError captured at read time.
      def validate_unparseable(entry)
        unless entry.content.valid_encoding?
          @result.add_error(entry.path, "file content is not valid UTF-8")
          return
        end

        @result.count(:concepts)
        @result.add_error(entry.path, entry.error)
        check_links(entry.path, entry.content)
      end

      def validate_reserved(entry)
        unless entry.content.valid_encoding?
          @result.add_error(entry.path, "file content is not valid UTF-8")
          return
        end

        @result.count(File.basename(entry.path) == "index.md" ? :indexes : :logs)
        validate_index(entry.path, entry.content) if File.basename(entry.path) == "index.md"
        validate_log(entry.path, entry.content) if File.basename(entry.path) == "log.md"
        check_links(entry.path, entry.content)
      end

      def validate_index(path, content)
        return unless content.match?(/\A---[ \t]*\n/)

        if path != "index.md"
          @result.add_error(path, "nested index.md must not include frontmatter")
          return
        end

        frontmatter, = Markdown::Frontmatter.parse(content)
        extra_keys = frontmatter.keys - [ "okf_version" ]
        @result.add_error(path, "root index.md frontmatter may only include okf_version") if extra_keys.any?
      rescue Markdown::Frontmatter::ParseError => e
        @result.add_error(path, e.message)
      end

      def validate_log(path, content)
        content.each_line do |line|
          next unless line.start_with?("## ")

          heading = line.sub(/\A## /, "").strip
          next if heading.match?(/\A\d{4}-\d{2}-\d{2}\z/)

          @result.add_error(path, "log.md date headings must use YYYY-MM-DD")
        end
      end

      # Broken bundle-internal links are warnings only (§5.3): the spec requires
      # consumers to tolerate them, so they never make a bundle non-conformant.
      def check_links(path, content)
        Markdown::Links.extract(content).each do |raw|
          resolved = Markdown::Links.resolve(raw, from: path, bundle: @bundle.root)
          next if resolved.nil? || @existing.include?(resolved)

          @result.add_warning(path, "cross-link target not found: `#{raw}` (tolerated under §5.3)")
        end
      end

      # A YAML-parsed Date/Time is temporal by construction (YAML already validated
      # the shape); only a String needs checking, and it may be a full ISO 8601
      # datetime (2026-05-28T14:30:00Z) or a date-only value (2026-05-28).
      def validate_timestamp(path, timestamp)
        return if timestamp.is_a?(Date) || timestamp.is_a?(Time)

        value = timestamp.to_s
        begin
          Time.iso8601(value)
        rescue ArgumentError
          Date.iso8601(value)
        end
      rescue ArgumentError
        @result.add_warning(path, "timestamp should be ISO 8601 parseable")
      end
    end
  end
end
