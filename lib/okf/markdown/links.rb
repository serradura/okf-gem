# frozen_string_literal: true

module OKF
  module Markdown
    # Markdown cross-link extraction and resolution — the single source of truth for
    # "which concepts does this body point at". Shared by OKF::Bundle::Graph (to build edges)
    # and OKF::Bundle::Validator (to warn on broken cross-links, §5.3), so both agree on what
    # counts as a link and where it resolves.
    module Links
      FENCE = /\A(```|~~~)/.freeze
      # Inline code span: a run of N backticks, the shortest content (which may hold
      # shorter backtick runs, per CommonMark), then a matching run of N backticks.
      # Links inside inline code render as literal text, not edges, so these are
      # blanked before scanning — the inline analogue of FENCE.
      CODE_SPAN = /(`+).*?\1/.freeze
      # Inline link [text](target) or [text](target "title"); (?<!!) skips images.
      INLINE_LINK = /(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/.freeze
      # Reference-style use: full [text][label] or collapsed [label][]; (?<!!) skips
      # images. group 1 = text/label, group 2 = the explicit label (empty if collapsed).
      REFERENCE_LINK = /(?<!!)\[([^\]]*)\]\[([^\]]*)\]/.freeze
      # Reference definition: [label]: target  (optionally followed by a "title").
      DEFINITION = /\A[ \t]{0,3}\[([^\]]+)\]:[ \t]*(\S+)/.freeze
      SCHEME = %r{\A[a-z][a-z0-9+.-]*://}.freeze

      module_function

      # Raw link targets in +body+, in document order, skipping fenced code blocks
      # and image links. Handles both inline links and standard reference-style links
      # (resolving [text][label] against its [label]: target definition). Targets
      # keep any +#anchor+ — {resolve} strips it.
      def extract(body)
        text = body.to_s
        definitions = reference_definitions(text)
        found = []
        each_prose_line(text) do |line|
          found.concat(line.scan(INLINE_LINK).flatten)
          line.scan(REFERENCE_LINK).each do |label, explicit|
            key = (explicit.empty? ? label : explicit).strip.downcase
            target = definitions[key]
            found << target if target
          end
        end
        found
      end

      # Map every reference definition (+[label]: target+) to its target, keyed by
      # the lowercased label. Definitions may appear anywhere, so they are collected
      # before uses are resolved.
      def reference_definitions(text)
        definitions = {}
        each_prose_line(text) do |line|
          match = DEFINITION.match(line)
          definitions[match[1].strip.downcase] = match[2] if match
        end
        definitions
      end

      # Yield each line outside a fenced code block, with inline code spans blanked.
      # Both exclusions mirror the rendered document: fenced and inline code are
      # literal text, so a link written inside them is not a cross-link.
      def each_prose_line(text)
        in_fence = false
        text.each_line do |line|
          if FENCE.match?(line.strip)
            in_fence = !in_fence
            next
          end
          yield line.gsub(CODE_SPAN, " ") unless in_fence
        end
      end

      # Resolve a raw link target to a bundle-relative +.md+ path, or +nil+ when the
      # target is not an in-scope markdown cross-link (external scheme, mailto,
      # non-+.md+, directory, or empty). A relative link that escapes the bundle root
      # is returned verbatim, so the validator can flag it "not found" and the graph
      # can drop it.
      #
      # @param from   [String] bundle-relative path of the source file, e.g. "features/x.md"
      # @param bundle [String] path to the bundle root
      def resolve(raw, from:, bundle:)
        target = raw.to_s.split("#", 2).first.to_s
        return nil if target.empty? || target.end_with?("/")
        return nil if target.match?(SCHEME) || target.start_with?("mailto:")
        return nil unless target.end_with?(".md")
        return target.sub(%r{\A/+}, "") if target.start_with?("/")

        bundle_abs = File.expand_path(bundle)
        source_dir = File.dirname(File.expand_path(from, bundle_abs))
        candidate = File.expand_path(target, source_dir)
        if candidate == bundle_abs || candidate.start_with?("#{bundle_abs}/")
          Pathname.new(candidate).relative_path_from(Pathname.new(bundle_abs)).to_s
        else
          target
        end
      end
    end
  end
end
