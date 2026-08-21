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
                     mount: "/b/orders/", default: true, missing: false, link: nil, origin: nil } ],
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

    assert_equal [ { slug: "backend", members: %w[alpha beta], resolved: 2, link: nil } ], reload.groups_listing
  end

  # --- links -------------------------------------------------------------
  #
  # A link is a pointer from the global registry to another registry file: its
  # bundles resolve through the pointer at read time, under their own slugs
  # unless one collides. Only the global registry honours links, so there is no
  # graph to walk and no cycle to guard.

  test "a link resolves the target registry's bundles under their own slugs" do
    target = linked_file("onm", %w[central autonote])

    reg = registry
    reg.link("onm", target)

    assert_equal %w[central autonote], reload.slugs
    assert_equal "central", reload.get("central").slug
  end

  test "a linked bundle carries the link it came from; a local one does not" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.link("onm", linked_file("onm", %w[central]))

    fresh = reload
    assert_nil fresh.get("alpha").link
    assert_equal "onm", fresh.get("central").link
  end

  test "a linked slug colliding with a local one is prefixed with the link name" do
    reg = registry
    reg.add(bundle("central"))
    reg.link("onm", linked_file("onm", %w[central]))

    fresh = reload
    assert_equal %w[central onm-central], fresh.slugs
    assert_nil fresh.get("central").link, "the local bundle keeps the bare name"
    assert_equal "central", fresh.get("onm-central").origin
  end

  test "a prefixed slug that also collides falls back to a numeric suffix" do
    reg = registry
    reg.add(bundle("central"))
    reg.add(bundle("onm-central"))
    reg.link("onm", linked_file("onm", %w[central]))

    assert_equal %w[central onm-central onm-central-2], reload.slugs
  end

  test "between two links, the first in file order keeps the bare slug" do
    reg = registry
    reg.link("onm", linked_file("onm", %w[docs]))
    reg.link("work", linked_file("work", %w[docs]))

    fresh = reload
    assert_equal %w[docs work-docs], fresh.slugs
    assert_equal "onm", fresh.get("docs").link
  end

  test "the link name resolves as a group over its bundles" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.link("onm", linked_file("onm", %w[central autonote]))

    assert_equal %w[central autonote], reload.expand("onm").map(&:slug)
  end

  test "a linked registry's own links are not followed" do
    inner = linked_file("inner", %w[deep])
    outer = linked_file("outer", %w[shallow], links: { "inner" => inner })

    registry.link("outer", outer)

    assert_equal %w[shallow], reload.slugs, "the target's own links stop at depth one"
  end

  test "a link whose target is gone resolves to nothing and is reported missing" do
    target = linked_file("onm", %w[central])
    registry.link("onm", target)
    File.unlink(target)

    fresh = reload
    assert_equal [], fresh.slugs
    assert_equal [ true ], fresh.links_listing.map { |row| row[:missing] }
  end

  test "a link whose target is malformed resolves to nothing rather than raising" do
    target = File.join(@bundles, "broken.json")
    File.write(target, "{ not json")
    registry.link("onm", target)

    fresh = reload
    assert_equal [], fresh.slugs
    assert_equal [ true ], fresh.links_listing.map { |row| row[:unreadable] }
  end

  test "linked entries are not written back into the registry file" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.link("onm", linked_file("onm", %w[central]))
    reg.add(bundle("beta"))

    data = JSON.parse(File.read(OKF::Registry.path(home: @home)))
    assert_equal %w[alpha beta], data["bundles"].map { |row| row["slug"] }
    assert_equal [ "onm" ], data["links"].map { |row| row["slug"] }
  end

  test "linked entries are appended after local ones, so the default stays local" do
    reg = registry
    reg.link("onm", linked_file("onm", %w[central]))
    reg.add(bundle("alpha"))

    assert_equal "alpha", reload.default.slug
  end

  test "rename refuses a linked slug, naming the file that owns it" do
    target = linked_file("onm", %w[central])
    registry.link("onm", target)

    error = assert_raises(OKF::Error) { reload.rename("central", "core") }
    assert_match(/linked registry/, error.message)
    assert_match(/#{Regexp.escape(target)}/, error.message)
  end

  test "remove refuses a linked slug" do
    registry.link("onm", linked_file("onm", %w[central]))

    error = assert_raises(OKF::Error) { reload.remove("central") }
    assert_match(/linked registry/, error.message)
  end

  test "default= refuses a linked slug" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.link("onm", linked_file("onm", %w[central]))

    error = assert_raises(OKF::Error) { reload.default = "central" }
    assert_match(/linked registry/, error.message)
  end

  test "add refuses to re-register a bundle a link already carries" do
    dir = bundle("central")
    registry.link("onm", linked_file_for("onm", [ dir ]))

    error = assert_raises(OKF::Error) { reload.add(dir) }
    assert_match(/linked registry/, error.message)
  end

  test "a group refuses a linked member" do
    reg = registry
    reg.add(bundle("alpha"))
    reg.link("onm", linked_file("onm", %w[central]))

    error = assert_raises(OKF::Error) { reload.set_group("mixed", %w[alpha central]) }
    assert_match(/linked registry/, error.message)
  end

  test "a link name collides with a bundle slug, and a bundle slug with a link name" do
    reg = registry
    reg.add(bundle("onm"))

    assert_raises(OKF::Error) { reg.link("onm", linked_file("other", %w[central])) }

    fresh = registry
    fresh.remove("onm")
    fresh.link("onm", linked_file("other2", %w[central]))
    error = assert_raises(OKF::Error) { reload.add(bundle("elsewhere/onm"), as: "onm") }
    assert_match(/slug already taken/, error.message)
  end

  test "a link refuses a target that is not a file, and refuses itself" do
    reg = registry

    assert_raises(OKF::Error) { reg.link("onm", File.join(@bundles, "nope.json")) }
    assert_raises(OKF::Error) { reg.link("self", OKF::Registry.path(home: @home)) }
  end

  test "unlink drops the link and its bundles" do
    reg = registry
    reg.link("onm", linked_file("onm", %w[central]))

    assert_equal "onm", reload.unlink("onm").slug
    assert_equal [], reload.slugs
    assert_equal [], reload.links_listing
  end

  test "a linked registry's groups arrive too, their members remapped" do
    target = linked_file("onm", %w[central autonote], groups: { "brain" => %w[central autonote] })
    reg = registry
    reg.add(bundle("central"))
    reg.link("onm", target)

    fresh = reload
    assert_equal %w[onm-central autonote], fresh.expand("brain").map(&:slug)
  end

  test "groups_listing carries the linked groups too, tagged with the link they came from" do
    target = linked_file("onm", %w[central autonote], groups: { "brain" => %w[central autonote] })
    reg = registry
    reg.add(bundle("alpha"))
    reg.add(bundle("beta"))
    reg.set_group("backend", %w[alpha beta])
    reg.link("onm", target)

    rows = reload.groups_listing

    # One question, one answer: `group?` resolves a linked group, so the listing
    # that enumerates groups has to name it — a second method for the linked half
    # is how a caller comes to answer about a smaller set than it can resolve.
    assert_equal %w[backend onm brain], rows.map { |row| row[:slug] }
    assert_nil rows.first[:link], "a group this registry owns came through no link"
    assert_equal %w[onm onm], rows.drop(1).map { |row| row[:link] }
    assert_equal 2, rows.last[:resolved]
  end

  test "links_listing reports each link with its target and bundle count" do
    target = linked_file("onm", %w[central autonote])
    registry.link("onm", target)

    assert_equal [ { slug: "onm", registry: target, bundles: 2, missing: false, unreadable: false } ],
      reload.links_listing
  end

  private

  def registry
    OKF::Registry.load(home: @home)
  end
  alias reload registry

  # A registry file at @bundles/<name>-registry.json listing one bundle per slug,
  # with absolute paths — the shape a link points at. +groups+ and +links+ let a
  # test give the target its own curation, or its own link (which must not be
  # followed).
  def linked_file(name, slugs, groups: {}, links: {})
    dirs = slugs.map { |slug| bundle("#{name}/#{slug}") }
    linked_file_for(name, dirs, slugs: slugs, groups: groups, links: links)
  end

  def linked_file_for(name, dirs, slugs: nil, groups: {}, links: {})
    slugs ||= dirs.map { |dir| File.basename(dir) }
    path = File.join(@bundles, "#{name}-registry.json")
    File.write(path, JSON.pretty_generate(
      "bundles" => dirs.each_with_index.map do |dir, i|
        { "slug" => slugs[i], "path" => File.expand_path(dir), "title" => slugs[i] }
      end,
      "groups" => groups.map { |slug, members| { "slug" => slug, "members" => members } },
      "links" => links.map { |slug, target| { "slug" => slug, "registry" => target } }
    ))
    path
  end

  # A minimal on-disk bundle at @bundles/<name> with one concept, so Folder.load
  # succeeds. Returns its path.
  def bundle(name)
    dir = File.join(@bundles, name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "a.md"), "---\ntype: Note\ntitle: A\ndescription: d\n---\n\nhi\n")
    dir
  end
end
