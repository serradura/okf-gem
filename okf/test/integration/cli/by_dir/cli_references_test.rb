# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf references` end-to-end — the §6.3 inventory: every file under
# `references/`, which concepts cite it through the §6.2 path-valued fields
# (resource, sources[].resource, computation, executor.resource,
# attester.resource), and the pointers into `references/` that resolve to
# nothing — bare paths written from a subdirectory first among them, since §6.2
# resolves those relative to the concept. An advisory read (exit 0): what a
# curator acts on lives in the output, never the status.
module ByDir
  # Bundles named by path — the plain form every verb accepts.
  class CLIReferencesTest < CLIIntegrationCase
    test "inventories the references/ tree with each file's citers (exit 0)" do
      result = okf("references", fixture("v0_2"))

      assert_equal 0, result.status
      assert_match(/References — .*v0_2 \(3 files\)/, result.out)
      assert_match(%r{references/attesters/\n {4}revenue\.py {2}← metrics/revenue \(attester\.resource\)}, result.out)
      assert_match(%r{references/computations/\n {4}orders-daily\.sql {2}← metrics/orders-daily \(computation\)}, result.out)
      refute_match(/dangling/, result.out, "a clean bundle has no dangling section")
    end

    test "a references/ file that is itself a concept is marked, and carries every citer" do
      result = okf("references", fixture("v0_2"))

      assert_match(
        %r{run-on-bigquery\.md {2}\[concept\] {2}← metrics/orders-daily \(executor\.resource\), metrics/revenue \(executor\.resource\)},
        result.out
      )
    end

    test "an uncited file says so, and a bare path from a subdirectory dangles with the leading-slash hint" do
      result = okf("references", fixture("references-trap"))

      assert_equal 0, result.status
      assert_match(/References — .* \(2 files\)/, result.out)
      assert_match(%r{revenue\.py {2}← overview \(sources\[0\]\.resource\)}, result.out,
        "the same bare spelling resolves from the root, so the root concept cites it")
      assert_match(/scratch\.txt {2}\(unreferenced\)/, result.out)
      assert_match(/dangling pointers:/, result.out)
      assert_includes result.out,
        "    metrics/report — sources[0].resource: references/attesters/revenue.py\n      " \
        "resolves to metrics/references/attesters/revenue.py, which does not exist " \
        "— /references/attesters/revenue.py does (missing leading slash?)\n"
      assert_match(
        %r{metrics/report — sources\[1\]\.resource: /references/specs/missing\.md\n {6}resolves to references/specs/missing\.md, which does not exist$},
        result.out
      )
    end

    test "a dangling pointer is reported even when the bundle has no references/ tree at all" do
      result = okf("references", fixture("v0_2-uncurated"))

      assert_equal 0, result.status
      assert_match(/\(0 files\)/, result.out)
      assert_match(%r{both-computation — computation: references/computations/both\.sql}, result.out)
      assert_match(%r{dangling-executor — executor\.resource: /references/skills/missing-runbook\.md}, result.out)
    end

    test "a bundle with no references/ directory and no pointers prints an empty inventory (exit 0)" do
      result = okf("references", fixture("conformant"))

      assert_equal 0, result.status
      assert_match(/References — .*conformant \(0 files\)/, result.out)
      assert_match(/\(none\)/, result.out)
      refute_match(/dangling/, result.out)
    end

    test "--json emits the bundle envelope, the row shape, and the dangling pointers" do
      data = json(okf("references", fixture("references-trap"), "--json"))

      assert_equal fixture("references-trap"), data.fetch("bundle")
      assert_equal 2, data.fetch("count")
      rows = data.fetch("references")
      assert_equal %w[path dir kind referenced_by], rows.first.keys
      assert_equal "references/attesters/revenue.py", rows.first.fetch("path")
      assert_equal "references/attesters", rows.first.fetch("dir")
      assert_equal "file", rows.first.fetch("kind")
      assert_equal [ { "id" => "overview", "field" => "sources[0].resource" } ], rows.first.fetch("referenced_by")
      assert_equal [], rows.last.fetch("referenced_by")

      dangling = data.fetch("dangling")
      assert_equal 2, dangling.size
      assert_equal(
        { "id" => "metrics/report", "field" => "sources[0].resource",
          "raw" => "references/attesters/revenue.py",
          "resolved" => "metrics/references/attesters/revenue.py",
          "hint" => "/references/attesters/revenue.py exists — missing leading slash?" },
        dangling.first
      )
      assert_nil dangling.last.fetch("hint"), "a plain miss carries no hint"
    end

    test "--json marks kinds, sorted by path, and never mistakes a URL for a pointer" do
      data = json(okf("references", fixture("v0_2"), "--json"))
      rows = data.fetch("references")

      assert_equal %w[file file concept], rows.map { |row| row.fetch("kind") }
      assert_equal rows.map { |row| row.fetch("path") }, rows.map { |row| row.fetch("path") }.sort
      assert_equal [], data.fetch("dangling"),
        "the https sources across v0_2 are external, not dangling pointers"
    end

    test "--pretty implies --json and indents it" do
      result = okf("references", fixture("v0_2"), "--pretty")

      assert_equal 3, JSON.parse(result.out).fetch("count")
      assert_match(/^\{\n  "bundle": /, result.out)
      assert_match(/^\{"bundle"/, okf("references", fixture("v0_2"), "--json").out)
    end

    test "--fields keeps only the named properties (and implies --json)" do
      data = json(okf("references", fixture("v0_2"), "--fields", "path,kind"))

      assert_equal %w[path kind], data.fetch("references").first.keys
      assert_equal 3, data.fetch("count") # the envelope is never projected away
    end

    test "--except drops the named properties (and implies --json)" do
      row = json(okf("references", fixture("v0_2"), "--except", "referenced_by")).fetch("references").first

      assert_equal %w[path dir kind], row.keys
    end

    test "an unknown field is a usage error naming the shape (exit 2)" do
      result = okf("references", fixture("v0_2"), "--fields", "bogus")

      assert_equal 2, result.status
      assert_match(/unknown field\(s\): bogus \(available: path, dir, kind, referenced_by\)/, result.err)
    end

    test "--fields and --except are mutually exclusive (exit 2)" do
      result = okf("references", fixture("v0_2"), "--fields", "path", "--except", "kind")

      assert_equal 2, result.status
      assert_match(/--fields and --except are mutually exclusive/, result.err)
    end
  end
end
