# frozen_string_literal: true

require "test_helper"

# The bundle carries this gem's structural documentation and its catalogue of
# what the program already answers, so it is code-derived knowledge — the kind
# that rots in silence. `AGENTS.md` used to hold a hand-maintained Map of
# `lib/**`, and nothing checked it: a file could arrive, move or leave and the
# Map would keep reading plausibly. Moving that Map into `.okf/structure/` only
# relocates the problem unless something fails when the two disagree.
#
# So this is the pin: the code is the truth, the bundle is the claim, and a
# mismatch in either direction is a failure.
#
#   - every `.rb` under `lib/` is named by **exactly one** structure concept,
#     so ownership is single and a reader knows where to look
#   - every path a structure concept names exists, so a delete cannot leave a
#     concept describing something that is gone
#   - the view catalogue agrees with `App::TABS`, which is the whole point of a
#     catalogue: an agent that reads it must not go looking for a seventh view,
#     or miss one of the six
class OKF::TUI::BundleCatalogTest < OKF::TUI::TestCase
  GEM_ROOT = File.expand_path("../..", __dir__)
  BUNDLE = File.join(GEM_ROOT, ".okf")
  STRUCTURE = File.join(BUNDLE, "structure")

  test "the bundle ships a structure area — the Map's home" do
    assert File.directory?(STRUCTURE),
      "#{rel(STRUCTURE)} is missing: the structural layer is the bundle's, not AGENTS.md's"
    refute_empty structure_concepts, "#{rel(STRUCTURE)} carries no concepts"
  end

  test "every lib file is named by exactly one structure concept" do
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

  test "every path a structure concept names is a file that exists" do
    dangling = structure_concepts.flat_map do |concept|
      cited_paths(concept).reject { |path| File.exist?(File.join(GEM_ROOT, path)) }
                          .map { |path| "#{File.basename(concept)} -> #{path}" }
    end

    assert_empty dangling,
      "the bundle describes files that are not there; a move or a delete has to travel to the concept"
  end

  test "the view catalogue agrees with the tab bar" do
    catalog = File.join(BUNDLE, "capabilities", "views.md")
    assert File.file?(catalog), "#{rel(catalog)} is missing: the view catalogue is the bundle's"

    declared = OKF::TUI::App::TABS.map { |tab| tab[0].to_s }.sort
    listed = File.read(catalog, encoding: "UTF-8").scan(/^\| `([a-z]+)`/).flatten.uniq.sort
    assert_equal declared, listed,
      "#{rel(catalog)} and OKF::TUI::App::TABS disagree about which views exist"
  end

  private

  # Paths as the concepts spell them: relative to the gem root, which is what a
  # reader standing in `gems/okf-tui/` can paste into an editor. `Dir.glob` takes
  # no `base:` on this gem's 2.4 floor, hence the chdir.
  def lib_files
    @lib_files ||= Dir.chdir(GEM_ROOT) { Dir.glob("lib/**/*.rb").sort }
  end

  def structure_concepts
    @structure_concepts ||=
      Dir.glob(File.join(STRUCTURE, "*.md")).reject { |f| File.basename(f) == "index.md" }.sort
  end

  # A concept names a file when the path appears in its text. Bounded by a
  # non-path character on the right so `lib/okf/tui.rb` is not read as a mention
  # of a `lib/okf/tui.rb.bak`, and so `tui/ui.rb` never matches inside
  # `tui/ui_extra.rb`.
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

  def rel(path)
    path.sub("#{GEM_ROOT}/", "")
  end
end
