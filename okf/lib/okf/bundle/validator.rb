# frozen_string_literal: true

module OKF
  class Bundle
    # Checks an OKF::Bundle against the OKF conformance rules (§11), which has
    # three conditions — all hard errors:
    #
    #   §11 c1  every non-reserved file has a parseable YAML frontmatter block;
    #   §11 c2  every such block has a non-empty `type`;
    #   §11 c3  every index.md/log.md present follows the §8/§9 structure — a nested
    #          index.md has no frontmatter, a root index.md carries only okf_version,
    #          and log.md date headings are ISO `YYYY-MM-DD`.
    #
    # Everything the spec marks as soft guidance is a warning and never makes a
    # bundle non-conformant: missing recommended fields, non-list tags, an
    # unparseable timestamp, broken cross-links (§6.1), and every v0.2 family
    # shape (§5, §10). Pure — it reads nothing from disk; it works entirely on
    # the in-memory bundle.
    #
    # Warnings are machine-readable: each carries a `check:` id and a `source:`
    # naming who states the rule — `:spec` for the SPEC's own words,
    # `:convention` for a shape this gem asks for beyond them. Errors keep their
    # exact two-key shape; consumers already read it.
    class Validator
      # The warnings that state a gem convention rather than a SPEC rule. §5.1
      # gives `usage_count` no type and §10.2 marks only `runtime` REQUIRED;
      # `verified[].by` is REQUIRED-within by analogy with `generated.by`, not
      # by the SPEC's own words. A consumer that wants only the spec-normative
      # warnings filters on `source:` instead of string-matching messages.
      CONVENTION_CHECKS = %i[
        verified_entry_by source_usage_count source_usage_window_shape
        parameter_name executor_resource attester_resource
      ].freeze

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

      # Every warning goes through here so the check id and its source cannot
      # drift apart: the id is the API, the source is derived from one constant.
      #
      # Not `warn`: that name shadows Kernel#warn for every method in the class,
      # so a later `warn "…"` meant for stderr would raise ArgumentError at
      # runtime — a collision neither RuboCop nor the call site can show you.
      def record_warning(path, check, message)
        @result.add_warning(path, message,
          check: check,
          source: CONVENTION_CHECKS.include?(check) ? :convention : :spec)
      end

      # §11.2 (non-empty type) is the only hard error here; the missing
      # recommended fields, non-list tags, and bad timestamp are soft warnings
      # (never non-conformant). A parsed concept is valid UTF-8 by construction.
      def validate_concept(concept)
        @result.count(:concepts)
        @result.add_error(concept.path, "frontmatter must include a non-empty type") if OKF.blank?(concept.type)
        record_warning(concept.path, :recommended_title, "frontmatter should include title") if OKF.blank?(concept.title)
        record_warning(concept.path, :recommended_description, "frontmatter should include description") if OKF.blank?(concept.description)
        record_warning(concept.path, :tags_shape, "tags should be a list") if concept.frontmatter.key?("tags") && !concept.tags.is_a?(Array)
        validate_iso8601(concept.path, :timestamp_format, "timestamp", concept.timestamp) if concept.frontmatter.key?("timestamp")
        validate_families(concept)
        check_links(concept.path, concept.body)
      end

      # ── the v0.2 families (§5, §10) ──────────────────────────────────────────
      #
      # Shape, and only shape: is it a mapping, does the date parse, is the enum
      # value one the spec names. Whether a field is *missing*, *stale* or
      # *unattributed* is curation, and the linter owns it — without that line the
      # two would double-report every family.
      #
      # Every check reads the raw frontmatter key, never the fallback-carrying
      # accessor — otherwise every v0.1 concept would warn about a mapping the
      # §13.1 fallback synthesized, and "a pure v0.1 bundle validates silently"
      # would stop being true. And every check is guarded by `frontmatter.key?`,
      # so absence is never a fault: each family is optional (§5), and a v0.1
      # concept that adopts none is a valid v0.2 concept. All warnings — §11's
      # conformance conditions are only three.
      def validate_families(concept)
        validate_generated(concept)
        validate_verified(concept)
        validate_sources(concept)
        validate_usage_window(concept)
        validate_lifecycle(concept)
        validate_computation(concept)
      end

      def validate_generated(concept)
        return unless concept.frontmatter.key?("generated")

        value = concept.frontmatter["generated"]
        unless value.is_a?(Hash)
          record_warning(concept.path, :generated_shape, "generated should be a mapping")
          return
        end

        generated = Markdown::Frontmatter.stringify_keys(value)
        record_warning(concept.path, :generated_by, "generated should include by") if OKF.blank?(generated["by"])
        validate_iso8601(concept.path, :generated_at_format, "generated.at", generated["at"]) if generated.key?("at")
      end

      # §5.2 permits a list or a single bare mapping; anything else records no
      # verification at all, which is what the warning is about.
      def validate_verified(concept)
        return unless concept.frontmatter.key?("verified")

        value = concept.frontmatter["verified"]
        return validate_verified_entries(concept, [ value ]) if value.is_a?(Hash)
        return validate_verified_entries(concept, value) if value.is_a?(Array)

        record_warning(concept.path, :verified_shape, "verified should be a mapping or a list of mappings")
      end

      def validate_verified_entries(concept, entries)
        entries.each_with_index do |entry, index|
          unless entry.is_a?(Hash)
            record_warning(concept.path, :verified_entry_shape, "verified[#{index}] should be a mapping")
            next
          end

          event = Markdown::Frontmatter.stringify_keys(entry)
          record_warning(concept.path, :verified_entry_by, "verified[#{index}] should include by") if OKF.blank?(event["by"])
          validate_iso8601(concept.path, :verified_entry_at_format, "verified[#{index}].at", event["at"]) if event.key?("at")
        end
      end

      def validate_sources(concept)
        return unless concept.frontmatter.key?("sources")

        value = concept.frontmatter["sources"]
        unless value.is_a?(Array)
          record_warning(concept.path, :sources_shape, "sources should be a list")
          return
        end

        value.each_with_index { |entry, index| validate_source(concept, entry, index) }
      end

      # `resource` is what makes a source addressable, so its absence is the one
      # that matters most; `last_modified` and `usage_count` are the credibility
      # signals with a shape to get wrong, and a per-entry `usage_window`
      # override must be the same mapping the sibling is (§5.1).
      def validate_source(concept, entry, index)
        unless entry.is_a?(Hash)
          record_warning(concept.path, :source_entry_shape, "sources[#{index}] should be a mapping")
          return
        end

        source = Markdown::Frontmatter.stringify_keys(entry)
        record_warning(concept.path, :source_resource, "sources[#{index}] should include resource") if OKF.blank?(source["resource"])
        validate_date(concept.path, :source_last_modified, "sources[#{index}].last_modified", source["last_modified"]) if source.key?("last_modified")
        if source.key?("usage_count") && !source["usage_count"].is_a?(Integer)
          record_warning(concept.path, :source_usage_count, "sources[#{index}].usage_count should be an integer")
        end
        return unless source.key?("usage_window") && !source["usage_window"].is_a?(Hash)

        record_warning(concept.path, :source_usage_window_shape, "sources[#{index}].usage_window should be a mapping")
      end

      def validate_usage_window(concept)
        return unless concept.frontmatter.key?("usage_window")

        value = concept.frontmatter["usage_window"]
        unless value.is_a?(Hash)
          record_warning(concept.path, :usage_window_shape, "usage_window should be a mapping")
          return
        end

        window = Markdown::Frontmatter.stringify_keys(value)
        %w[from to].each { |key| validate_date(concept.path, :usage_window_date, "usage_window.#{key}", window[key]) if window.key?(key) }
      end

      # §5.4 lets a producer use a status outside the three and requires consumers
      # to tolerate it (§4.1), so this is a warning about a vocabulary a consumer
      # keyed to the spec will not understand — never a rejection.
      def validate_lifecycle(concept)
        # fold_status, not effective_status: the §5.4 default belongs to a
        # concept that never declared the key, and applying it here read a
        # blank `status: ""` as `stable` — so the one value §5.4 names nowhere
        # was the one value that never warned.
        if concept.frontmatter.key?("status") && !Concept::STATUSES.include?(Concept.fold_status(concept.declared_status))
          record_warning(concept.path, :status_vocabulary, "status should be one of #{Concept::STATUSES.join(", ")}")
        end

        validate_date(concept.path, :stale_after_format, "stale_after", concept.stale_after) if concept.frontmatter.key?("stale_after")
      end

      # §10.2 makes `runtime` REQUIRED for an Attested Computation — but §11's
      # conformance conditions are only three, so its absence is a warning here
      # and the linter owns the rest of the contract (one home per finding:
      # shape and REQUIRED-within are the validator's side).
      def validate_computation(concept)
        if concept.attested_computation? && OKF.blank?(concept.frontmatter["runtime"])
          record_warning(concept.path, :runtime_required, "runtime is required for an Attested Computation")
        end

        validate_parameters(concept)
        validate_contract_mapping(concept, "executor", :executor_shape, :executor_resource)
        validate_contract_mapping(concept, "attester", :attester_shape, :attester_resource)
      end

      def validate_parameters(concept)
        return unless concept.frontmatter.key?("parameters")

        value = concept.frontmatter["parameters"]
        unless value.is_a?(Array)
          record_warning(concept.path, :parameters_shape, "parameters should be a list")
          return
        end

        value.each_with_index do |entry, index|
          unless entry.is_a?(Hash)
            record_warning(concept.path, :parameter_entry_shape, "parameters[#{index}] should be a mapping")
            next
          end

          parameter = Markdown::Frontmatter.stringify_keys(entry)
          record_warning(concept.path, :parameter_name, "parameters[#{index}] should include name") if OKF.blank?(parameter["name"])
        end
      end

      def validate_contract_mapping(concept, key, shape_check, resource_check)
        return unless concept.frontmatter.key?(key)

        value = concept.frontmatter[key]
        unless value.is_a?(Hash)
          record_warning(concept.path, shape_check, "#{key} should be a mapping")
          return
        end

        contract = Markdown::Frontmatter.stringify_keys(value)
        record_warning(concept.path, resource_check, "#{key} should include resource") if OKF.blank?(contract["resource"])
      end

      # §11.1: a concept-position file whose frontmatter did not parse. The message is
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
        validate_okf_version(path, frontmatter["okf_version"]) if frontmatter.key?("okf_version")
      rescue Markdown::Frontmatter::ParseError => e
        @result.add_error(path, e.message)
      end

      # §12 asks a consumer to attempt best-effort consumption rather than
      # refuse, so an unknown version is a warning and the bundle is read
      # anyway; an absent one is the sanctioned MAY-not-declare case and never
      # warns. Compared after `to_s.strip`: an unquoted `okf_version: 0.2` is a
      # Psych Float, and warning on a correctly-declared bundle is the bug.
      def validate_okf_version(path, declared)
        return if OKF.blank?(declared) || Concept::KNOWN_SPEC_VERSIONS.include?(declared.to_s.strip)

        record_warning(path, :okf_version_unknown,
          "okf_version `#{declared}` is not a version this gem knows (read best-effort under §12)")
      end

      def validate_log(path, content)
        content.each_line do |line|
          next unless line.start_with?("## ")

          heading = line.sub(/\A## /, "").strip
          next if heading.match?(/\A\d{4}-\d{2}-\d{2}\z/)

          @result.add_error(path, "log.md date headings must use YYYY-MM-DD")
        end
      end

      # Broken bundle-internal links are warnings only (§6.1): the spec requires
      # consumers to tolerate them, so they never make a bundle non-conformant.
      def check_links(path, content)
        Markdown::Links.extract(content).each do |raw|
          resolved = Markdown::Links.resolve(raw, from: path, bundle: @bundle.root)
          next if resolved.nil? || @existing.include?(resolved)

          record_warning(path, :broken_link, "cross-link target not found: `#{raw}` (tolerated under §6.1)")
        end
      end

      # A YAML-parsed Date/Time is temporal by construction (YAML already validated
      # the shape); only a String needs checking, and it may be a full ISO 8601
      # datetime (2026-05-28T14:30:00Z) or a date-only value (2026-05-28).
      #
      # `field` names what is being checked: one rule about what a moment looks
      # like serves the legacy `timestamp`, `generated.at` and every
      # `verified[].at`, reported against whichever field carried it.
      def validate_iso8601(path, check, field, value)
        return if value.is_a?(Date) || value.is_a?(Time)

        string = value.to_s
        begin
          Time.iso8601(string)
        rescue ArgumentError
          Date.iso8601(string)
        end
      rescue ArgumentError
        record_warning(path, check, "#{field} should be ISO 8601 parseable")
      end

      # §5.1/§5.5 want a calendar day, not a moment: `last_modified`,
      # `usage_window.from`/`to` and `stale_after` are all YYYY-MM-DD. A YAML Date
      # is one by construction; a Time is not — the extra precision means the
      # producer wrote something else.
      def validate_date(path, check, field, value)
        return if value.is_a?(Date) && !value.is_a?(DateTime)

        Date.iso8601(value.to_s)
        record_warning(path, check, "#{field} should be a YYYY-MM-DD date") unless value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      rescue ArgumentError
        record_warning(path, check, "#{field} should be a YYYY-MM-DD date")
      end
    end
  end
end
