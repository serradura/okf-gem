# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf loose` end-to-end — the folder-grouped view of degree-0 concepts (files with
# no cross-links in or out), a curation lens over the graph distinct from `lint`'s
# reachability (an index listing does not connect a file in the graph).
module ByDir
  # Bundles named by path — the plain form every verb accepts.
  class CLILooseTest < CLIIntegrationCase
    test "lists a floating concept grouped under its folder (exit 0)" do
      result = okf("loose", fixture("minimal"))

      assert_equal 0, result.status
      assert_match(/Loose files .* \(1\)/, result.out)
      assert_match(/note\.md\s+Only Note/, result.out)
    end

    test "reports none when every concept is linked" do
      result = okf("loose", fixture("conformant"))

      assert_equal 0, result.status
      assert_match(/\(0\)/, result.out)
      assert_match(/none/, result.out)
    end

    test "--json emits the loose set as a machine substrate" do
      result = okf("loose", fixture("minimal"), "--json")
      data = JSON.parse(result.out)

      assert_equal 1, data.fetch("count")
      assert_equal %w[dir id title], data.fetch("loose").first.keys.sort
      assert_equal "note", data.fetch("loose").first.fetch("id")
    end

    test "is best-effort — malformed files are skipped (stderr), not fatal" do
      result = okf("loose", fixture("malformed"))

      assert_equal 0, result.status
      assert_match(/skipped 2 unusable file\(s\)/, result.err)
    end
  end
end
