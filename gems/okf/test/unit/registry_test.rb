# frozen_string_literal: true

require "test_helper"
require "okf"
require "okf/registry"

# OKF::Registry — the persistent, ordered JSON registry behind a bundle-less
# server. Every test passes home: a tmpdir — the library seam that names a
# registry without touching $OKF_HOME — so the real ~/.okf is never read or
# written.
class OKF::RegistryTest < OKF::TestCase
  setup do
    @home = Dir.mktmpdir("okf-registry-home")
    @bundles = Dir.mktmpdir("okf-registry-bundles")
  end

  teardown do
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@bundles)
  end

  test "add registers a bundle, slugged by basename, and persists it" do
    dir = bundle("orders")

    entry = registry.add(dir)

    assert_equal "orders", entry.slug
    assert_equal File.expand_path(dir), entry.path
    assert_equal [ "orders" ], reload.slugs, "a fresh load sees the persisted entry"
    assert File.exist?(OKF::Registry.path(home: @home))
  end

  test "the first-registered bundle is the default; order is preserved" do
    registry.add(bundle("alpha"))
    registry.add(bundle("beta"))

    reg = reload
    assert_equal "alpha", reg.default.slug
    assert_equal %w[alpha beta], reg.slugs
  end

  test "a slug collision is deduped with a numeric suffix" do
    reg = registry
    reg.add(bundle("shared/docs"))
    reg.add(bundle("other/docs"))

    assert_equal %w[docs docs-2], reg.slugs
  end

  test "--as overrides the derived slug" do
    entry = registry.add(bundle("orders"), as: "sales")

    assert_equal "sales", entry.slug
  end

  test "re-registering the same path updates in place, not a duplicate" do
    dir = bundle("orders")
    reg = registry
    reg.add(dir)
    first_count = reg.size

    reg.add(dir)

    assert_equal first_count, reg.size, "same path does not add a second entry"
    assert_equal 1, reload.size
  end

  test "remove deletes by slug and by path, and persists" do
    reg = registry
    dir = bundle("orders")
    reg.add(dir)
    reg.add(bundle("notes"))

    assert_equal "orders", reg.remove("orders").slug
    assert_equal [ "notes" ], reg.slugs
    assert_nil reg.remove("ghost"), "removing an unknown slug returns nil"

    reg.add(dir)
    assert reg.remove(dir), "remove also matches an absolute path"
    assert_equal [ "notes" ], reload.slugs
  end

  test "listing exposes disk dir, mount path, default and missing flags" do
    dir = bundle("orders")
    registry.add(dir)

    assert_equal [ { slug: "orders", title: File.basename(@bundles) + "/orders", dir: File.expand_path(dir),
                     mount: "/b/orders/", default: true, missing: false } ],
      reload.listing
  end

  test "listing flags a registered directory that vanished" do
    dir = bundle("orders")
    registry.add(dir)
    FileUtils.rm_rf(dir)

    assert_equal [ true ], reload.listing.map { |row| row[:missing] }
  end

  test "--as raises on a slug collision instead of silently suffixing" do
    registry.add(bundle("orders"))

    error = assert_raises(OKF::Error) { registry.add(bundle("notes"), as: "orders") }
    assert_match(/slug already taken/, error.message)
    assert_equal [ "orders" ], reload.slugs, "the colliding registration is not persisted"
  end

  test "an empty OKF_HOME env var counts as unset, not the current directory" do
    was = ENV.fetch("OKF_HOME", nil)
    begin
      ENV["OKF_HOME"] = ""
      assert_equal File.join(File.expand_path("~/.okf"), "registry.json"), OKF::Registry.path
    ensure
      was.nil? ? ENV.delete("OKF_HOME") : ENV["OKF_HOME"] = was
    end
  end

  test "writes promote via rename — no temp file left behind" do
    registry.add(bundle("orders"))

    leftovers = Dir.entries(@home).reject { |name| [ ".", "..", "registry.json" ].include?(name) }
    assert_empty leftovers
  end

  test "default= moves the entry to the front, and default resolves to it" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.add(bundle("beta"))

    reg.default = "beta"

    assert_equal "beta", reload.default.slug
    assert_equal %w[beta alpha], reload.slugs, "the default is the first entry, so choosing one moves it"
    assert_equal [ true, false ], reload.listing.map { |row| row[:default] }
  end

  test "default is the first entry when nothing was ever chosen, and nil when empty" do
    reg = registry
    assert_nil reg.default

    reg.add(bundle("alpha"))
    reg.add(bundle("beta"))

    assert_equal "alpha", reload.default.slug
  end

  test "default= rejects an unknown slug" do
    registry.add(bundle("alpha"))

    assert_raises(OKF::Error) { registry.default = "ghost" }
  end

  test "removing the default falls back to the first registered" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.add(bundle("beta"))
    reg.default = "beta"

    reg.remove("beta")

    assert_equal "alpha", reload.default.slug
  end

  test "add with default: true takes the default from the incumbent" do
    reg = registry
    reg.add(bundle("alpha"))

    reg.add(bundle("beta"), default: true)

    assert_equal "beta", reload.default.slug
  end

  test "rename slugifies the new name, follows the default, and persists" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.add(bundle("beta"))
    reg.default = "beta"

    entry = reg.rename("beta", "Prod Docs!")

    assert_equal "prod-docs", entry.slug
    fresh = reload
    assert_equal %w[prod-docs alpha], fresh.slugs, "beta was moved to the front by default=; the rename leaves it there"
    assert_equal "prod-docs", fresh.default.slug
  end

  test "rename rejects an unknown slug and a collision" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.add(bundle("beta"))

    assert_raises(OKF::Error) { reg.rename("ghost", "x") }
    assert_raises(OKF::Error) { reg.rename("beta", "alpha") }
    assert_equal %w[alpha beta], reg.slugs, "a failed rename mutates nothing"
  end

  test "a bare-array registry file (the original shape) still reads, defaulting to the first" do
    FileUtils.mkdir_p(@home)
    rows = [ { "slug" => "a", "path" => "/x", "title" => "t" } ]
    File.write(OKF::Registry.path(home: @home), JSON.generate(rows))

    reg = registry
    assert_equal [ "a" ], reg.slugs
    assert_equal "a", reg.default.slug
  end

  test "a missing registry file loads as empty" do
    assert_empty registry
    assert_nil registry.default
  end

  test "a malformed registry file raises a clear error" do
    FileUtils.mkdir_p(@home)
    File.write(OKF::Registry.path(home: @home), "{ not json")

    error = assert_raises(OKF::Error) { registry }
    assert_match(/malformed registry/, error.message)
  end

  test "adding a non-directory raises" do
    assert_raises(OKF::Error) { registry.add(File.join(@bundles, "nope")) }
  end

  test "path honours an explicit home: over $OKF_HOME and the ~/.okf default" do
    assert_equal File.join(File.expand_path(@home), "registry.json"), OKF::Registry.path(home: @home)
  end

  test "an unexpandable home is an OKF::Error, not a raw ArgumentError" do
    # File.expand_path raises ArgumentError for a ~user that does not exist.
    # It is a bad argument, so it must arrive as the error the CLI turns into
    # exit 2 — never as a backtrace.
    error = assert_raises(OKF::Error) { OKF::Registry.path(home: "~nosuchuser") }
    assert_match(/cannot expand ~nosuchuser/, error.message)
  end

  test "add reports an unexpandable path as an OKF::Error" do
    assert_raises(OKF::Error) { registry.add("~nosuchuser") }
  end

  test "remove reports an unexpandable path as an OKF::Error once there is an entry to compare" do
    reg = registry
    # An empty registry never reaches the path comparison (find skips the
    # block), so the raise needs an entry to compare against.
    reg.add(bundle("one"))

    assert_raises(OKF::Error) { reg.remove("~nosuchuser") }
  end

  test "the slug verbs normalize the ask, so the name typed at --as resolves" do
    reg = registry
    reg.add(bundle("one"), as: "My Docs") # stored normalized: "my-docs"

    reg.default = "My Docs"
    assert_equal "my-docs", reload.default.slug

    reg.rename("My Docs", "Team Notes")
    assert_equal [ "team-notes" ], reload.slugs

    assert reload.remove("Team Notes"), "remove reads the same name back"
    assert_empty reload.slugs
  end

  test "remove prefers a registered directory over the slug that name normalizes to" do
    reg = registry
    docs = bundle("docs")
    reg.add(bundle("other"), as: "docs") # the slug "docs" is NOT the docs/ dir
    reg.add(docs)                        # registered as "docs-2"

    reg.remove(docs) # a path — must remove the directory's entry, not the "docs" slug
    assert_equal [ "docs" ], reload.slugs
    assert_equal File.join(@bundles, "other"), reload.get("docs").path
  end

  test "slugify and dedupe normalize and disambiguate" do
    assert_equal "my-bundle", OKF::Registry.slugify("My Bundle!")
    assert_equal "bundle", OKF::Registry.slugify("---")
    assert_equal "x-2", OKF::Registry.dedupe("x", [ "x" ])
    assert_equal "x-3", OKF::Registry.dedupe("x", %w[x x-2])
  end

  # ── groups: a named, recursive set of bundle slugs ──

  test "set_group names a set of bundle slugs, and expand resolves it to entries" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.add(bundle("beta"))

    group = reg.set_group("backend", %w[@alpha @beta])

    assert_equal "backend", group.slug
    assert_equal %w[alpha beta], group.members
    assert_equal %w[alpha beta], reload.expand("backend").map(&:slug), "a fresh load resolves the persisted group"
  end

  test "set_group on an existing group adds members as a union, order-preserving" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.add(bundle("beta"))
    reg.set_group("backend", %w[alpha])

    reg.set_group("backend", %w[alpha beta])

    assert_equal %w[alpha beta], reload.group?("backend").members, "an already-present member is not duplicated"
  end

  test "expand flattens nested groups and dedupes by path, order-preserving" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.add(bundle("beta"))
    reg.add(bundle("gamma"))
    reg.set_group("inner", %w[beta gamma])
    reg.set_group("outer", %w[alpha inner beta])

    assert_equal %w[alpha beta gamma], reg.expand("outer").map(&:slug),
      "inner expands in place, and beta (named twice) resolves once"
  end

  test "set_group refuses a member set that would make the group reach itself" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.set_group("a", %w[alpha])
    reg.set_group("b", %w[a])

    error = assert_raises(OKF::Error) { reg.set_group("a", %w[b]) }
    assert_match(/cycle/, error.message)
    assert_equal %w[alpha], reload.group?("a").members, "the cyclic edit is not persisted"
  end

  test "set_group refuses a direct self-reference" do
    reg = registry
    reg.add(bundle("alpha"))

    assert_raises(OKF::Error) { reg.set_group("a", %w[a alpha]) }
  end

  test "a group slug collides with a bundle slug in one namespace" do
    reg = registry
    reg.add(bundle("alpha"))

    assert_raises(OKF::Error) { reg.set_group("alpha", %w[alpha]) }
  end

  test "a bundle cannot claim a slug a group already holds" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.set_group("backend", %w[alpha])

    assert_raises(OKF::Error) { reg.add(bundle("beta"), as: "backend") }
    assert_nil reload.get("backend"), "the colliding bundle registration is not persisted"
  end

  test "set_group rejects an unknown member and the reserved name" do
    reg = registry
    reg.add(bundle("alpha"))

    assert_raises(OKF::Error) { reg.set_group("backend", %w[ghost]) }
    assert_raises(OKF::Error) { reg.set_group("all", %w[alpha]) }
    assert_raises(OKF::Error) { reg.set_group("backend", []) }
  end

  test "unset_group_members removes members, and empties delete the group" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.add(bundle("beta"))
    reg.set_group("backend", %w[alpha beta])

    removed, emptied = reg.unset_group_members("backend", %w[alpha])
    assert_equal %w[alpha], removed
    refute emptied
    assert_equal %w[beta], reload.group?("backend").members

    _removed, emptied = reg.unset_group_members("backend", %w[beta])
    assert emptied
    assert_nil reload.group?("backend"), "removing the last member deletes the group"
  end

  test "unset_group_members raises on an unknown group, no-ops a non-member" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.set_group("backend", %w[alpha])

    assert_raises(OKF::Error) { reg.unset_group_members("ghost", %w[alpha]) }
    removed, = reg.unset_group_members("backend", %w[beta])
    assert_equal [], removed, "removing a non-member changes nothing"
    assert_equal %w[alpha], reload.group?("backend").members
  end

  test "removing a bundle cascade-drops it from groups, deleting any it empties" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.add(bundle("beta"))
    reg.set_group("backend", %w[alpha beta])
    reg.set_group("solo", %w[alpha])

    reg.remove("alpha")

    assert_equal %w[beta], reload.group?("backend").members, "the surviving member stays"
    assert_nil reload.group?("solo"), "a group emptied by the cascade is deleted"
  end

  test "removing a group by slug drops it from any parent group" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.add(bundle("beta"))
    reg.set_group("inner", %w[beta])
    reg.set_group("outer", %w[alpha inner])

    removed = reg.remove("inner")

    assert_equal "inner", removed.slug
    assert_equal %w[alpha], reload.group?("outer").members, "the parent no longer names the deleted group"
    assert_nil reload.group?("inner")
  end

  test "renaming a bundle propagates into every group that names it" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.add(bundle("beta"))
    reg.set_group("backend", %w[alpha beta])

    reg.rename("alpha", "core")

    assert_equal %w[core beta], reload.group?("backend").members, "the member follows the rename"
  end

  test "renaming a group propagates into a parent group" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.set_group("inner", %w[alpha])
    reg.set_group("outer", %w[inner])

    reg.rename("inner", "core")

    assert_equal %w[core], reload.group?("outer").members
    assert_equal %w[alpha], reload.group?("core").members, "the renamed group keeps its own members"
  end

  test "renaming onto a slug a group holds is refused" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.set_group("backend", %w[alpha])

    assert_raises(OKF::Error) { reg.rename("alpha", "backend") }
    assert_equal "alpha", reload.get("alpha").slug, "a failed rename mutates nothing"
  end

  test "default= refuses a group slug" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.set_group("backend", %w[alpha])

    assert_raises(OKF::Error) { reg.default = "backend" }
  end

  test "expand raises a clear cycle error on a hand-edited cyclic file" do
    FileUtils.mkdir_p(@home)
    File.write(OKF::Registry.path(home: @home), JSON.generate(
      "bundles" => [],
      "groups" => [ { "slug" => "a", "members" => %w[b] }, { "slug" => "b", "members" => %w[a] } ]
    ))

    error = assert_raises(OKF::Error) { registry.expand("a") }
    assert_match(/group cycle/, error.message)
  end

  test "a groups-less registry file reads with no groups" do
    reg = registry
    reg.add(bundle("alpha"))

    assert_equal [], reload.groups_listing, "the original bundles-only shape carries no groups"
  end

  test "groups_listing reports each group's members and resolved leaf count" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.add(bundle("beta"))
    reg.set_group("backend", %w[alpha beta])

    assert_equal [ { slug: "backend", members: %w[alpha beta], resolved: 2 } ], reload.groups_listing
  end

  private

  def registry
    OKF::Registry.load(home: @home)
  end
  alias reload registry

  # A minimal on-disk bundle at @bundles/<name> with one concept, so Folder.load
  # succeeds. Returns its path.
  def bundle(name)
    dir = File.join(@bundles, name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "a.md"), "---\ntype: Note\ntitle: A\ndescription: d\n---\n\nhi\n")
    dir
  end
end
