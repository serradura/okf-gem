# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf registry default` end-to-end — choosing which registered bundle a bare
# `okf server` opens at `/`. The choice is asserted where a user reads it: the
# star in `registry list`, and the "default" key in the file on disk.
#
# Every run here is pinned to the scratch @home, so the suite never reads or
# writes the developer's own ~/.okf.
class CLIRegistryDefaultTest < CLIIntegrationCase
  test "choosing a slug stars it in the listing" do
    okf("registry", "set", fixture("conformant"), "--home", @home)
    okf("registry", "set", fixture("minimal"), "--home", @home)

    result = okf("registry", "default", "minimal", "--home", @home)

    assert_equal 0, result.status
    assert_equal "default bundle → minimal\n", result.out
    listing = okf("registry", "list", "--home", @home).out
    assert_match(/^\* minimal/, listing)
    assert_match(/^ {2}conformant/, listing, "the star moves — it never doubles")
  end

  test "the chosen default persists — later commands and the file agree" do
    okf("registry", "set", fixture("conformant"), "--home", @home)
    okf("registry", "set", fixture("minimal"), "--home", @home)

    okf("registry", "default", "minimal", "--home", @home)

    assert_equal "minimal", registry_json["default"]
    okf("registry", "set", fixture("empty"), "--home", @home) # an unrelated write
    assert_equal "minimal", registry_json["default"], "registering another bundle must not disturb the choice"
    assert_match(/^\* minimal/, okf("registry", "list", "--home", @home).out)
    assert_equal true, json(okf("registry", "list", "--json", "--home", @home))["bundles"]
      .find { |row| row["slug"] == "minimal" }["default"]
  end

  test "an unknown slug is a usage error (exit 2) and keeps the incumbent" do
    okf("registry", "set", fixture("conformant"), "--home", @home)
    okf("registry", "set", fixture("minimal"), "--home", @home)
    okf("registry", "default", "minimal", "--home", @home)

    result = okf("registry", "default", "ghost", "--home", @home)

    assert_equal 2, result.status
    assert_match(/error: no such bundle: ghost/, result.err)
    assert_empty result.out
    assert_equal "minimal", registry_json["default"]
  end

  test "with no explicit default the first registered entry is the effective default" do
    okf("registry", "set", fixture("minimal"), "--home", @home)
    okf("registry", "set", fixture("conformant"), "--home", @home)

    refute_includes registry_json.keys, "default", "nothing was chosen, so nothing is written"
    listing = okf("registry", "list", "--home", @home).out
    assert_match(/^\* minimal/, listing, "the first registered entry stars by fallback")
    assert_match(/^ {2}conformant/, listing)
  end

  test "a default that no longer exists falls back to the first — the choice is cleared, not remembered" do
    okf("registry", "set", fixture("conformant"), "--home", @home)
    okf("registry", "set", fixture("minimal"), "--home", @home)
    okf("registry", "default", "minimal", "--home", @home)

    okf("registry", "del", "minimal", "--home", @home)
    assert_match(/^\* conformant/, okf("registry", "list", "--home", @home).out)

    okf("registry", "set", fixture("minimal"), "--home", @home) # back, under the same slug
    assert_match(/^\* conformant/, okf("registry", "list", "--home", @home).out,
      "re-registering the deleted bundle must not resurrect its old claim on `/`")
    refute_includes registry_json.keys, "default"
  end

  test "the slug is normalized: @minimal and MINIMAL choose the same bundle; a bare @ does not" do
    okf("registry", "set", fixture("conformant"), "--home", @home)
    okf("registry", "set", fixture("minimal"), "--home", @home)

    at_ref = okf("registry", "default", "@minimal", "--home", @home)
    assert_equal 0, at_ref.status
    assert_equal "default bundle → minimal\n", at_ref.out, "the @ normalizes away — the ref spelling resolves"

    okf("registry", "default", "conformant", "--home", @home)
    cased = okf("registry", "default", "MINIMAL", "--home", @home)
    assert_equal 0, cased.status
    assert_equal "minimal", registry_json["default"], "the ask is normalized the way registration normalized it"

    # A bare @ means "the current default", exactly as it does for `del` — the
    # slug verbs read the ref grammar deliberately now, rather than by way of
    # normalize happening to strip the @ off a slug and choke on a lone one.
    bare = okf("registry", "default", "@", "--home", @home)
    assert_equal 0, bare.status
    assert_equal "minimal", registry_json["default"], "choosing the current default is a coherent no-op"
  end

  test "--home picks the registry the choice lands in" do
    other = File.join(@out_dir, "other-home")
    okf("registry", "set", fixture("conformant"), "--home", @home)
    okf("registry", "set", fixture("minimal"), "--home", @home)
    okf("registry", "set", fixture("conformant"), "--home", other)

    unreachable = okf("registry", "default", "minimal", "--home", other)
    assert_equal 2, unreachable.status
    assert_match(/error: no such bundle: minimal/, unreachable.err)

    assert_equal 0, okf("registry", "default", "minimal", "--home", @home).status
    assert_equal "minimal", registry_json["default"]
    refute_includes JSON.parse(File.read(File.join(other, "registry.json"))).keys, "default",
      "the other home's registry is untouched by this one's choice"
  end

  test "a stray extra positional is a usage error (exit 2), and nothing is chosen" do
    okf("registry", "set", fixture("conformant"), "--home", @home)
    okf("registry", "set", fixture("minimal"), "--home", @home)

    result = okf("registry", "default", "minimal", "extra", "--home", @home)

    assert_equal 2, result.status
    assert_match(/error: unexpected argument 'extra'/, result.err)
    refute_includes registry_json.keys, "default"
  end

  test "no slug at all prints the banner (exit 2)" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    result = okf("registry", "default", "--home", @home)

    assert_equal 2, result.status
    assert_match(/Usage: okf registry default <slug> \[--home DIR\]/, result.err)
    assert_empty result.out
  end

  private

  # The registry as it sits on disk under the scratch home.
  def registry_json
    JSON.parse(File.read(File.join(@home, "registry.json")))
  end
end
