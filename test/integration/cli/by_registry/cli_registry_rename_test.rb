# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf registry rename` end-to-end — giving a registered bundle a new slug, which
# is also its `/b/<slug>/` mount and its switcher name. The path never moves;
# only the name does, and the chosen default follows it.
#
# Every run here is pinned to the scratch @home, so the suite never reads or
# writes the developer's own ~/.okf.
class CLIRegistryRenameTest < CLIIntegrationCase
  test "renaming changes the slug, and with it the /b/<slug>/ mount" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    result = okf("registry", "rename", "conformant", "handbook", "--home", @home)

    assert_equal 0, result.status
    assert_equal "renamed conformant → handbook\n", result.out
    row = json(okf("registry", "list", "--json", "--home", @home))["bundles"].first
    assert_equal "handbook", row["slug"]
    assert_equal "/b/handbook/", row["mount"]
    assert_equal fixture("conformant"), row["dir"], "the bundle stays put — only its name moved"
  end

  test "the default follows the rename" do
    okf("registry", "set", fixture("conformant"), "--home", @home)
    okf("registry", "set", fixture("minimal"), "--home", @home)
    okf("registry", "default", "minimal", "--home", @home)

    assert_equal 0, okf("registry", "rename", "minimal", "tiny", "--home", @home).status

    listing = okf("registry", "list", "--home", @home).out
    assert_match(/^\* tiny/, listing, "the star moves with the bundle it marked")
    assert_match(/^ {2}conformant/, listing)
    assert_equal "tiny", registry_json["default"]
  end

  test "the new name is slugified" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    result = okf("registry", "rename", "conformant", "Team Handbook!", "--home", @home)

    assert_equal 0, result.status
    assert_equal "renamed conformant → team-handbook\n", result.out
    assert_equal "/b/team-handbook/", json(okf("registry", "list", "--json", "--home", @home))["bundles"].first["mount"]
  end

  test "a collision with another entry raises (exit 2) — explicit is explicit, never suffixed" do
    okf("registry", "set", fixture("conformant"), "--home", @home)
    okf("registry", "set", fixture("minimal"), "--home", @home)

    result = okf("registry", "rename", "minimal", "conformant", "--home", @home)

    assert_equal 2, result.status
    assert_match(/error: slug already taken: conformant/, result.err)
    assert_empty result.out
    assert_equal %w[conformant minimal], registry_json["bundles"].map { |row| row["slug"] }
    refute_match(/conformant-2/, okf("registry", "list", "--home", @home).out, "a rename never silently suffixes its way out")

    # An entry does not collide with itself: the new name is checked against the
    # *other* entries only.
    assert_equal 0, okf("registry", "rename", "minimal", "MINIMAL", "--home", @home).status
  end

  test "an unknown old slug is a usage error (exit 2)" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    result = okf("registry", "rename", "ghost", "handbook", "--home", @home)

    assert_equal 2, result.status
    assert_match(/error: no such bundle: ghost/, result.err)
    assert_empty result.out
    assert_equal %w[conformant], registry_json["bundles"].map { |row| row["slug"] }
  end

  test "a new name with nothing sluggable left is a usage error (exit 2)" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    result = okf("registry", "rename", "conformant", "***", "--home", @home)

    assert_equal 2, result.status
    assert_match(/error: not a usable slug: \*\*\* \(letters and digits, please\)/, result.err)
    assert_equal %w[conformant], registry_json["bundles"].map { |row| row["slug"] }, "no placeholder name is substituted"
  end

  test "missing args print the banner (exit 2)" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    [ [], [ "conformant" ] ].each do |args|
      result = okf("registry", "rename", *args, "--home", @home)

      assert_equal 2, result.status, "rename #{args.inspect} takes two slugs"
      assert_match(/Usage: okf registry rename <old> <new> \[--home DIR\]/, result.err)
      assert_empty result.out
    end
    assert_equal %w[conformant], registry_json["bundles"].map { |row| row["slug"] }
  end

  test "a stray extra positional is a usage error (exit 2), and nothing is renamed" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    result = okf("registry", "rename", "conformant", "handbook", "extra", "--home", @home)

    assert_equal 2, result.status
    assert_match(/error: unexpected argument 'extra'/, result.err)
    assert_equal %w[conformant], registry_json["bundles"].map { |row| row["slug"] }
  end

  test "--home picks the registry the rename lands in" do
    other = File.join(@out_dir, "other-home")
    okf("registry", "set", fixture("conformant"), "--home", @home)
    okf("registry", "set", fixture("minimal"), "--home", other)

    stray = okf("registry", "rename", "conformant", "handbook", "--home", other)

    assert_equal 2, stray.status
    assert_match(/error: no such bundle: conformant/, stray.err)
    assert_equal %w[conformant], registry_json["bundles"].map { |row| row["slug"] },
      "the other home's rename cannot reach this one"
  end

  test "the on-disk JSON after a rename moves the slug and leaves the rest alone" do
    okf("registry", "set", fixture("conformant"), "--home", @home)
    okf("registry", "set", fixture("minimal"), "--home", @home)
    okf("registry", "default", "conformant", "--home", @home)

    okf("registry", "rename", "conformant", "handbook", "--home", @home)

    data = registry_json
    assert_equal "handbook", data["default"]
    assert_equal %w[handbook minimal], data["bundles"].map { |row| row["slug"] }, "registration order survives the rename"
    entry = data["bundles"].first
    assert_equal fixture("conformant"), entry["path"]
    assert_equal "fixtures/conformant", entry["title"]
  end

  private

  # The registry as it sits on disk under the scratch home.
  def registry_json
    JSON.parse(File.read(File.join(@home, "registry.json")))
  end
end
