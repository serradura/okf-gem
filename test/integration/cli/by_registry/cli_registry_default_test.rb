# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf registry default` end-to-end — choosing which registered bundle a bare
# `okf server` opens at `/`. The choice *is* position: the first entry is the
# default, and `default <slug>` moves that entry to the front. So every test
# here asserts the resulting order on disk, not only the star in the listing —
# the star is a rendering of the order, and a test that reads only the star
# would pass on a registry that reordered nothing.
#
# Every run here is pinned to the scratch @home, so the suite never reads or
# writes the developer's own ~/.okf.
class CLIRegistryDefaultTest < CLIIntegrationCase
  test "choosing a slug moves it to the front, and stars it in the listing" do
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", fixture("minimal"))
    assert_equal %w[conformant minimal], registry_slugs, "registration order, before any choice"

    result = okf("registry", "default", "minimal")

    assert_equal 0, result.status
    assert_equal "default bundle → minimal (now first)\n", result.out
    assert_equal %w[minimal conformant], registry_slugs, "the chosen entry moved to the front"
    listing = okf("registry", "list").out
    assert_match(/^\* minimal/, listing)
    assert_match(/^ {2}conformant/, listing, "the star moves — it never doubles")
  end

  test "the move keeps every other entry in its order" do
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", fixture("minimal"))
    okf("registry", "set", fixture("empty"))

    okf("registry", "default", "empty")

    assert_equal %w[empty conformant minimal], registry_slugs,
      "the chosen one leads; the rest keep the order they were registered in"
  end

  test "the chosen default persists — later commands and the file agree" do
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", fixture("minimal"))

    okf("registry", "default", "minimal")

    assert_equal %w[minimal conformant], registry_slugs
    okf("registry", "set", fixture("empty")) # an unrelated write
    assert_equal %w[minimal conformant empty], registry_slugs,
      "registering another bundle appends — it must not disturb the choice"
    assert_match(/^\* minimal/, okf("registry", "list").out)
    assert_equal true, json(okf("registry", "list", "--json"))["bundles"]
      .find { |row| row["slug"] == "minimal" }["default"]
  end

  test "an unknown slug is a usage error (exit 2) and keeps the incumbent" do
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", fixture("minimal"))
    okf("registry", "default", "minimal")

    result = okf("registry", "default", "ghost")

    assert_equal 2, result.status
    assert_match(/error: no such bundle: ghost/, result.err)
    assert_empty result.out
    assert_equal %w[minimal conformant], registry_slugs, "a refused move reorders nothing"
  end

  test "the first registered entry is the default until another is moved to the front" do
    okf("registry", "set", fixture("minimal"))
    okf("registry", "set", fixture("conformant"))

    listing = okf("registry", "list").out
    assert_match(/^\* minimal/, listing, "first in, first served — no choice needed")
    assert_match(/^ {2}conformant/, listing)
    assert_equal true, json(okf("registry", "list", "--json"))["bundles"].first["default"],
      "the row still says which one it is, so a consumer need not know the rule"
  end

  test "removing the default promotes the next entry — nothing to clear, nothing to dangle" do
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", fixture("minimal"))
    okf("registry", "default", "minimal")
    assert_equal %w[minimal conformant], registry_slugs

    okf("registry", "del", "minimal")

    assert_equal %w[conformant], registry_slugs
    assert_match(/^\* conformant/, okf("registry", "list").out)

    okf("registry", "set", fixture("minimal")) # back, under the same slug
    assert_equal %w[conformant minimal], registry_slugs,
      "re-registering appends: the deleted bundle cannot resurrect a claim on `/`"
    assert_match(/^\* conformant/, okf("registry", "list").out)
  end

  test "the slug is normalized: @minimal and MINIMAL choose the same bundle; a bare @ does not" do
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", fixture("minimal"))

    at_ref = okf("registry", "default", "@minimal")
    assert_equal 0, at_ref.status
    assert_equal "default bundle → minimal (now first)\n", at_ref.out, "the @ normalizes away — the ref spelling resolves"

    okf("registry", "default", "conformant")
    cased = okf("registry", "default", "MINIMAL")
    assert_equal 0, cased.status
    assert_equal %w[minimal conformant], registry_slugs, "the ask is normalized the way registration normalized it"

    # A bare @ means "the current default", exactly as it does for `del` — the
    # slug verbs read the ref grammar deliberately now, rather than by way of
    # normalize happening to strip the @ off a slug and choke on a lone one.
    bare = okf("registry", "default", "@")
    assert_equal 0, bare.status
    assert_equal %w[minimal conformant], registry_slugs, "choosing the current default is a coherent no-op"
  end

  test "$OKF_HOME picks the registry the choice lands in" do
    other = File.join(@out_dir, "other-home")
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", fixture("minimal"))
    with_home(other) { okf("registry", "set", fixture("conformant")) }

    unreachable = with_home(other) { okf("registry", "default", "minimal") }
    assert_equal 2, unreachable.status
    assert_match(/error: no such bundle: minimal/, unreachable.err)

    assert_equal 0, okf("registry", "default", "minimal").status
    assert_equal %w[minimal conformant], registry_slugs
    assert_equal %w[conformant], slugs_in(File.join(other, "registry.json")),
      "the other home's registry is untouched by this one's choice"
  end

  test "defaulting to a bundle whose directory vanished is refused (exit 2)" do
    # `registry set` already refuses a directory that is not there; choosing one
    # as the default is the same explicit ask, so it fails the same way. It also
    # has to: the default is the first bundle still on disk, so a registry that
    # let this through would answer `default bundle → conformant` to someone who
    # typed `doomed`.
    doomed = scratch_bundle("doomed")
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", doomed)
    FileUtils.rm_rf(doomed)

    result = okf("registry", "default", "doomed")

    assert_equal 2, result.status
    assert_match(/^error: cannot default to doomed: #{Regexp.escape(doomed)} is not a directory/, result.err)
    assert_match(/okf registry del doomed, or restore it/, result.err, "a refusal with no way forward is a dead end")
    assert_empty result.out
    assert_equal %w[conformant doomed], registry_slugs, "a refused choice reorders nothing"
  end

  test "a stray extra positional is a usage error (exit 2), and nothing is chosen" do
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", fixture("minimal"))

    result = okf("registry", "default", "minimal", "extra")

    assert_equal 2, result.status
    assert_match(/error: unexpected argument 'extra'/, result.err)
    assert_equal %w[conformant minimal], registry_slugs, "the order the registrations left"
  end

  test "no slug at all prints the banner (exit 2)" do
    okf("registry", "set", fixture("conformant"))

    result = okf("registry", "default")

    assert_equal 2, result.status
    assert_match(/Usage: okf registry default <@slug>/, result.err)
    assert_match(/moves it to the front/, result.err, "the banner says the move, since the file visibly reorders")
    assert_empty result.out
  end

  test "a group slug cannot be made the default — a group is not one bundle" do
    okf("registry", "set", fixture("conformant"))
    okf("registry", "group", "docs", "@conformant")

    result = okf("registry", "default", "@docs")

    assert_equal 2, result.status
    assert_match(/cannot default to a group/, result.err)
    assert_equal %w[conformant], registry_slugs, "the order is untouched"
  end

  private

  # The registry's slugs in on-disk order — the first is the default.
  def registry_slugs
    slugs_in(File.join(@home, "registry.json"))
  end

  def slugs_in(path)
    JSON.parse(read_utf8(path))["bundles"].map { |row| row["slug"] }
  end
end
