# frozen_string_literal: true

require_relative "../mcp_integration_case"

module AcrossBundles
  # lint takes one bundle; a group slug is refused outright — the
  # second-bundle rule by another spelling. Answering for a group's first
  # member would be a silent wrong answer, so the boundary is guarded here,
  # not assumed.
  class LintTest < MCPIntegrationCase
    test "refuses a group slug, naming the one tool that takes a set" do
      with_registry("knowledge", "notes") do |registry|
        registry.set_group("docs", %w[knowledge notes])
        result = call_tool(mcp_server, "lint", bundle: "docs")
        assert result.error?
        assert_match(/@docs names a group of 2 members; only `search` takes a group/, result.text)
      end
    end
  end
end
