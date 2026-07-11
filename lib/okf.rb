# frozen_string_literal: true

require "erb"
require "fileutils"
require "date"
require "json"
require "optparse"
require "pathname"
require "securerandom"
require "set"
require "time"
require "yaml"

module OKF
  class Error < StandardError
  end

  # Blank in the frontmatter sense: nil, false, an empty/whitespace-only string,
  # or an empty collection. Numbers and other scalars are never blank. The one
  # domain-wide predicate behind "non-empty type" (§9.2) and the recommended-field
  # warnings, kept here so the gem needs no ActiveSupport.
  def self.blank?(value)
    return true if value.nil? || value == false
    return value.strip.empty? if value.is_a?(String)

    value.respond_to?(:empty?) ? value.empty? : false
  end

  require "okf/version"

  # ── kernel: cross-cutting primitives ──
  require "okf/path"

  # ── Markdown: parse structure out of a markdown document (§4/§5/§8) ──
  require "okf/markdown/frontmatter"
  require "okf/markdown/links"
  require "okf/markdown/citations"

  # ── domain: pure representations + analyzers (no disk, no CLI) ──
  require "okf/concept"
  require "okf/bundle"
  require "okf/bundle/graph"
  require "okf/bundle/validator"
  require "okf/bundle/validator/result"
  require "okf/bundle/linter"
  require "okf/bundle/linter/report"
end
