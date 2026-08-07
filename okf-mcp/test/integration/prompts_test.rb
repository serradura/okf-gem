# frozen_string_literal: true

require_relative "mcp_integration_case"
require "okf/skill"

# The skill's playbooks over the wire: four prompts, each serving the
# corresponding playbook read live from the installed okf gem's canonical
# skill tree — the single-copy rule, so they version with the kernel.
class PromptsTest < MCPIntegrationCase
  test "the four playbook prompts are listed" do
    server = mcp_server(fixture("knowledge"))
    names = rpc(server, "prompts/list").dig("result", "prompts").map { |prompt| prompt["name"] }
    assert_equal %w[okf-consume okf-search okf-maintain okf-curate], names
  end

  test "a prompt serves its playbook verbatim from the kernel's skill tree" do
    server = mcp_server(fixture("knowledge"))
    result = rpc(server, "prompts/get", name: "okf-search").fetch("result")
    text = result.dig("messages", 0, "content", "text")
    canonical = File.read(File.join(OKF::Skill::ASSETS, "playbooks", "search.md"), encoding: "UTF-8")
    assert_equal canonical, text
  end
end
