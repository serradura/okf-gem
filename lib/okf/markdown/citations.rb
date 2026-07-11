# frozen_string_literal: true

module OKF
  module Markdown
    # Parses the conventional `# Citations` section of a concept body (spec §8): the
    # block of external sources listed at the bottom of a document. Pure and
    # fence-aware, mirroring Links; it reuses Links.extract to pull the citation link
    # targets so citations and cross-links agree on what counts as a link.
    module Citations
      # A markdown ATX heading line: 1–6 `#`, whitespace, then the heading text.
      HEADING = /\A(\#{1,6})\s+(.*?)\s*\z/.freeze
      CITATIONS = /\ACitations\z/i.freeze

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

      # Citation link targets within the `# Citations` section (empty when absent).
      def targets(body)
        Links.extract(section(body).to_s)
      end
    end
  end
end
