# frozen_string_literal: true

require "test_helper"

# The bundle carries this gem's structural documentation and its catalogue of
# what the code already answers, so it is code-derived knowledge — the kind
# that rots in silence. `AGENTS.md` used to hold a hand-maintained Map of
# `lib/**`, and nothing checked it: a file could arrive, move or leave and the
# Map would keep reading plausibly. Moving that Map into `.okf/structure/` only
# relocates the problem unless something fails when the two disagree.
#
# So this is the pin, in the same spirit as `closure_grammar_test.rb` and the
# `READERS` sweep in `cli_test.rb`: the code is the truth, the bundle is the
# claim, and a mismatch in either direction is a failure.
#
#   - every `.rb` under `lib/` is named by **exactly one** structure concept,
#     so ownership is single and a reader knows where to look
#   - every path a structure concept names exists, so a delete cannot leave a
#     concept describing something that is gone
#   - the verb and check catalogues agree with `CLI::USAGE` and `HOOK_NAMES`,
#     which is the whole point of a catalogue: an agent that reads it must not
#     go looking for a seventeenth verb, or miss one of the nine checks
class OKF::Pro::BundleCatalogTest < OKF::Pro::TestCase
  GEM_ROOT = File.expand_path("../..", __dir__)
  BUNDLE = File.join(GEM_ROOT, ".okf")
  STRUCTURE = File.join(BUNDLE, "structure")
  CAPABILITIES = File.join(BUNDLE, "capabilities")

  def test_the_bundle_ships_a_structure_area
    assert File.directory?(STRUCTURE),
      "#{rel(STRUCTURE)} is missing: the structural layer is the bundle's, not AGENTS.md's"
    refute_empty structure_concepts, "#{rel(STRUCTURE)} carries no concepts"
  end

  def test_every_lib_file_is_named_by_exactly_one_structure_concept
    owners = lib_files.map { |file| [ file, structure_concepts.select { |c| names?(c, file) } ] }

    unowned = owners.select { |pair| pair[1].empty? }.map { |pair| pair[0] }
    assert_empty unowned,
      "no concept in #{rel(STRUCTURE)} names #{unowned.join(", ")} — a new file needs a line in " \
      "the concept that owns its layer, or a concept of its own"

    shared = owners.select { |pair| pair[1].size > 1 }
                   .map { |pair| "#{pair[0]} (#{pair[1].map { |c| File.basename(c) }.join(", ")})" }
    assert_empty shared,
      "these files are named by more than one structure concept, so no single concept owns them"
  end

  def test_every_path_a_structure_concept_names_is_a_file_that_exists
    dangling = structure_concepts.flat_map do |concept|
      cited_paths(concept).reject { |path| File.exist?(File.join(GEM_ROOT, path)) }
                          .map { |path| "#{File.basename(concept)} -> #{path}" }
    end

    assert_empty dangling,
      "the bundle describes files that are not there; a move or a delete has to travel to the concept"
  end

  def test_the_verb_catalogue_agrees_with_the_usage_table
    catalog = File.join(CAPABILITIES, "verbs.md")
    assert File.file?(catalog), "#{rel(catalog)} is missing: the verb catalogue is the bundle's"

    declared = OKF::Pro::CLI::USAGE.map { |row| row[0] }.sort
    assert_equal declared, table_keys(catalog),
      "#{rel(catalog)} and OKF::Pro::CLI::USAGE disagree about which verbs exist"
  end

  def test_the_check_catalogue_agrees_with_the_hook_door
    catalog = File.join(CAPABILITIES, "checks.md")
    assert File.file?(catalog), "#{rel(catalog)} is missing: the check catalogue is the bundle's"

    assert_equal OKF::Pro::CLI::HOOK_NAMES.sort, table_keys(catalog),
      "#{rel(catalog)} and OKF::Pro::CLI::HOOK_NAMES disagree about what the hook door accepts"
  end

  private

  # Paths as the concepts spell them: relative to the gem root, which is what a
  # reader standing in `gems/okf-pro/` can paste into an editor. `Dir.glob` takes
  # no `base:` on this gem's 2.4 floor, hence the chdir.
  def lib_files
    @lib_files ||= Dir.chdir(GEM_ROOT) { Dir.glob("lib/**/*.rb").sort }
  end

  def structure_concepts
    @structure_concepts ||=
      Dir.glob(File.join(STRUCTURE, "*.md")).reject { |f| File.basename(f) == "index.md" }.sort
  end

  # A concept names a file when the path appears in its text. Bounded by a
  # non-path character on the right so `lib/okf/pro/board.rb` is not read as a
  # mention of a `lib/okf/pro/board.rb.bak`, and so `pro/log.rb` never matches
  # inside `pro/log_extra.rb`.
  def names?(concept, path)
    body(concept).match?(/#{Regexp.escape(path)}(?![\w.\/-])/)
  end

  def cited_paths(concept)
    body(concept).scan(%r{\blib/[\w./-]*\.(?:rb|md)\b}).uniq
  end

  # `encoding: "UTF-8"` is not decoration. `File.read` uses
  # `Encoding.default_external`, which is US-ASCII when LANG is unset — the
  # state the documented Ruby 2.4 Docker floor run is in — and the very next
  # `match?` then raises `ArgumentError: invalid byte sequence` on the first em
  # dash in a concept. Read the bytes as what they are.
  def body(concept)
    (@bodies ||= {})[concept] ||= File.read(concept, encoding: "UTF-8")
  end

  # The first column of every markdown table row that opens with a code span.
  # `uniq` because a catalogue may list the same verb twice — once in the main
  # table, once in the flags table — and the second list is a subset by
  # construction.
  def table_keys(path)
    File.read(path, encoding: "UTF-8").scan(/^\| `([a-z][a-z-]*)`/).flatten.uniq.sort
  end

  def rel(path)
    path.sub("#{GEM_ROOT}/", "")
  end
end
