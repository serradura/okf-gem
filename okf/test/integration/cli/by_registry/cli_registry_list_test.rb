# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf registry list` end-to-end — the read view over the persistent registry:
# which bundles are registered, which one a bare `okf server` opens (*), and
# which have gone missing on disk. Advisory (exit 0), and the bare `okf registry`
# spells the same thing.
#
# $OKF_HOME is pinned at the scratch home the base class makes and removes (see
# the integration case's setup), so the real ~/.okf is never read or written.
class CLIRegistryListTest < CLIIntegrationCase
  test "bare `okf registry` is the listing, exactly as `registry list` spells it" do
    okf("registry", "set", fixture("conformant"))

    bare = okf("registry")
    explicit = okf("registry", "list")

    assert_equal 0, bare.status
    assert_match(/^\* conformant\s/, bare.out)
    assert_equal explicit.out, bare.out, "the bare umbrella and the named subcommand print one listing"
  end

  test "the human listing stars the default and columns the slugs" do
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", fixture("minimal"), "--default")

    out = okf("registry", "list").out

    assert_match(/^ {2}conformant {2}fixtures\/conformant {2}\(#{Regexp.escape(fixture("conformant"))}\)$/, out)
    assert_match(/^\* minimal {5}fixtures\/minimal {2}\(#{Regexp.escape(fixture("minimal"))}\)$/, out,
      "the chosen default is starred, and slugs pad to a column")
  end

  test "the sole registered bundle is the effective default, starred without being chosen" do
    okf("registry", "set", fixture("conformant"))

    assert_match(/^\* conformant\s/, okf("registry", "list").out)
    assert_equal true, json(okf("registry", "list", "--json"))["bundles"].first["default"]
  end

  test "--json answers the object envelope, one row per bundle" do
    okf("registry", "set", fixture("conformant"))

    result = okf("registry", "list", "--json")
    payload = json(result)

    assert_equal 0, result.status
    assert_kind_of Hash, payload, "a bare array would break the CLI's one JSON shape"
    assert_equal %w[bundles count groups registry], payload.keys.sort
    assert_equal [], payload["groups"], "the groups key is always present, empty when none are registered"
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
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", fixture("minimal"))
    okf("registry", "set", fixture("empty"))

    payload = json(okf("registry", "list", "--json"))

    assert_equal 3, payload["count"]
    assert_equal %w[conformant minimal empty], payload["bundles"].map { |row| row["slug"] }
  end

  test "a bundle's mount is /b/<slug>/ — it follows the slug, not the directory" do
    okf("registry", "set", fixture("conformant"), "--as", "My Docs")

    row = json(okf("registry", "list", "--json"))["bundles"].first

    assert_equal "my-docs", row["slug"]
    assert_equal "/b/my-docs/", row["mount"]
  end

  test "--pretty implies --json and indents it" do
    okf("registry", "set", fixture("conformant"))

    pretty = okf("registry", "list", "--pretty")

    assert_equal 0, pretty.status
    assert_match(/^ {2}"count": 1,$/, pretty.out, "--pretty alone emits JSON, indented")
    assert_equal json(okf("registry", "list", "--json")), json(pretty), "the same JSON — only the whitespace differs"
  end

  test "an empty registry says so, and answers count 0 in JSON" do
    human = okf("registry", "list")

    assert_equal 0, human.status
    assert_equal "no bundles registered — okf registry set <dir>\n", human.out

    payload = json(okf("registry", "list", "--json"))
    assert_equal 0, payload["count"]
    assert_equal [], payload["bundles"], "an empty registry still answers the envelope"
  end

  test "$OKF_HOME names the registry, and each home answers only its own" do
    other = File.join(@out_dir, "other-home")
    okf("registry", "set", fixture("conformant"))
    with_home(other) { okf("registry", "set", fixture("minimal")) }

    assert_equal [ "conformant" ], slugs_from(okf("registry", "list", "--json"))
    assert_equal [ "minimal" ], slugs_from(with_home(other) { okf("registry", "list", "--json") })
  end

  test "an unexpandable $OKF_HOME is a usage error (exit 2), never a backtrace" do
    # $OKF_HOME is the only lever on which registry a verb reads, so a bad one is
    # a bad *argument*: exit 2. exit 1 would mean "failing bundle", and a
    # backtrace would mean nobody handled it.
    result = with_home("~nosuchuser") { okf("registry", "list") }

    assert_equal 2, result.status
    assert_match(/error: cannot expand ~nosuchuser/, result.err)
    assert_empty result.out
  end

  test "a registered directory that vanished is flagged (missing)" do
    doomed = scratch_bundle("doomed")
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", doomed)
    FileUtils.rm_rf(doomed)

    result = okf("registry", "list")

    assert_equal 0, result.status, "a vanished bundle is reported, not an error"
    assert_match(/^ {2}doomed {6}.*#{Regexp.escape(doomed)}\) {2}\(missing\)$/, result.out)
    refute_match(/conformant.*\(missing\)/, result.out, "only the vanished bundle is flagged")
  end

  test "the star follows what `/` opens, so a vanished first entry does not wear it" do
    # The star means "the bundle a bare `okf server` opens at /", and the hub
    # cannot open a directory that is gone — it drops it and lands on the next.
    # Starring the vanished entry would point the user at a bundle `/` will
    # never serve, which is why the default is the first one *still on disk*.
    doomed = scratch_bundle("doomed")
    okf("registry", "set", doomed)
    okf("registry", "set", fixture("conformant"))
    FileUtils.rm_rf(doomed)

    result = okf("registry", "list")

    assert_equal 0, result.status
    assert_match(/^ {2}doomed .*\(missing\)$/, result.out, "the vanished first entry is listed, flagged, and unstarred")
    assert_match(/^\* conformant/, result.out, "the star sits on the first bundle still on disk")
    assert_equal 1, result.out.scan(/^\* /).size, "exactly one default"
  end

  test "--json says default false for a vanished first entry, true for the one / opens" do
    doomed = scratch_bundle("doomed")
    okf("registry", "set", doomed)
    okf("registry", "set", fixture("conformant"))
    FileUtils.rm_rf(doomed)

    rows = json(okf("registry", "list", "--json"))["bundles"]

    assert_equal [ [ "doomed", true, false ], [ "conformant", false, true ] ],
      rows.map { |row| [ row["slug"], row["missing"], row["default"] ] },
      "order is untouched — only the default moves past the hole"
  end

  test "a registry of nothing but vanished bundles still names its default" do
    # Every entry missing means `/` opens nothing, but the listing must still
    # answer, and the first entry is still the one the user chose — falling back
    # to it keeps `@` failing with "points to <path>, which is not a directory"
    # instead of the far worse "not a registered bundle".
    doomed = scratch_bundle("doomed")
    okf("registry", "set", doomed)
    FileUtils.rm_rf(doomed)

    result = okf("registry", "list")

    assert_equal 0, result.status
    assert_match(/^\* doomed .*\(missing\)$/, result.out)
  end

  test "a reserved slug on the way in is minted around, not grounds to reject the file" do
    # `all` reaches the file two ways nothing can take back: a registry written
    # before the name was reserved (every released version slugged a directory
    # named all/ exactly that), and the hand-editing the format invites. Refusing
    # the whole registry over one unusable *name* would take every healthy entry
    # with it — and `registry del`/`rename`, the two verbs that could fix it, die
    # on the same read. So the read mints around it, as #unique_slug does for a
    # directory named all/: the entry keeps its bundle and answers to @all-2.
    write_registry([ { "slug" => "all", "path" => fixture("conformant"), "title" => "legacy" },
                     { "slug" => "docs", "path" => fixture("minimal"), "title" => "docs" } ])

    result = okf("registry", "list")

    assert_equal 0, result.status
    refute_match(/malformed/, result.err, "one unusable name is not a malformed file")
    assert_match(/^\* all-2 /, result.out, "the minted name is the one the listing answers to")
    rows = json(okf("registry", "list", "--json"))["bundles"]
    assert_equal %w[all-2 docs], rows.map { |row| row["slug"] },
      "the healthy entry survives the sick one, and the sick one survives too"
    assert_equal "/b/all-2/", rows.first["mount"], "the minted name is the mount, so the bundle is reachable in the browser too"
    assert_equal fixture("conformant"), rows.first["dir"], "renaming the slug moves no bundle"
  end

  test "a hand-typed slug is normalized on the way in, so the listing never shows a name no ref can reach" do
    # The write path normalizes and the read path did not, so the file could hold
    # a slug the listing prints and nothing else can name: `@my-docs` misses it,
    # and `rename`/`default` — the verbs that could fix it — miss it too, because
    # they all look up through normalize. Same dead end the reserved `all` row
    # had, one asymmetry over.
    write_registry([ { "slug" => "My Docs", "path" => fixture("conformant"), "title" => "hand-typed" } ])

    result = okf("registry", "list")

    assert_equal 0, result.status
    assert_match(/^\* my-docs /, result.out, "the listing shows the name registration would have given it")
    assert_equal 0, okf("lint", "@my-docs").status, "the name the listing prints is the name a ref resolves"
  end

  test "normalizing on read does not rob an entry of a name it already holds" do
    write_registry([ { "slug" => "My Docs", "path" => fixture("conformant"), "title" => "hand-typed" },
                     { "slug" => "my-docs", "path" => fixture("minimal"), "title" => "already normal" } ])

    assert_equal %w[my-docs-2 my-docs], slugs_from(okf("registry", "list", "--json")),
      "the entry that was already usable keeps its slug; the one being fixed mints around it"
  end

  test "the minted name steps past a slug already spoken for" do
    write_registry([ { "slug" => "all", "path" => fixture("conformant"), "title" => "legacy" },
                     { "slug" => "all-2", "path" => fixture("minimal"), "title" => "taken" } ])

    result = okf("registry", "list", "--json")

    assert_equal 0, result.status
    assert_equal %w[all-3 all-2], slugs_from(result),
      "minting around `all` must not collide with an entry that already answers to all-2"
  end

  test "@all keeps its meaning over a registry that carries a legacy `all` entry" do
    write_registry([ { "slug" => "all", "path" => fixture("conformant"), "title" => "legacy" } ])

    result = okf("lint", "@all")

    assert_equal 2, result.status
    assert_match(/@all is only supported by `okf search`/, result.err,
      "the ref grammar wins the name — the entry moved aside, so @all never means one bundle")
  end

  test "--json flips `missing` true for the vanished bundle alone" do
    doomed = scratch_bundle("doomed")
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", doomed)

    refute_includes json(okf("registry", "list", "--json"))["bundles"].map { |row| row["missing"] }, true
    FileUtils.rm_rf(doomed)

    rows = json(okf("registry", "list", "--json"))["bundles"]
    assert_equal [ [ "conformant", false ], [ "doomed", true ] ], rows.map { |row| [ row["slug"], row["missing"] ] }
    assert_equal doomed, rows.last["dir"], "the row still names the directory that went away, so it can be restored or deleted"
  end

  test "a stray positional is a usage error (exit 2)" do
    okf("registry", "set", fixture("conformant"))

    result = okf("registry", "list", "stray")

    assert_equal 2, result.status
    assert_match(/^error: unexpected argument 'stray'$/, result.err)
    assert_empty result.out, "the listing is not printed alongside the complaint"
  end

  test "an unknown flag is a usage error (exit 2), reported not raised" do
    result = okf("registry", "list", "--bogus")

    assert_equal 2, result.status
    assert_match(/invalid option: --bogus/, result.err)
    refute_match(/\.rb:\d+/, result.err, "a bad flag is a message, never a backtrace")
  end

  # -- groups in the listing

  test "the human listing shows groups under the bundles, with member refs and a resolved count" do
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", fixture("minimal"))
    okf("registry", "group", "docs", "@conformant", "@minimal")

    out = okf("registry", "list").out

    assert_match(/^groups:$/, out, "the section is headed and set off from the bundle rows")
    assert_match(/^  docs  @conformant, @minimal  \(2 bundles\)$/, out)
  end

  test "a group's resolved count is singular for one bundle, and slugs pad to a column" do
    okf("registry", "set", fixture("conformant"))
    okf("registry", "group", "a", "@conformant")
    okf("registry", "group", "longer", "@conformant")

    out = okf("registry", "list").out

    assert_match(/^  a {7}@conformant  \(1 bundle\)$/, out, "one leaf is singular, and the short slug pads to the column")
    assert_match(/^  longer  @conformant  \(1 bundle\)$/, out)
  end

  test "a group row missing its members array is a malformed registry, named for the fix" do
    File.write(File.join(@home, "registry.json"), JSON.generate("bundles" => [], "groups" => [ { "slug" => "docs" } ]))

    result = okf("registry", "list")

    assert_equal 2, result.status
    assert_match(/malformed registry/, result.err)
    assert_match(/every group needs a "slug" and a "members" array/, result.err)
  end

  test "a hand-typed group slug is normalized on read, like a bundle slug" do
    File.write(File.join(@home, "registry.json"), JSON.generate(
      "bundles" => [ { "slug" => "one", "path" => fixture("conformant"), "title" => "t" } ],
      "groups" => [ { "slug" => "My Group", "members" => %w[one] } ]
    ))

    groups = json(okf("registry", "list", "--json"))["groups"]

    assert_equal "my-group", groups.first["slug"], "the listing shows the name a ref can reach, not one nothing resolves"
  end

  test "a hand-edited cyclic group lists as (cycle) rather than crashing the read" do
    File.write(File.join(@home, "registry.json"), JSON.generate(
      "bundles" => [ { "slug" => "one", "path" => fixture("conformant"), "title" => "t" } ],
      "groups" => [ { "slug" => "a", "members" => %w[b] }, { "slug" => "b", "members" => %w[a] } ]
    ))

    result = okf("registry", "list")

    assert_equal 0, result.status, "one unresolvable group is not a malformed file"
    assert_match(/^  a\s+@b\s+\(cycle\)$/, result.out, "an unanswerable count reads (cycle), not a crash")
    assert_match(/^  b\s+@a\s+\(cycle\)$/, result.out)
  end

  private

  def slugs_from(result)
    json(result)["bundles"].map { |row| row["slug"] }
  end

  # Hand-write the registry file, the way the format invites and a pre-reservation
  # release wrote it. `registry set` cannot stage these rows — that is the point.
  def write_registry(rows)
    File.write(File.join(@home, "registry.json"), JSON.generate({ "bundles" => rows }))
  end
end
