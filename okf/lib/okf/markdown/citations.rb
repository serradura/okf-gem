# frozen_string_literal: true

module OKF
  module Markdown
    # Parses the retired `# Citations` section of a v0.1 concept body (§13.1): the
    # block of external sources listed at the bottom of a document. Pure and
    # fence-aware, mirroring Links; it reuses Links.extract to pull the citation link
    # targets so citations and cross-links agree on what counts as a link.
    module Citations
      # A markdown ATX heading line: 1–6 `#`, whitespace, then the heading text.
      HEADING = /\A(\#{1,6})\s+(.*?)\s*\z/.freeze
      CITATIONS = /\ACitations\z/i.freeze
      # A list item (or lone line) that is only a URL — the v0.1 spelling the
      # v0.2 SPEC's own Appendix A uses — and the same item written as an
      # autolink. Both are citations with no text to lift into a title.
      URL_ITEM = %r{\A(?:[-*+]\s+)?([a-z][a-z0-9+.-]*://\S+)\z}i.freeze
      AUTOLINK_ITEM = /\A(?:[-*+]\s+)?<([a-z][a-z0-9+.-]*:[^>\s]+)>\z/i.freeze

      module_function

      # The body text under a `# Citations` heading, up to the next heading at the
      # same or higher level, or nil when there is no Citations section.
      def section(body)
        lines = []
        level = nil
        in_fence = false
        body.to_s.each_line do |line|
          if Links::FENCE.match?(line.strip)
            in_fence = !in_fence
            lines << line unless level.nil?
            next
          end

          heading = in_fence ? nil : HEADING.match(line.strip)
          if level.nil?
            next unless heading && CITATIONS.match?(heading[2])

            level = heading[1].length
          elsif heading && heading[1].length <= level
            break
          else
            lines << line
          end
        end
        lines.join unless level.nil?
      end

      # The citation entries as { text:, target: } pairs, in document order —
      # what Concept#sources lifts into { "title", "resource" } mappings. Three
      # item forms (§13.1): labelled links
      # carry their text; bare-URL and autolink items have none; a
      # reference-style citation still yields its target through Links.extract.
      def entries(body)
        text = section(body).to_s
        found = []
        Links.each_prose_line(text) do |line|
          item = line.strip
          match = AUTOLINK_ITEM.match(item) || URL_ITEM.match(item)
          if match
            found << { text: "", target: match[1] }
            next
          end

          line.scan(Links::INLINE_LINK) do |label, target|
            found << { text: label.to_s.strip, target: target }
          end
        end
        covered = found.map { |entry| entry[:target] }
        extra = Links.extract(text).reject { |target| covered.include?(target) }
        found + extra.map { |target| { text: "", target: target } }
      end
    end
  end
end
