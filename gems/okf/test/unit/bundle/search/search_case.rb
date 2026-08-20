# frozen_string_literal: true

require "test_helper"
require "okf"

# Shared base for the search unit tests that came in with the engine seam: the
# router (routing_test.rb) and the per-engine conformance suite
# (engine_conformance.rb). Both build bundles out of thin in-memory concepts, so
# the fixtures stay readable inside the test that uses them.
#
# `search_test.rb` keeps its own copy of #concept deliberately: it predates the
# seam, and leaving it untouched is what makes "every existing search test passes
# unedited" a proof rather than a claim.
class SearchCase < OKF::TestCase
  private

  def concept(path, type: "Note", title: nil, description: nil, tags: nil, body: "")
    frontmatter = { "type" => type }
    frontmatter["title"] = title if title
    frontmatter["description"] = description if description
    frontmatter["tags"] = tags if tags
    OKF::Concept.new(path: "#{path}.md", frontmatter: frontmatter, body: body)
  end

  def bundle(*concepts)
    OKF::Bundle.new(concepts: concepts)
  end
end
