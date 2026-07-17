# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf registry set` end-to-end — adding a bundle to the persistent registry, or
# updating one already there. The entry is keyed by the bundle's *path*: a known
# path refreshes in place (and --as renames it), a new one is added under a slug
# minted from the directory basename.
#
# $OKF_HOME is pinned at the scratch home the base class makes and removes — the real ~/.okf is never read
# or written.
class CLIRegistrySetTest < CLIIntegrationCase
  test "registering a directory reports the slug it took, where it landed, and its size" do
    result = okf("registry", "set", fixture("conformant"))

    assert_equal 0, result.status
    assert_equal "registered conformant → #{fixture("conformant")} (3 concepts)\n", result.out
    assert_equal [ "conformant" ], OKF::Registry.load(home: @home).slugs
  end

  test "the reported concept count comes from the bundle, so a typo'd path is caught at once" do
    assert_match(/\(3 concepts\)/, okf("registry", "set", fixture("conformant")).out)
    assert_match(/\(1 concept\)/, okf("registry", "set", fixture("minimal")).out)
    assert_match(/\(0 concepts\)/, okf("registry", "set", fixture("empty")).out, "an empty dir registers, and says it is empty")
  end

  test "the slug derives from the directory basename and is silently deduped on collision" do
    first = scratch_bundle("x/notes")
    second = scratch_bundle("y/notes")

    assert_match(/^registered notes → /, okf("registry", "set", first).out)
    assert_match(/^registered notes-2 → /, okf("registry", "set", second).out, "a basename collision suffixes rather than refusing")
    assert_equal %w[notes notes-2], OKF::Registry.load(home: @home).slugs
  end

  test "--as sets the slug explicitly" do
    result = okf("registry", "set", fixture("conformant"), "--as", "handbook")

    assert_equal 0, result.status
    assert_match(/^registered handbook → #{Regexp.escape(fixture("conformant"))} /, result.out)
    assert_equal [ "handbook" ], OKF::Registry.load(home: @home).slugs
  end

  test "--as is slugified — the name a URL can carry, not the name as typed" do
    result = okf("registry", "set", fixture("minimal"), "--as", "My Docs")

    assert_equal 0, result.status
    assert_match(/^registered my-docs → /, result.out)
    assert_equal [ "my-docs" ], OKF::Registry.load(home: @home).slugs
  end

  test "--as collides with another entry and raises (exit 2) rather than suffixing" do
    okf("registry", "set", fixture("conformant"))

    result = okf("registry", "set", fixture("minimal"), "--as", "conformant")

    assert_equal 2, result.status
    assert_match(/^error: slug already taken: conformant \(rename or remove that entry first\)$/, result.err)
    assert_equal [ "conformant" ], OKF::Registry.load(home: @home).slugs, "an explicit ask never mints conformant-2 behind the user's back"
  end

  test "an --as with nothing slug-shaped left in it is a usage error, not a placeholder" do
    result = okf("registry", "set", fixture("minimal"), "--as", "***")

    assert_equal 2, result.status
    assert_match(/^error: not a usable slug: \*\*\* \(letters and digits, please\)$/, result.err)
    assert_empty OKF::Registry.load(home: @home).slugs, "the placeholder slug is never substituted for a name the user did not choose"
  end

  test "re-setting the same path updates it in place; --as renames that entry" do
    okf("registry", "set", fixture("conformant"))

    again = okf("registry", "set", fixture("conformant"))
    assert_equal 0, again.status
    assert_match(/^updated conformant → /, again.out, "an update must not report itself as a fresh registration")
    assert_equal 1, OKF::Registry.load(home: @home).size, "the same path registered twice is one entry, not a twin"

    renamed = okf("registry", "set", fixture("conformant"), "--as", "handbook")
    assert_match(/^updated handbook → /, renamed.out)
    reg = OKF::Registry.load(home: @home)
    assert_equal [ "handbook" ], reg.slugs, "--as on a known path renames the entry"
    assert_equal 1, reg.size
  end

  test "a relative path finds the entry registered under its absolute spelling" do
    okf("registry", "set", fixture("conformant"))
    relative = relative_to_cwd(fixture("conformant"))

    result = okf("registry", "set", relative)

    assert_match(/^updated conformant → #{Regexp.escape(fixture("conformant"))} /, result.out, "the path is expanded before the lookup")
    assert_equal 1, OKF::Registry.load(home: @home).size
  end

  test "a re-set refreshes a title that has gone stale on disk" do
    write_registry("bundles" => [ { "slug" => "conformant", "path" => fixture("conformant"), "title" => "STALE" } ])

    result = okf("registry", "set", fixture("conformant"))

    assert_match(/^updated conformant → /, result.out, "the hand-written entry was read, so this is a refresh of it")
    assert_equal "fixtures/conformant", OKF::Registry.load(home: @home).get("conformant").title
  end

  test "--default puts it first — the bundle a bare `okf server` opens" do
    okf("registry", "set", fixture("conformant"))

    assert_equal 0, okf("registry", "set", fixture("minimal"), "--default").status
    assert_equal "minimal", OKF::Registry.load(home: @home).default.slug, "--default takes the default from the incumbent"
    assert_equal %w[minimal conformant], registry_json["bundles"].map { |row| row["slug"] },
      "it leads the file, which is what being the default now means"
  end

  test "--default on a bundle already registered moves it to the front" do
    okf("registry", "set", fixture("conformant"))
    okf("registry", "set", fixture("minimal"))
    assert_equal %w[conformant minimal], registry_json["bundles"].map { |row| row["slug"] }

    assert_equal 0, okf("registry", "set", fixture("minimal"), "--default").status

    assert_equal %w[minimal conformant], registry_json["bundles"].map { |row| row["slug"] },
      "an update promotes in place — it does not append a twin"
  end

  test "the on-disk registry is a JSON object of absolute-path entries" do
    okf("registry", "set", fixture("conformant"), "--as", "handbook")

    payload = registry_json
    assert_equal [ "bundles" ], payload.keys, "the file carries the list and nothing else — the default is its first row"
    assert_equal 1, payload["bundles"].size
    entry = payload["bundles"].first
    assert_equal %w[path slug title], entry.keys.sort
    assert_equal "handbook", entry["slug"]
    assert_equal fixture("conformant"), entry["path"], "the path is stored absolute, so the entry survives a cwd change"
    assert_equal "fixtures/conformant", entry["title"]
  end

  test "$OKF_HOME is the registry a set writes to, and each home keeps its own" do
    other = File.join(@out_dir, "other-home")

    assert_equal 0, okf("registry", "set", fixture("minimal")).status
    with_home(other) { assert_equal 0, okf("registry", "set", fixture("conformant")).status }

    assert_equal [ "minimal" ], OKF::Registry.load(home: @home).slugs
    assert_equal [ "conformant" ], OKF::Registry.load(home: other).slugs, "the other home holds only what was written there"
  end

  test "an @ref positional resolves through the registry $OKF_HOME names" do
    okf("registry", "set", fixture("conformant"))

    result = okf("registry", "set", "@conformant")

    assert_equal 0, result.status
    assert_match(/^updated conformant → #{Regexp.escape(fixture("conformant"))} \(3 concepts\)/, result.out)
    assert_equal 1, OKF::Registry.load(home: @home).size, "the ref resolved to the entry it names, not to a second one"
  end

  test "an @ref reads exactly the registry $OKF_HOME names — there is no fallback" do
    other = File.join(@out_dir, "other-home")

    # @home knows @conformant; `other` is empty. Pointed at `other`, the ref must
    # fail — resolving it would mean a second registry was consulted behind the
    # one the user named.
    with_registry("conformant") do
      result = with_home(other) { okf("registry", "set", "@conformant") }

      assert_equal 2, result.status
      assert_match(/^error: not a registered bundle: @conformant in #{Regexp.escape(File.join(other, "registry.json"))} /, result.err)
      assert_match(/\(okf registry set <dir>\)$/, result.err, "the hint fits the empty registry it actually read")
    end
  end

  test "an unknown @ref is a usage error naming the registry it consulted" do
    okf("registry", "set", fixture("conformant"))

    result = okf("registry", "set", "@ghost")

    assert_equal 2, result.status
    assert_match(/^error: not a registered bundle: @ghost in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry list\)$/, result.err)
    assert_equal 1, OKF::Registry.load(home: @home).size
  end

  test "a missing path and a non-directory are usage errors (exit 2), reported not raised" do
    ghost = okf("registry", "set", File.join(BUNDLES, "does-not-exist"))
    assert_equal 2, ghost.status
    assert_match(/^error: #{Regexp.escape(File.join(BUNDLES, "does-not-exist"))} is not a directory$/, ghost.err)
    refute_match(/\.rb:\d+/, ghost.err, "a bad path argument is a message, never a backtrace")

    file = okf("registry", "set", File.join(fixture("minimal"), "note.md"))
    assert_equal 2, file.status
    assert_match(/is not a directory$/, file.err, "a file is not a bundle")

    refute_path_exists File.join(@home, "registry.json"), "a failed set writes no registry at all"
  end

  test "a stray extra positional is rejected, not silently dropped" do
    result = okf("registry", "set", fixture("conformant"), fixture("minimal"))

    assert_equal 2, result.status
    assert_match(/^error: unexpected argument '#{Regexp.escape(fixture("minimal"))}'$/, result.err)
    refute_path_exists File.join(@home, "registry.json"), "nothing was half-registered before the complaint"
  end

  test "a bundle-less set prints the banner and exits 2" do
    result = okf("registry", "set")

    assert_equal 2, result.status
    assert_match(/^Usage: okf registry set <dir\|@slug> \[--as SLUG\] \[--default\]$/, result.err)
  end

  test "registering a bundle it cannot fully read says so, rather than reporting an empty one" do
    # Every other bundle-reading verb notes its skips; `set` builds its count
    # straight off the graph and never called report_skipped. Once the reader
    # started tolerating a file it cannot open, that silence turned a loud
    # failure into "registered → (0 concepts)" — a registration the user is told
    # is an empty bundle, with the reason never named.
    skip_unless_permissions_bite
    dir = unreadable_bundle("locked")

    result = okf("registry", "set", dir)

    assert_equal 0, result.status
    assert_match(/note: skipped 1 unusable file\(s\) \(run `okf validate` for details\)/, result.err,
      "the count is 0 because a file could not be read — say which, or the number is a lie")
    assert_match(/^registered locked → #{Regexp.escape(dir)} \(0 concepts\)$/, result.out)
  end

  test "an unwritable registry home is a usage error naming it, not a backtrace" do
    skip_unless_permissions_bite
    readonly = File.join(@out_dir, "readonly")
    FileUtils.mkdir_p(readonly)
    File.chmod(0o500, readonly)

    begin
      with_home(File.join(readonly, "home")) do
        result = okf("registry", "set", fixture("conformant"))

        assert_equal 2, result.status, "a home the registry cannot be written to is a usage error, not a failing bundle"
        refute_match(/\.rb:\d+/, result.err, "#read already turns this errno into a message; #write must not be the hole left")
        assert_match(/^error: .*ermission denied/, result.err)
      end
    ensure
      File.chmod(0o700, readonly)
    end
  end

  private

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
