# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  class LogTest < MCPIntegrationCase
    test "every log.md, root scope first, content live from disk" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "log", bundle: "knowledge")

      assert_equal 2, data["total"]
      assert_equal %w[log.md runbooks/log.md], data["logs"].map { |row| row["path"] }
      assert_equal %w[. runbooks], data["logs"].map { |row| row["dir"] }
      assert_match(/ledger decision/, data["logs"].first["content"])
    end

    test "a just-appended entry shows without a reboot" do
      dir = File.join(@out_dir, "logged")
      FileUtils.cp_r(fixture("knowledge"), dir)
      server = mcp_server(dir)

      File.open(File.join(dir, "log.md"), "a") { |f| f.puts "\n## 2026-07-24\n* **Update**: Appended mid-session." }
      data = call_tool!(server, "log", bundle: "logged")
      assert_match(/Appended mid-session/, data["logs"].first["content"])
    end
  end
end
