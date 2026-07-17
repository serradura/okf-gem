# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf registry set` end-to-end — adding a bundle to the persistent registry, or
# updating one already there. The entry is keyed by the bundle's *path*: a known
# path refreshes in place (and --as renames it), a new one is added under a slug
# minted from the directory basename.
#
# Every invocation here pins --home (or $OKF_HOME, via with_registry) at the
# scratch home the base class makes and removes — the real ~/.okf is never read
# or written.
class CLIRegistrySetTest < CLIIntegrationCase
  test "registering a directory reports the slug it took, where it landed, and its size" do
    result = okf("registry", "set", fixture("conformant"), "--home", @home)

    assert_equal 0, result.status
    assert_equal "registered conformant → #{fixture("conformant")} (3 concepts)\n", result.out
    assert_equal [ "conformant" ], OKF::Registry.load(home: @home).slugs
  end

  test "the reported concept count comes from the bundle, so a typo'd path is caught at once" do
    assert_match(/\(3 concepts\)/, okf("registry", "set", fixture("conformant"), "--home", @home).out)
    assert_match(/\(1 concept\)/, okf("registry", "set", fixture("minimal"), "--home", @home).out)
    assert_match(/\(0 concepts\)/, okf("registry", "set", fixture("empty"), "--home", @home).out, "an empty dir registers, and says it is empty")
  end

  test "the slug derives from the directory basename and is silently deduped on collision" do
    first = scratch_bundle("x/notes")
    second = scratch_bundle("y/notes")

    assert_match(/^registered notes → /, okf("registry", "set", first, "--home", @home).out)
    assert_match(/^registered notes-2 → /, okf("registry", "set", second, "--home", @home).out, "a basename collision suffixes rather than refusing")
    assert_equal %w[notes notes-2], OKF::Registry.load(home: @home).slugs
  end

  test "--as sets the slug explicitly" do
    result = okf("registry", "set", fixture("conformant"), "--as", "handbook", "--home", @home)

    assert_equal 0, result.status
    assert_match(/^registered handbook → #{Regexp.escape(fixture("conformant"))} /, result.out)
    assert_equal [ "handbook" ], OKF::Registry.load(home: @home).slugs
  end

  test "--as is slugified — the name a URL can carry, not the name as typed" do
    result = okf("registry", "set", fixture("minimal"), "--as", "My Docs", "--home", @home)

    assert_equal 0, result.status
    assert_match(/^registered my-docs → /, result.out)
    assert_equal [ "my-docs" ], OKF::Registry.load(home: @home).slugs
  end

  test "--as collides with another entry and raises (exit 2) rather than suffixing" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    result = okf("registry", "set", fixture("minimal"), "--as", "conformant", "--home", @home)

    assert_equal 2, result.status
    assert_match(/^error: slug already taken: conformant \(rename or remove that entry first\)$/, result.err)
    assert_equal [ "conformant" ], OKF::Registry.load(home: @home).slugs, "an explicit ask never mints conformant-2 behind the user's back"
  end

  test "an --as with nothing slug-shaped left in it is a usage error, not a placeholder" do
    result = okf("registry", "set", fixture("minimal"), "--as", "***", "--home", @home)

    assert_equal 2, result.status
    assert_match(/^error: not a usable slug: \*\*\* \(letters and digits, please\)$/, result.err)
    assert_empty OKF::Registry.load(home: @home).slugs, "the placeholder slug is never substituted for a name the user did not choose"
  end

  test "re-setting the same path updates it in place; --as renames that entry" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    again = okf("registry", "set", fixture("conformant"), "--home", @home)
    assert_equal 0, again.status
    assert_match(/^updated conformant → /, again.out, "an update must not report itself as a fresh registration")
    assert_equal 1, OKF::Registry.load(home: @home).size, "the same path registered twice is one entry, not a twin"

    renamed = okf("registry", "set", fixture("conformant"), "--as", "handbook", "--home", @home)
    assert_match(/^updated handbook → /, renamed.out)
    reg = OKF::Registry.load(home: @home)
    assert_equal [ "handbook" ], reg.slugs, "--as on a known path renames the entry"
    assert_equal 1, reg.size
  end

  test "a relative path finds the entry registered under its absolute spelling" do
    okf("registry", "set", fixture("conformant"), "--home", @home)
    relative = relative_to_cwd(fixture("conformant"))

    result = okf("registry", "set", relative, "--home", @home)

    assert_match(/^updated conformant → #{Regexp.escape(fixture("conformant"))} /, result.out, "the path is expanded before the lookup")
    assert_equal 1, OKF::Registry.load(home: @home).size
  end

  test "a re-set refreshes a title that has gone stale on disk" do
    write_registry("bundles" => [ { "slug" => "conformant", "path" => fixture("conformant"), "title" => "STALE" } ])

    result = okf("registry", "set", fixture("conformant"), "--home", @home)

    assert_match(/^updated conformant → /, result.out, "the hand-written entry was read, so this is a refresh of it")
    assert_equal "fixtures/conformant", OKF::Registry.load(home: @home).get("conformant").title
  end

  test "--default makes it the bundle a bare `okf server` opens" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    assert_equal 0, okf("registry", "set", fixture("minimal"), "--default", "--home", @home).status
    assert_equal "minimal", OKF::Registry.load(home: @home).default.slug, "--default takes the default from the incumbent"
    assert_equal "minimal", registry_json["default"], "the choice is persisted, not just reported"
  end

  test "the on-disk registry is a JSON object of absolute-path entries" do
    okf("registry", "set", fixture("conformant"), "--as", "handbook", "--home", @home)

    payload = registry_json
    assert_equal [ "bundles" ], payload.keys, "no default key is written until a bundle is explicitly chosen"
    assert_equal 1, payload["bundles"].size
    entry = payload["bundles"].first
    assert_equal %w[path slug title], entry.keys.sort
    assert_equal "handbook", entry["slug"]
    assert_equal fixture("conformant"), entry["path"], "the path is stored absolute, so the entry survives a cwd change"
    assert_equal "fixtures/conformant", entry["title"]
  end

  test "--home writes to that registry, and $OKF_HOME is ignored when it is given" do
    other = File.join(@out_dir, "other-home")

    # with_registry pins $OKF_HOME at @home for the block; --home must still win.
    with_registry do
      assert_equal 0, okf("registry", "set", fixture("minimal"), "--home", other).status
    end

    assert_equal [ "minimal" ], OKF::Registry.load(home: other).slugs
    assert_empty OKF::Registry.load(home: @home).slugs, "the $OKF_HOME registry was left untouched"
  end

  test "$OKF_HOME is the registry when no --home is given" do
    with_registry do
      assert_equal 0, okf("registry", "set", fixture("minimal")).status
    end

    assert_equal [ "minimal" ], OKF::Registry.load(home: @home).slugs
  end

  test "an @ref positional resolves through the registry --home names" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    result = okf("registry", "set", "@conformant", "--home", @home)

    assert_equal 0, result.status
    assert_match(/^updated conformant → #{Regexp.escape(fixture("conformant"))} \(3 concepts\)/, result.out)
    assert_equal 1, OKF::Registry.load(home: @home).size, "the ref resolved to the entry it names, not to a second one"
  end

  test "an @ref reads the registry --home names, not the one $OKF_HOME names" do
    other = File.join(@out_dir, "other-home")

    # @home knows @conformant; `other` is empty. With --home pointing at `other`
    # the ref must fail — if it resolved, it read $OKF_HOME behind --home's back.
    with_registry("conformant") do
      result = okf("registry", "set", "@conformant", "--home", other)

      assert_equal 2, result.status
      assert_match(/^error: not a registered bundle: @conformant in #{Regexp.escape(File.join(other, "registry.json"))} /, result.err)
      assert_match(/\(okf registry set <dir>\)$/, result.err, "the hint fits the empty registry it actually read")
    end
  end

  test "an unknown @ref is a usage error naming the registry it consulted" do
    okf("registry", "set", fixture("conformant"), "--home", @home)

    result = okf("registry", "set", "@ghost", "--home", @home)

    assert_equal 2, result.status
    assert_match(/^error: not a registered bundle: @ghost in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry list\)$/, result.err)
    assert_equal 1, OKF::Registry.load(home: @home).size
  end

  test "a missing path and a non-directory are usage errors (exit 2), reported not raised" do
    ghost = okf("registry", "set", File.join(BUNDLES, "does-not-exist"), "--home", @home)
    assert_equal 2, ghost.status
    assert_match(/^error: #{Regexp.escape(File.join(BUNDLES, "does-not-exist"))} is not a directory$/, ghost.err)
    refute_match(/\.rb:\d+/, ghost.err, "a bad path argument is a message, never a backtrace")

    file = okf("registry", "set", File.join(fixture("minimal"), "note.md"), "--home", @home)
    assert_equal 2, file.status
    assert_match(/is not a directory$/, file.err, "a file is not a bundle")

    refute_path_exists File.join(@home, "registry.json"), "a failed set writes no registry at all"
  end

  test "a stray extra positional is rejected, not silently dropped" do
    result = okf("registry", "set", fixture("conformant"), fixture("minimal"), "--home", @home)

    assert_equal 2, result.status
    assert_match(/^error: unexpected argument '#{Regexp.escape(fixture("minimal"))}'$/, result.err)
    refute_path_exists File.join(@home, "registry.json"), "nothing was half-registered before the complaint"
  end

  test "a bundle-less set prints the banner and exits 2" do
    result = okf("registry", "set", "--home", @home)

    assert_equal 2, result.status
    assert_match(/^Usage: okf registry set <bundle-dir> \[--as SLUG\] \[--default\] \[--home DIR\]$/, result.err)
  end

  private

  # A one-concept bundle under @out_dir, at a relative +path+ (so two can share a
  # basename under different parents). Returns its absolute directory.
  def scratch_bundle(path)
    dir = File.join(@out_dir, path)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "note.md"), "---\ntype: Note\ntitle: Scratch Note\n---\n\nA scratch concept.\n")
    dir
  end

  # Plant a registry file in the scratch home by hand — the way a user editing it
  # (or an older okf) would leave one.
  def write_registry(payload)
    FileUtils.mkdir_p(@home)
    File.write(File.join(@home, "registry.json"), JSON.generate(payload))
  end

  def registry_json
    JSON.parse(File.read(File.join(@home, "registry.json")))
  end

  def relative_to_cwd(path)
    Pathname.new(path).relative_path_from(Pathname.new(Dir.pwd)).to_s
  end
end
