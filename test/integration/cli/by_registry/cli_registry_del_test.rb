# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf registry del` end-to-end — dropping an entry from the persistent registry
# at $OKF_HOME/registry.json. It takes a slug, the bundle's directory, or an
# @ref, and the removal is asserted through what a later command sees: the
# listing, the effective default, and the file on disk.
#
# Every run here is pinned to the scratch @home (or the $OKF_HOME `with_registry`
# sets), so the suite never reads or writes the developer's own ~/.okf.
class CLIRegistryDelTest < CLIIntegrationCase
  test "removing by slug reports what went and drops it from the listing" do
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", fixture("minimal"))

    result = okf("registry", "del", "minimal")

    assert_equal 0, result.status
    assert_equal "removed minimal\n", result.out
    listing = okf("registry", "list").out
    assert_match(/conformant/, listing)
    refute_match(/minimal/, listing)
  end

  test "a bundle removes by its directory too — del takes a slug or a dir" do
    # Registered under a slug its basename would never mint, so only the *path*
    # can match: a del that succeeds here read the argument as a directory.
    okf("registry", "set", fixture("conformant"), "--as", "handbook")

    result = okf("registry", "del", fixture("conformant"))

    assert_equal 0, result.status
    assert_equal "removed handbook\n", result.out
    assert_match(/no bundles registered/, okf("registry", "list").out)
  end

  test "an @ref removes by name, and a bare @ removes the default" do
    with_registry("conformant", "minimal") do
      assert_equal "removed minimal\n", okf("registry", "del", "@minimal").out
      assert_equal "removed conformant\n", okf("registry", "del", "@").out

      exhausted = okf("registry", "del", "@")
      assert_equal 2, exhausted.status
      assert_match(/error: no bundle is registered, so `@` names nothing \(okf registry set <dir>\)/, exhausted.err)
    end
  end

  test "an unknown slug is a usage error (exit 2) and leaves the registry alone" do
    okf("registry", "set", fixture("conformant"))

    result = okf("registry", "del", "ghost")

    assert_equal 2, result.status
    assert_match(/error: no such bundle: ghost/, result.err)
    assert_empty result.out
    assert_equal %w[conformant], registry_json["bundles"].map { |row| row["slug"] }
  end

  test "removing the default clears the choice — the first remaining bundle takes over" do
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", fixture("minimal"))
    okf("registry", "set", fixture("empty"))
    okf("registry", "default", "minimal")
    assert_match(/^\* minimal/, okf("registry", "list").out)

    assert_equal 0, okf("registry", "del", "minimal").status

    listing = okf("registry", "list").out
    assert_match(/^\* conformant/, listing, "the first remaining bundle is the effective default")
    assert_match(/^ {2}empty/, listing)
    refute_includes registry_json.keys, "default", "the choice goes with the entry — no dangling slug is left behind"
  end

  test "an entry whose directory is already gone still deletes" do
    dir = File.join(@out_dir, "vanishing")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "index.md"), <<~MD)
      ---
      okf_version: "0.1"
      title: Vanishing
      ---
    MD
    okf("registry", "set", dir)
    FileUtils.rm_rf(dir)
    assert_match(/vanishing.*\(missing\)/, okf("registry", "list").out)

    result = okf("registry", "del", "vanishing")

    assert_equal 0, result.status
    assert_equal "removed vanishing\n", result.out
    assert_empty registry_json["bundles"], "the entry a gone directory left behind is exactly the one worth deleting"
  end

  test "$OKF_HOME picks the registry the del lands in" do
    other = File.join(@out_dir, "other-home")
    okf("registry", "set", fixture("conformant"))
    with_home(other) { okf("registry", "set", fixture("minimal")) }

    stray = with_home(other) { okf("registry", "del", "conformant") }

    assert_equal 2, stray.status
    assert_match(/error: no such bundle: conformant/, stray.err)
    assert_equal %w[conformant], registry_json["bundles"].map { |row| row["slug"] }, "the other home's del cannot reach this one"
  end

  test "a stray extra positional is a usage error (exit 2), and nothing is removed" do
    okf("registry", "set", fixture("conformant"))

    result = okf("registry", "del", "conformant", "extra")

    assert_equal 2, result.status
    assert_match(/error: unexpected argument 'extra'/, result.err)
    assert_equal %w[conformant], registry_json["bundles"].map { |row| row["slug"] }
  end

  test "no slug at all prints the banner (exit 2)" do
    result = okf("registry", "del")

    assert_equal 2, result.status
    assert_match(%r{Usage: okf registry del <slug-or-dir\|@ref>}, result.err)
    assert_empty result.out
  end

  test "the on-disk JSON after a del keeps the survivors in registration order" do
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", fixture("minimal"))
    okf("registry", "set", fixture("empty"))

    okf("registry", "del", "minimal")

    rows = registry_json["bundles"]
    assert_equal %w[conformant empty], rows.map { |row| row["slug"] }
    assert_equal [ fixture("conformant"), fixture("empty") ], rows.map { |row| row["path"] }
  end

  test "a path that is registered nowhere is refused, never read as a slug" do
    # `del` takes a slug *or* a directory, and the normalized-slug fallback must
    # not reach across that line: `./notes` names a directory, and an entry
    # slugged `notes` pointing somewhere else entirely has nothing to do with it.
    # Deleting that entry answers a question nobody asked — and answers it
    # destructively, with exit 0.
    okf("registry", "set", fixture("conformant"), "--as", "notes")

    result = okf("registry", "del", "./notes")

    assert_equal 2, result.status
    assert_match(/^error: no such bundle: \.\/notes$/, result.err)
    assert_equal [ "notes" ], registry_json["bundles"].map { |row| row["slug"] },
      "the entry the caller did not name is still registered"
  end

  test "a slug that only needs normalizing still deletes — the fallback keeps its real job" do
    okf("registry", "set", fixture("conformant"), "--as", "docs")

    result = okf("registry", "del", "DOCS")

    assert_equal 0, result.status
    assert_match(/^removed docs$/, result.out)
    assert_empty registry_json["bundles"]
  end

  test "a legacy `all` entry deletes under the name the read minted for it" do
    # The escape hatch has to be reachable: `del` is what a user with a
    # pre-reservation registry reaches for, so it must not be one of the verbs
    # that dies reading the row it is being asked to remove.
    File.write(File.join(@home, "registry.json"),
      JSON.generate({ "bundles" => [ { "slug" => "all", "path" => fixture("conformant"), "title" => "legacy" } ] }))

    result = okf("registry", "del", "all-2")

    assert_equal 0, result.status
    assert_match(/^removed all-2$/, result.out)
    assert_empty registry_json["bundles"], "the row is gone from the file, and the minted name is what removed it"
  end

  private

  # The registry as it sits on disk under the scratch home.
  def registry_json
    JSON.parse(File.read(File.join(@home, "registry.json")))
  end
end
