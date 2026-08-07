# frozen_string_literal: true

require_relative "mcp_integration_case"

# The consuming prompts, and only those: this server's mission is to make any
# MCP client an expert consumer of bundles, so the surface offers the two
# playbooks that teach consumption — search and consume — rewritten in this
# server's own tool vocabulary and shipped in this gem. The skill's authoring
# playbooks (produce, migrate, maintain, refine, curate) and its CLI front door
# (menu) are the okf skill's to serve: they instruct CLI runs and file edits
# this surface cannot make, and half of them dead-ended a CLI-less host at
# "install the CLI first".
class PromptsTest < MCPIntegrationCase
  # SKILL.md's Commands-table order, kept by the two survivors: search before
  # consume, so the surfaces that offer both verbs agree on their sequence.
  EXPECTED = %w[okf-search okf-consume].freeze

  PROMPTS_DIR = File.expand_path("../../lib/okf/mcp/prompts", __dir__)

  # Words the prompts set in backticks that are neither tools nor arguments —
  # worked examples and typography (`ustomer` is the mid-word fragment the
  # engine table teaches with). Anything else backticked must exist on the
  # wire, so this list is what keeps a renamed tool from hiding as prose.
  PROSE_TOKENS = %w[backticks customer_id dedup deduplication ustomer].freeze

  test "only the consuming prompts are offered" do
    server = mcp_server(fixture("knowledge"))
    names = rpc(server, "prompts/list").dig("result", "prompts").map { |prompt| prompt["name"] }
    assert_equal EXPECTED, names
  end

  # The trim is a refusal, not an omission: a host asking for a prompt this
  # server used to offer must get a protocol error, never an empty result.
  test "the authoring playbooks and the menu are not prompts" do
    server = mcp_server(fixture("knowledge"))
    %w[okf-menu okf-produce okf-migrate okf-maintain okf-refine okf-curate okf-doctor].each do |name|
      response = rpc(server, "prompts/get", name: name)
      assert response["error"], "#{name} must be a protocol error, not a served prompt"
    end
  end

  test "a prompt serves this gem's own text verbatim" do
    server = mcp_server(fixture("knowledge"))
    EXPECTED.each do |name|
      file = name.sub(/\Aokf-/, "")
      text = rpc(server, "prompts/get", name: name).dig("result", "messages", 0, "content", "text")
      canonical = read_utf8(File.join(PROMPTS_DIR, "#{file}.md"))
      assert_equal canonical, text, "#{name} did not serve prompts/#{file}.md verbatim"
    end
  end

  # The rewrite's whole point: the text teaches this server's tools, not the
  # CLI. No backticked `okf …` invocation may survive — that spelling is what
  # made the skill's playbooks dead weight to a host with no shell — and
  # *every* backticked word must be accounted for: a served tool, a declared
  # argument, or the prose list above. The first cut checked five tools from
  # a fixed list and never noticed the texts also teach `log`, `catalog` and
  # `graph` — a rename there would have shipped a prompt pointing at a tool
  # that answers method-not-found, suite green.
  test "the prompt text speaks in tool names, never CLI invocations" do
    server = mcp_server(fixture("knowledge"))
    tools = rpc(server, "tools/list").dig("result", "tools")
    served = tools.map { |tool| tool["name"] }
    arguments = tools.flat_map { |tool| (tool.dig("inputSchema", "properties") || {}).keys }.uniq
    EXPECTED.each do |name|
      text = rpc(server, "prompts/get", name: name).dig("result", "messages", 0, "content", "text")
      refute_match(/`okf /, text, "#{name} still instructs a CLI run")
      tokens = text.scan(/`([a-z][a-z_]*)`/).flatten.uniq
      refute_empty tokens & served, "#{name} teaches none of the tools"
      stray = tokens - served - arguments - PROSE_TOKENS
      assert_empty stray, "#{name} backticks #{stray.inspect} — not a served tool, a declared argument, or listed prose"
    end
  end

  test "each prompt carries a consuming description" do
    server = mcp_server(fixture("knowledge"))
    prompts = rpc(server, "prompts/list").dig("result", "prompts").to_h { |p| [ p["name"], p["description"] ] }
    assert_match(/pointed question/, prompts.fetch("okf-search"))
    assert_match(/without reading it whole/, prompts.fetch("okf-consume"))
  end

  # The old surface pointed a fixable finding at the okf-curate and
  # okf-maintain prompts; those are gone, so the boot instructions must not
  # send a host to a prompt that will refuse.
  test "the server instructions name no retired prompt" do
    text = OKF::MCP::Server::INSTRUCTIONS
    %w[okf-menu okf-produce okf-migrate okf-maintain okf-refine okf-curate].each do |name|
      refute_match(/#{name}/, text, "instructions still point at #{name}")
    end
  end
end
