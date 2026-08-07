# frozen_string_literal: true

require_relative "mcp_integration_case"
require "okf/skill"

# The skill's playbooks over the wire: one prompt per playbook, each served
# live from the installed okf gem's canonical skill tree — the single-copy
# rule, so they version with the kernel.
class PromptsTest < MCPIntegrationCase
  # SKILL.md's own Commands table order, minus doctor. Matching it is the
  # point: the two surfaces offer the same verbs in the same sequence, so
  # nobody has to learn a second ordering.
  EXPECTED = %w[okf-menu okf-search okf-produce okf-migrate okf-maintain okf-refine okf-consume okf-curate].freeze

  test "every playbook but doctor is offered as a prompt" do
    server = mcp_server(fixture("knowledge"))
    names = rpc(server, "prompts/list").dig("result", "prompts").map { |prompt| prompt["name"] }
    assert_equal EXPECTED, names
  end

  # doctor installs the CLI and verifies a Ruby. If this server is answering,
  # the gem is installed — the playbook's whole premise is already false.
  test "doctor is not offered, because reaching this server disproves its premise" do
    server = mcp_server(fixture("knowledge"))
    names = rpc(server, "prompts/list").dig("result", "prompts").map { |prompt| prompt["name"] }
    refute_includes names, "okf-doctor"

    response = rpc(server, "prompts/get", name: "okf-doctor")
    assert response["error"], "an unknown prompt must be a protocol error, not an empty result"
  end

  test "a prompt serves its playbook verbatim from the kernel's skill tree" do
    server = mcp_server(fixture("knowledge"))
    EXPECTED.each do |name|
      playbook = name.sub(/\Aokf-/, "")
      text = rpc(server, "prompts/get", name: name).dig("result", "messages", 0, "content", "text")
      canonical = File.read(File.join(OKF::Skill::ASSETS, "playbooks", "#{playbook}.md"), encoding: "UTF-8")
      assert_equal canonical, text, "#{name} did not serve playbooks/#{playbook}.md verbatim"
    end
  end

  # The authoring playbooks instruct edits — maintain says "update bodies and
  # timestamp", produce says "write each concept". That is not in tension with
  # a read-only tool surface: a prompt is instructions for the *host's* tools,
  # not a capability this server offers. The four that shipped first were the
  # four whose names happened to resemble tools.
  test "the authoring playbooks are served even though every tool is read-only" do
    server = mcp_server(fixture("knowledge"))
    prompts = rpc(server, "prompts/list").dig("result", "prompts")
    %w[okf-produce okf-migrate okf-refine].each do |name|
      assert_includes prompts.map { |prompt| prompt["name"] }, name
    end

    tools = rpc(server, "tools/list").dig("result", "tools")
    assert tools.all? { |tool| tool.dig("annotations", "readOnlyHint") },
      "a write-capable tool would make the read-only posture a lie"
  end

  # The gemspec floors okf with no ceiling and the eight names are hardcoded
  # here, so a later kernel that renames or drops a playbook leaves this server
  # advertising a prompt whose file is gone. The tools funnel exactly this
  # through define_tool's rescue into an actionable message; the prompts path
  # let the errno escape as a bare -32603 carrying a filesystem path.
  test "a playbook the installed kernel no longer carries is an actionable refusal" do
    server = mcp_server(fixture("knowledge"))
    OKF::MCP::Server.stub(:playbook, ->(name) { raise Errno::ENOENT, "#{name}.md" }) do
      response = rpc(server, "prompts/get", name: "okf-menu", arguments: {})

      assert response["error"], "expected a refusal, got #{response.inspect}"
      message = response.dig("error", "message").to_s
      assert_match(/okf-menu/, message, "the refusal does not name the prompt that failed")
      assert_match(/okf skill/, message, "…nor what to do about it")
    end
  end

  test "each prompt carries the description the skill's own table gives it" do
    server = mcp_server(fixture("knowledge"))
    prompts = rpc(server, "prompts/list").dig("result", "prompts").to_h { |p| [ p["name"], p["description"] ] }
    assert_match(/highest-value next move/, prompts.fetch("okf-menu"))
    assert_match(/bodies verbatim/, prompts.fetch("okf-migrate"))
    assert_match(/menu playbook/, prompts.fetch("okf-menu"))
  end
end
