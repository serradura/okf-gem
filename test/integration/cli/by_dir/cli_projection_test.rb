# frozen_string_literal: true

require_relative "../cli_integration_case"

module ByDir
  # The `--fields`/`--except` projection, across every view that offers it. The
  # declared row shape (CLI::ROW_FIELDS) is what lets a typo be caught when the
  # result is empty — and is knowledge duplicated from the row builders, so the
  # first test here is the guard that keeps the two from drifting apart.
  class CLIProjectionTest < CLIIntegrationCase
    # declared key => argv that yields at least one row (:dir marks the bundle
    # slot, since `search` takes its terms *after* the directory).
    VIEWS = {
      "concepts" => [ "catalog", :dir ],
      "files" => [ "files", :dir ],
      "directories" => [ "index", :dir ],
      "matches" => [ "search", :dir, "orders" ]
    }.freeze

    test "every declared row shape matches the rows the view actually emits" do
      VIEWS.each do |key, argv|
        command = argv.map { |arg| arg == :dir ? fixture("conformant") : arg }
        rows = json(okf(*command, "--json")).fetch(key)
        refute_empty rows, "#{key} needs a non-empty result for this to mean anything"

        declared = OKF::CLI::ROW_FIELDS.fetch(key)
        assert_equal rows.first.keys.sort, (declared - [ "slug" ]).sort,
          "#{key}: ROW_FIELDS drifted from the rows `#{argv.first}` emits"
      end
    end

    test "the registry list shape is declared too" do
      with_registry("conformant") do
        row = json(okf("registry", "list", "--json", "--home", @home)).fetch("bundles").first
        assert_equal row.keys.sort, OKF::CLI::ROW_FIELDS.fetch("bundles").sort
      end
    end

    test "a slug joins the declared match shape only in registry mode" do
      with_registry("conformant") do
        assert_includes json(okf("search", "@conformant", "orders", "--json")).fetch("matches").first.keys, "slug"
      end
      refute_includes json(okf("search", fixture("conformant"), "orders", "--json")).fetch("matches").first.keys, "slug"
      assert_includes OKF::CLI::ROW_FIELDS.fetch("matches"), "slug", "declared as the union, so --fields slug is never a typo"
    end

    test "an unknown field is a usage error whether or not the result has rows" do
      # The bug this guards: the check used to key off the data, so a typo was
      # an error against a bundle with matches and silently fine against one
      # without — a typo's fate decided by whether a filter happened to match.
      full = okf("catalog", fixture("conformant"), "--fields", "bogus")
      assert_equal 2, full.status
      assert_match(/unknown field\(s\): bogus \(available: id, title, .*links_in\)/, full.err)

      narrowed = okf("catalog", fixture("conformant"), "--tag", "nosuchtag", "--fields", "bogus")
      assert_equal 2, narrowed.status, "an empty result still knows what its fields are called"
      assert_equal full.err, narrowed.err, "and says the same thing about them"

      empty_bundle = okf("index", fixture("empty"), "--fields", "bogus")
      assert_equal 2, empty_bundle.status, "even a bundle with no concepts at all"
    end

    test "a valid projection still answers over an empty result" do
      result = okf("catalog", fixture("conformant"), "--tag", "nosuchtag", "--fields", "id,title")

      assert_equal 0, result.status
      assert_equal 0, json(result).fetch("count")
      assert_equal [], json(result).fetch("concepts")
    end

    test "--no-body and --fields body contradict each other rather than one winning" do
      # --no-body is shorthand for --except body; asking for the body by name in
      # the same breath used to hand it back, silently.
      result = okf("index", fixture("minimal"), "--no-body", "--fields", "body")

      assert_equal 2, result.status
      assert_match(/--no-body and --fields body contradict each other/, result.err)
      assert_empty result.out

      # each alone is still fine
      assert_equal 0, okf("index", fixture("minimal"), "--no-body", "--json").status
      assert_includes json(okf("index", fixture("minimal"), "--fields", "body")).fetch("directories").first.keys, "body"
    end
  end
end
