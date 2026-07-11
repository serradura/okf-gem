# frozen_string_literal: true

module OKF
  # Primitives for parsing structure out of a markdown document — the format layer
  # (§4 frontmatter, §5 links, §8 citations) shared by Concept, Bundle, and the
  # analyzers. Pure string-in/string-out; no disk, no domain knowledge.
  module Markdown
    module Frontmatter
      class ParseError < Error
      end

      FRONTMATTER_PATTERN = /\A---[ \t]*\n(.*?)\n---[ \t]*(?:\n|\z)/m.freeze

      # Psych gained keyword arguments for safe_load in 3.1 (Ruby 2.6); older
      # versions take the permitted classes positionally.
      PSYCH_KEYWORDS = Gem::Version.new(Psych::VERSION) >= Gem::Version.new("3.1.0")

      module_function

      def parse(content)
        text = content.to_s
        raise ParseError, "content is not valid UTF-8" unless text.encoding == Encoding::UTF_8 && text.valid_encoding?

        match = FRONTMATTER_PATTERN.match(text)
        raise ParseError, "missing YAML frontmatter" unless match

        data = load_yaml(match[1])
        raise ParseError, "frontmatter must be a mapping" unless data.nil? || data.is_a?(Hash)

        body = text[match.end(0)..-1] || ""
        [ stringify_keys(data || {}), body.sub(/\A\n/, "") ]
      rescue Psych::SyntaxError => e
        raise ParseError, "invalid YAML frontmatter: #{e.message}"
      end

      def dump(frontmatter, body)
        attrs = stringify_keys(frontmatter || {})
        yaml = YAML.dump(attrs).sub(/\A---[ \t]*\n/, "")
        "---\n#{yaml}---\n\n#{body}"
      end

      def stringify_keys(hash)
        hash.to_h.map { |key, value| [ key.to_s, value ] }.to_h
      end

      def load_yaml(text)
        if PSYCH_KEYWORDS
          YAML.safe_load(text, permitted_classes: [ Date, Time ], aliases: false)
        else
          YAML.safe_load(text, [ Date, Time ], [], false)
        end
      end
    end
  end
end
