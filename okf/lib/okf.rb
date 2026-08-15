# frozen_string_literal: true

require "erb"
require "fileutils"
require "date"
require "json"
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
  # domain-wide predicate behind "non-empty type" (§11 cond. 2) and the recommended-field
  # warnings, kept here so the gem needs no ActiveSupport.
  def self.blank?(value)
    return true if value.nil? || value == false
    return value.strip.empty? if value.is_a?(String)

    value.respond_to?(:empty?) ? value.empty? : false
  end

  # A temporal value as ISO 8601 — the one serialization rule for
  # generated_at/stale_after, shared by the catalog row and /node/meta so the
  # served and baked pages cannot drift over one concept's dates. YAML hands
  # over a Date or a Time for an unquoted value (whose default to_s is not
  # ISO); a String passes through; a degenerate value serializes as its
  # string, never as raw structure.
  def self.iso8601(value)
    return nil if value.nil?

    value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
  end

  # The directory a concept lives in, derived from its §2 id: the id *is* the
  # path minus `.md`, so putting the suffix back and taking the dirname is the
  # definition rather than a parse of it. One home for it because three views
  # answer with a `dir` — the catalog, the search rows, the linter's per-directory
  # checks — and a rule spelled three times is three things to keep in step.
  def self.dir_of(id)
    File.dirname("#{id}.md")
  end

  require "okf/version"

  # The OKF spec version this gem targets — one declaration behind the validate
  # header and its help row, so the version a bundle is judged against cannot
  # be stated two ways. The gem still *reads* v0.1 (§13.1); this is what it
  # validates for. Known readable versions: Concept::KNOWN_SPEC_VERSIONS.
  SPEC_VERSION = "0.2"

  # ── kernel: cross-cutting primitives ──
  require "okf/path"
  require "okf/safe_read"

  # ── Markdown: parse structure out of a markdown document (§4/§6/§5.1) ──
  require "okf/markdown/frontmatter"
  require "okf/markdown/links"
  require "okf/markdown/citations"

  # ── domain: pure representations + analyzers (no disk, no CLI) ──
  require "okf/concept"
  require "okf/bundle"
  require "okf/bundle/graph"
  require "okf/bundle/references"
  require "okf/bundle/row_filter"
  require "okf/bundle/skeleton"
  require "okf/bundle/search"
  # These two lines ARE the engine preference order. Each engine registers itself
  # at load, `Search.engines` is registration order, and the router walks it after
  # putting DEFAULT_ENGINE first — so reordering these requires reorders which
  # engine answers a query two engines could both answer. `loading_test.rb` pins
  # the result (`[:index, :scan]`) so the coupling cannot drift unnoticed, but the
  # coupling is here, not there.
  require "okf/bundle/search/index"
  require "okf/bundle/search/scan"
  require "okf/bundle/validator"
  require "okf/bundle/validator/result"
  require "okf/bundle/linter"
  require "okf/bundle/linter/report"

  # ── shell: everything that touches the outside world ──
  require "okf/concept/file"
  require "okf/bundle/reader"
  require "okf/bundle/writer"
  require "okf/bundle/folder"
end
