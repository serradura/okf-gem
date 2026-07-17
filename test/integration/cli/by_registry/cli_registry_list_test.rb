# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf registry list` end-to-end — the read view over the persistent registry:
# which bundles are registered, which one a bare `okf server` opens (*), and
# which have gone missing on disk. Advisory (exit 0), and the bare `okf registry`
# spells the same thing.
#
# Every invocation here pins --home (or $OKF_HOME, via with_registry) at the
# scratch home the base class makes and removes — the real ~/.okf is never read
# or written.
class CLIRegistryListTest < CLIIntegrationCase
  test "bare `okf registry` is the listing, exactly as `registry list` spells it" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    bare = okf("registry", "--home", @home)
    explicit = okf("registry", "list", "--home", @home)

    assert_equal 0, bare.status
    assert_match(/^\* conformant\s/, bare.out)
    assert_equal explicit.out, bare.out, "the bare umbrella and the named subcommand print one listing"
  end

  test "the human listing stars the default and columns the slugs" do
    okf("registry", "set", fixture("conformant"), "--home", @home)
    okf("registry", "set", fixture("minimal"), "--default", "--home", @home)

    out = okf("registry", "list", "--home", @home).out

    assert_match(/^ {2}conformant {2}fixtures\/conformant {2}\(#{Regexp.escape(fixture("conformant"))}\)$/, out)
    assert_match(/^\* minimal {5}fixtures\/minimal {2}\(#{Regexp.escape(fixture("minimal"))}\)$/, out,
      "the chosen default is starred, and slugs pad to a column")
  end

  test "the sole registered bundle is the effective default, starred without being chosen" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    assert_match(/^\* conformant\s/, okf("registry", "list", "--home", @home).out)
    assert_equal true, json(okf("registry", "list", "--json", "--home", @home))["bundles"].first["default"]
  end

  test "--json answers the object envelope, one row per bundle" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    result = okf("registry", "list", "--json", "--home", @home)
    payload = json(result)

    assert_equal 0, result.status
    assert_kind_of Hash, payload, "a bare array would break the CLI's one JSON shape"
    assert_equal %w[bundles count registry], payload.keys.sort
    assert_equal File.join(@home, "registry.json"), payload["registry"], "the envelope names the file it read, so a $OKF_HOME mismatch self-diagnoses"
    assert_equal 1, payload["count"]

    row = payload["bundles"].first
    assert_equal %w[default dir missing mount slug title], row.keys.sort
    assert_equal "conformant", row["slug"]
    assert_equal "fixtures/conformant", row["title"]
    assert_equal fixture("conformant"), row["dir"]
    assert_equal "/b/conformant/", row["mount"]
    assert_equal true, row["default"]
    assert_equal false, row["missing"]
  end

  test "count tracks the rows, and insertion order is the listing order" do
    okf("registry", "set", fixture("conformant"), "--home", @home)
    okf("registry", "set", fixture("minimal"), "--home", @home)
    okf("registry", "set", fixture("empty"), "--home", @home)

    payload = json(okf("registry", "list", "--json", "--home", @home))

    assert_equal 3, payload["count"]
    assert_equal %w[conformant minimal empty], payload["bundles"].map { |row| row["slug"] }
  end

  test "a bundle's mount is /b/<slug>/ — it follows the slug, not the directory" do
    okf("registry", "set", fixture("conformant"), "--as", "My Docs", "--home", @home)

    row = json(okf("registry", "list", "--json", "--home", @home))["bundles"].first

    assert_equal "my-docs", row["slug"]
    assert_equal "/b/my-docs/", row["mount"]
  end

  test "--pretty implies --json and indents it" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    pretty = okf("registry", "list", "--pretty", "--home", @home)

    assert_equal 0, pretty.status
    assert_match(/^ {2}"count": 1,$/, pretty.out, "--pretty alone emits JSON, indented")
    assert_equal json(okf("registry", "list", "--json", "--home", @home)), json(pretty), "the same JSON — only the whitespace differs"
  end

  test "an empty registry says so, and answers count 0 in JSON" do
    human = okf("registry", "list", "--home", @home)

    assert_equal 0, human.status
    assert_equal "no bundles registered — okf registry set <dir>\n", human.out

    payload = json(okf("registry", "list", "--json", "--home", @home))
    assert_equal 0, payload["count"]
    assert_equal [], payload["bundles"], "an empty registry still answers the envelope"
  end

  test "--home reads the registry there, and each home answers only its own" do
    other = File.join(@out_dir, "other-home")
    okf("registry", "set", fixture("conformant"), "--home", @home)
    okf("registry", "set", fixture("minimal"), "--home", other)

    assert_equal [ "conformant" ], slugs_from(okf("registry", "list", "--json", "--home", @home))
    assert_equal [ "minimal" ], slugs_from(okf("registry", "list", "--json", "--home", other))
  end

  test "$OKF_HOME is the registry when no --home is given" do
    with_registry("conformant") do
      assert_equal [ "conformant" ], slugs_from(okf("registry", "list", "--json"))
    end
  end

  test "a registered directory that vanished is flagged (missing)" do
    doomed = scratch_bundle("doomed")
    okf("registry", "set", fixture("conformant"), "--home", @home)
    okf("registry", "set", doomed, "--home", @home)
    FileUtils.rm_rf(doomed)

    result = okf("registry", "list", "--home", @home)

    assert_equal 0, result.status, "a vanished bundle is reported, not an error"
    assert_match(/^ {2}doomed {6}.*#{Regexp.escape(doomed)}\) {2}\(missing\)$/, result.out)
    refute_match(/conformant.*\(missing\)/, result.out, "only the vanished bundle is flagged")
  end

  test "--json flips `missing` true for the vanished bundle alone" do
    doomed = scratch_bundle("doomed")
    okf("registry", "set", fixture("conformant"), "--home", @home)
    okf("registry", "set", doomed, "--home", @home)

    refute_includes json(okf("registry", "list", "--json", "--home", @home))["bundles"].map { |row| row["missing"] }, true
    FileUtils.rm_rf(doomed)

    rows = json(okf("registry", "list", "--json", "--home", @home))["bundles"]
    assert_equal [ [ "conformant", false ], [ "doomed", true ] ], rows.map { |row| [ row["slug"], row["missing"] ] }
    assert_equal doomed, rows.last["dir"], "the row still names the directory that went away, so it can be restored or deleted"
  end

  test "a stray positional is a usage error (exit 2)" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    result = okf("registry", "list", "stray", "--home", @home)

    assert_equal 2, result.status
    assert_match(/^error: unexpected argument 'stray'$/, result.err)
    assert_empty result.out, "the listing is not printed alongside the complaint"
  end

  test "an unknown flag is a usage error (exit 2), reported not raised" do
    result = okf("registry", "list", "--bogus", "--home", @home)

    assert_equal 2, result.status
    assert_match(/invalid option: --bogus/, result.err)
    refute_match(/\.rb:\d+/, result.err, "a bad flag is a message, never a backtrace")
  end

  private

  # A one-concept bundle under @out_dir — a directory a test is free to delete.
  def scratch_bundle(name)
    dir = File.join(@out_dir, name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "note.md"), "---\ntype: Note\ntitle: Scratch Note\n---\n\nA scratch concept.\n")
    dir
  end

  def slugs_from(result)
    json(result)["bundles"].map { |row| row["slug"] }
  end
end
