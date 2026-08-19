# frozen_string_literal: true

require "test_helper"

# The bundle is this gem's structural documentation, so it is code-derived
# knowledge — the kind that rots in silence. `AGENTS.md` used to carry a
# hand-maintained Map of `lib/**`, and nothing checked it: a file could arrive,
# move or leave and the Map would keep reading plausibly. Moving that Map into
# `.okf/structure/` only relocates the problem unless something fails when the
# two disagree.
#
# So this is the pin, in the same spirit as the kernel's `boundary_test.rb` and
# its `cli.rb` require-order test: the tree is the truth, the bundle is the
# claim, and a mismatch in either direction is a failure.
#
#   - every `.rb` under `lib/` is named by **exactly one** structure concept,
#     so ownership is single and a reader knows where to look
#   - every path a structure concept names exists, so a deleted file cannot
#     leave a concept describing something that is gone
#   - every tool the server defines appears in the capabilities catalog, which
#     is the whole point of the catalog: an agent that reads it must not go
#     looking for a fifteenth tool, or miss one of the fourteen
class BundleCatalogTest < OKF::TestCase
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

    unowned = owners.select { |(_, cs)| cs.empty? }.map(&:first)
    assert_empty unowned,
      "no concept in #{rel(STRUCTURE)} names #{unowned.join(", ")} — a new file needs a line in " \
      "the concept that owns its layer, or a concept of its own"

    shared = owners.select { |(_, cs)| cs.size > 1 }
    assert_empty shared.map { |(f, cs)| "#{f} (#{cs.map { |c| File.basename(c) }.join(", ")})" },
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

  test "every tool the server defines is in the capabilities catalog" do
    catalog = File.join(BUNDLE, "capabilities", "tools.md")
    assert File.file?(catalog), "#{rel(catalog)} is missing: the tool catalog is the bundle's"

    text = File.read(catalog, encoding: "UTF-8")
    missing = defined_tools.reject { |name| text.include?("`#{name}`") }
    assert_empty missing, "#{rel(catalog)} does not list #{missing.join(", ")}"

    listed = text.scan(/^\| `([a-z_]+)`/).flatten
    assert_equal defined_tools.sort, listed.sort,
      "the catalog's tool rows and the tools server.rb defines disagree"
  end

  private

  # Paths as the concepts spell them: relative to the gem root, which is what a
  # reader standing in `gems/okf-mcp/` can paste into an editor.
  def lib_files
    @lib_files ||= Dir.glob("lib/**/*.rb", base: GEM_ROOT).sort
  end

  def structure_concepts
    @structure_concepts ||= Dir.glob(File.join(STRUCTURE, "*.md")).reject { |f| File.basename(f) == "index.md" }.sort
  end

  # A concept names a file when the path appears in its text. Bounded by a
  # non-path character on the right so `lib/okf/mcp.rb` is not read as a mention
  # of a `lib/okf/mcp.rb.bak`, and so `mcp/http.rb` never matches inside
  # `mcp/http_extra.rb`.
  def names?(concept, path)
    body(concept).match?(/#{Regexp.escape(path)}(?![\w.\/-])/)
  end

  def cited_paths(concept)
    body(concept).scan(%r{\blib/[\w./-]*\.(?:rb|md)\b}).uniq
  end

  # `encoding: "UTF-8"` is not decoration. `File.read` uses
  # `Encoding.default_external`, which is US-ASCII when LANG is unset — the
  # state the documented Ruby 2.7 Docker floor run is in — and the very next
  # `match?` then raises `ArgumentError: invalid byte sequence` on the first em
  # dash in a concept. Read the bytes as what they are.
  def body(concept)
    (@bodies ||= {})[concept] ||= File.read(concept, encoding: "UTF-8")
  end

  def defined_tools
    @defined_tools ||= File.read(File.join(GEM_ROOT, "lib/okf/mcp/server.rb"), encoding: "UTF-8")
                           .scan(/define_tool\(\s*\n\s*name: "([a-z_]+)"/).flatten.sort
  end

  def rel(path)
    path.sub("#{GEM_ROOT}/", "")
  end
end
