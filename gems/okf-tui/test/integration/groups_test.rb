# frozen_string_literal: true

require "test_helper"
require "json"

module Integration
  # Registry groups (okf 1.12) in the bundles view.
  #
  # A group is a named, recursive set of bundles — which is to say a named search
  # scope, and the scope is what this view already manages with space / A / N. So
  # the group belongs here, and `Enter` on one means "make a search cover exactly
  # these", the same set `okf search @group` merges into one ranking.
  class GroupsTest < OKF::TUI::TestCase
    # ── the three panes ──────────────────────────────────────────────────────
    #
    # The groups have a pane of their own rather than a heading inside the bundle
    # list. A heading scrolls away: thirteen registered bundles put the groups below
    # the fold on a short terminal, which is no way to show a thing you are meant to
    # select. Two panes also give two selections at once, which is what lets `+` name
    # a bundle *and* a group without reaching for the search scope.

    test "the groups get a pane of their own" do
      with_groups do |home|
        frame = plain(render(home: home, keys: "1"))

        assert_match(/┌ groups ─|╔ groups ═/, frame, "a box, not a heading in the bundle list")
        assert_match(/@docs\s+2 bundles/, frame)
        assert_match(/@everything\s+3 bundles/, frame)
      end
    end

    test "the groups pane stays on screen however long the registry is" do
      # The reason it is a pane. Every fixture registered, on a short terminal.
      with_registry(:conformant, :minimal, :nested, :unhealthy, :malformed, :wide) do |home, registry|
        registry.set_group("docs", %w[@minimal @nested])

        frame = plain(render(home: home, keys: "1", size: [ 100, 18 ]))

        assert_match(/@docs/, frame, "the groups must not be pushed off the bottom")
      end
    end

    test "an ad-hoc workspace has no groups, because it has no registry" do
      app = app_for(dirs: %w[conformant minimal])

      assert_empty app.workspace.groups
      refute_match(/@docs/, plain(frame_for(app)))
    end

    test "a registry with no groups says how to make one" do
      with_registry(:conformant) do |home|
        frame = plain(render(home: home, keys: "1"))

        assert_match(/c names the scoped bundles as one/, frame,
          "an empty pane should say what fills it")
      end
    end

    # ── Tab and Esc ──────────────────────────────────────────────────────────

    test "Tab cycles bundles, groups, members, and round again" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")

        assert app.bundles_pane?, "it opens on the bundles"
        app.handle(OKF::TUI::App::TAB)
        assert app.groups_pane?
        app.handle(OKF::TUI::App::TAB)
        assert app.member_pane?
        app.handle(OKF::TUI::App::TAB)
        assert app.bundles_pane?, "and back round"
      end
    end

    test "Tab skips the members when there is no group to have any" do
      with_registry(:conformant) do |home|
        app = app_for(home: home, keys: "1")

        app.handle(OKF::TUI::App::TAB)

        assert app.bundles_pane?, "nowhere else to go"
        assert_match(/no groups here yet/, plain(frame_for(app)))
      end
    end

    test "Esc steps back out one pane at a time, before the filter" do
      with_groups do |home|
        # <enter> accepts the filter — without it the next keystroke types into it.
        app = app_for(home: home, keys: "1/doc<enter>")
        assert_equal "doc", app.filter
        app.handle(OKF::TUI::App::TAB)
        app.handle(OKF::TUI::App::TAB)
        assert app.member_pane?

        app.handle(OKF::TUI::App::ESCAPE)
        assert app.groups_pane?, "members → groups"
        app.handle(OKF::TUI::App::ESCAPE)
        assert app.bundles_pane?, "groups → bundles"
        assert_equal "doc", app.filter, "and the filter is the outermost layer, still in force"

        app.handle(OKF::TUI::App::ESCAPE)
        assert_empty app.filter, "only now"
      end
    end

    test "each pane keeps its own cursor" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        app.handle(OKF::TUI::App::DOWN) # second bundle
        bundle = app.selected_entry.slug

        app.handle(OKF::TUI::App::TAB)
        app.handle(OKF::TUI::App::DOWN) # second group

        assert_equal "everything", app.selected_group.slug
        assert_equal bundle, app.selected_entry.slug,
          "moving in the groups pane must not drag the bundles cursor"
      end
    end

    test "the detail pane describes whichever pane has focus" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        assert_match(/conformance/, plain(frame_for(app)), "a bundle's standing")

        app.handle(OKF::TUI::App::TAB)
        frame = plain(frame_for(app))

        assert_match(/@docs\s+group/, frame)
        refute_match(/conformance/, frame, "a group has no conformance of its own")
      end
    end

    # ── reading a group ──────────────────────────────────────────────────────

    test "a nested group resolves recursively to its bundle leaves" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        group = focus_group(app, "everything")

        refute_nil group
        assert_equal 2, group.members.length, "two members as written"
        assert_equal %w[conformant minimal nested], group.bundles.sort,
          "three bundles once resolved — the recursion is okf's, and it has to be used"
      end
    end

    test "the detail pane names the members and what they resolve to" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "everything")
        frame = plain(frame_for(app))

        assert_match(/members\s+2/, frame, "what the registry file records")
        assert_match(/bundles\s+3/, frame, "and what it resolves to — for a nested group these differ")
        assert_match(/@docs\s+group of 2/, frame, "a nested member should read as a group")
      end
    end

    test "a member naming nothing registered is called out, not dropped" do
      with_groups do |home, registry|
        # Reach past okf to plant it: `registry group` validates its members, so this
        # state only arises from a hand-edited file — and a silently shorter member
        # list is how it would stay unnoticed.
        hand_edit(registry) do |data|
          data["groups"].each { |g| g["members"] << "ghost" if g["slug"] == "docs" }
        end

        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")

        assert_match(/@ghost\s+not registered/, plain(frame_for(app)))
      end
    end

    test "a cyclic group says so and refuses to be scoped" do
      # okf refuses to *create* a cycle ("group cycle: @g would contain itself"), so
      # this state only exists in a hand-edited file — which is why okf reports it as
      # unresolvable rather than looping. Nothing here can repair it; the honest
      # answer is to say so and decline.
      with_groups do |home, registry|
        hand_edit(registry) do |data|
          data["groups"] = [
            { "slug" => "loop-a", "members" => %w[loop-b] },
            { "slug" => "loop-b", "members" => %w[loop-a] }
          ]
        end

        app = app_for(home: home, keys: "1")
        group = focus_group(app, "loop-a")

        refute_nil group, "the cyclic group should still be listed"
        assert group.cyclic?, "okf could not resolve it, and the row has to carry that"
        assert_empty group.bundles

        frame = plain(frame_for(app))
        assert_match(/unresolvable/, frame)
        assert_match(/cycle/, frame)

        app.handle("\r")
        assert_match(/cycle/, plain(frame_for(app)), "Enter should explain, not silently do nothing")
        refute_empty app.workspace.scope, "and it must not leave the scope empty"
      end
    end

    # ── scoping ──────────────────────────────────────────────────────────────

    test "Enter on a group scopes the search to its bundles" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")

        app.handle("\r")

        assert_equal %w[minimal nested], app.workspace.scope
        assert_match(/search scope: @docs — 2 bundles/, plain(frame_for(app)))
      end
    end

    test "scoping a group narrows what a search actually covers" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        app.handle("\r")

        # "data" hits @nested *and* @conformant, so an unscoped search returns both —
        # which is what makes the exclusion below mean something.
        hits = app.workspace.search("data")
        refute_empty hits, "the scoped bundles should still produce hits"
        refute_includes hits.map { |hit| hit[:slug] }.uniq, "conformant",
          "a search covered a bundle the group does not name"
      end
    end

    test "the in-scope mark is set equality, not overlap" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        app.handle("\r") # scope is exactly @docs

        assert app.group_in_scope?(app.workspace.group("docs"))
        refute app.group_in_scope?(app.workspace.group("everything")),
          "a group whose set is a superset of the scope is not in force"

        app.workspace.toggle_scope("nested")
        refute app.group_in_scope?(app.workspace.group("docs")),
          "the scope is no longer the group, and the row must not claim it is"
      end
    end

    # ── + : two visible rows, no scope ───────────────────────────────────────
    #
    # This key was wrong twice. It removed against `scope ∩ members`, then added
    # from the scope; both made the effect a set with no row on screen. With a pane
    # each, it is the bundle under one cursor joining the group selected in the other.

    test "+ adds the bundle under the cursor to the selected group" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        app.handle(OKF::TUI::App::TAB) # into the members
        app.handle(OKF::TUI::App::TAB) # round to the bundles
        assert app.bundles_pane?
        assert_equal "conformant", app.selected_entry.slug

        app.handle("+")

        assert_equal %w[minimal nested conformant], app.workspace.group("docs").members
      end
    end

    test "+ does not consult the search scope at all" do
      # The whole point of the redesign. Scope something *other* than the bundle
      # under the cursor and the scope must have no bearing on what is added.
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        app.handle(OKF::TUI::App::TAB)
        app.handle(OKF::TUI::App::TAB)
        app.workspace.scope_only("unhealthy")
        assert_equal "conformant", app.selected_entry.slug

        app.handle("+")

        members = app.workspace.group("docs").members
        assert_includes members, "conformant", "the row under the cursor"
        refute_includes members, "unhealthy", "not whatever happened to be in scope"
      end
    end

    test "+ says so when the bundle is already a member" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        app.handle(OKF::TUI::App::TAB)
        app.handle(OKF::TUI::App::TAB)
        app.handle(OKF::TUI::App::DOWN) # @minimal, already in @docs
        before = app.workspace.group("docs").members.dup

        app.handle("+")

        assert_equal before, app.workspace.group("docs").members
        assert_match(/already names @minimal/, plain(frame_for(app)))
      end
    end

    test "+ from the groups pane points back at the bundles" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")

        app.handle("+")

        assert_match(/Tab back, point at one/, plain(frame_for(app)),
          "a key that does nothing should say where it works")
      end
    end

    test "+ with no group registered says what to do instead" do
      with_registry(:conformant, :minimal) do |home|
        app = app_for(home: home, keys: "1")

        app.handle("+")

        assert_match(/no group to add it to/, plain(frame_for(app)))
        assert_match(/c names/, plain(frame_for(app)))
      end
    end

    # ── c : the one gesture the scope is right for ───────────────────────────

    test "c names the bundles in scope as a new group" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        app.workspace.scope_only("conformant")
        app.workspace.toggle_scope("minimal")

        app.handle("c")
        refute_nil app.prompt, "c should ask for a name"
        assert_match(/2 scoped bundles/, app.prompt.label)
        "pair".each_char { |char| app.handle(char) }
        app.handle("\r")

        group = app.workspace.group("pair")
        refute_nil group
        assert_equal %w[conformant minimal], group.bundles.sort
      end
    end

    test "c with nothing in scope explains instead of making an empty group" do
      with_groups do |home|
        app = app_for(home: home, keys: "1N") # N clears the scope

        app.handle("c")

        assert_nil app.prompt, "there is nothing to name"
        assert_match(/nothing in scope/, plain(frame_for(app)))
      end
    end

    test "the write lands in the registry file, not just in memory" do
      with_groups do |home, registry|
        app = app_for(home: home, keys: "1")
        app.workspace.scope_only("conformant")
        app.handle("c")
        "solo".each_char { |char| app.handle(char) }
        app.handle("\r")

        # A separate reader over the same file: the point of the reload contract is
        # that the screen shows what the file says.
        assert_includes OKF::Registry.load(home: home).groups_listing.map { |row| row[:slug] }, "solo"
        refute_nil registry.reopen.group?("solo")
      end
    end

    # ── - : the member under the cursor ──────────────────────────────────────

    test "- removes the member under the cursor, once confirmed" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        app.handle(OKF::TUI::App::TAB)
        app.handle(OKF::TUI::App::DOWN) # @nested

        app.handle("-")
        refute_nil app.prompt, "it writes to the registry, so it has to ask"
        assert_match(/remove @nested from @docs/, app.prompt.label,
          "and name the member being pointed at, not a set")
        app.handle("y")

        assert_equal %w[minimal], app.workspace.group("docs").members
      end
    end

    test "- leaves the group alone when declined" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        app.handle(OKF::TUI::App::TAB)
        before = app.workspace.group("docs").members.dup

        app.handle("-")
        app.handle("n")

        assert_equal before, app.workspace.group("docs").members
        assert_match(/cancelled/, plain(frame_for(app)))
      end
    end

    test "- says so when the member is the last one and the group goes with it" do
      with_registry(:conformant, :minimal) do |home, registry|
        registry.set_group("solo", %w[@minimal])
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "solo")
        app.handle(OKF::TUI::App::TAB)

        app.handle("-")

        assert_match(/@solo goes too/, app.prompt.label,
          "trimming a member and deleting the group are the same keystroke here")
      end
    end

    test "removing the last member steps focus back to the groups" do
      with_registry(:conformant, :minimal) do |home, registry|
        registry.set_group("solo", %w[@minimal])
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "solo")
        app.handle(OKF::TUI::App::TAB)

        app.handle("-")
        app.handle("y")

        assert_empty app.workspace.groups
        refute app.member_pane?, "the pane described a group that no longer exists"
      end
    end

    test "- from the bundles pane says where the key lives" do
      # It acted here for one round, as the inverse of `+`. It went back: the members
      # pane already gives every member a row of its own, and one editing gesture
      # with two homes is a wider surface than the flow needs. It must not go silent
      # either — a key that quietly stopped working reads as a broken one.
      with_groups do |home, registry|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        refute_nil focus_bundle(app, "minimal") # a member of @docs, so the row is live
        before = File.read(registry.path)

        app.handle("-")

        assert_nil app.prompt
        assert_equal before, File.read(registry.path)
        assert_match(/Tab to the groups/, plain(frame_for(app)))
      end
    end

    # ── the row says what it is in ───────────────────────────────────────────

    test "a bundle row says nothing about the group selected below" do
      # It carried the slug for a round. The column was relative to a cursor in
      # another pane, so it changed as that cursor moved and read as noise while
      # working in this one. The membership lives in the detail pane instead, which
      # names every group rather than whichever happens to be selected.
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        refute_nil focus_bundle(app, "minimal") # a member of @docs

        rows = plain(frame_for(app)).lines.map { |line| line.split("│").first.to_s }
        row = rows.find { |line| line.include?("@minimal") }

        refute_nil row
        refute_includes row, "@docs", "the row is about the bundle, not about a cursor elsewhere"
        assert_includes row, "concept", "and still says what it is"
      end
    end

    test "the detail pane names every group that names the bundle" do
      # The row can only carry the selected group; a bundle can be in several, and
      # after a + the one just edited may be scrolled out of the groups pane.
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_bundle(app, "conformant")

        assert_match(/in @everything/, plain(frame_for(app)))
      end
    end

    # ── the scope follows the group it is ────────────────────────────────────

    test "a group that is the scope in force stays in force when + grows it" do
      # The reported symptom: "after adding a bundle it does not select the bundle".
      # The group had grown and the scope had not, so the ◉ on the row the key acted
      # on stayed hollow and the group's own ◉ emptied at the same time.
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        app.handle("\r") # scope is exactly @docs
        assert app.group_in_scope?(app.workspace.group("docs"))
        refute_nil focus_bundle(app, "conformant")

        app.handle("+")

        assert app.scoped?("conformant"), "the bundle just added to the scope in force is in it"
        assert app.group_in_scope?(app.workspace.group("docs")),
          "and the group is still the thing the scope is"
      end
    end

    test "a group that is the scope in force stays in force when - shrinks it" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        app.handle("\r")
        app.handle(OKF::TUI::App::TAB) # into the members, where - lives

        app.handle("-")
        app.handle("y")

        refute app.scoped?("minimal"), "it left the group, so it leaves the scope the group is"
        assert app.group_in_scope?(app.workspace.group("docs"))
      end
    end

    test "editing a group nobody scoped leaves the scope alone" do
      # The other half of the rule. Re-scoping on every group edit would replace a
      # selection the reader made by hand, which is a worse surprise than the one
      # this fixed.
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        app.workspace.scope_only("unhealthy")
        refute_nil focus_bundle(app, "conformant")

        app.handle("+")

        assert_equal %w[unhealthy], app.workspace.scope
        assert_includes app.workspace.group("docs").members, "conformant", "the write still happened"
      end
    end

    # ── rename and delete, on the pane that has focus ────────────────────────

    test "renaming a group cascades through the member lists that name it" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")

        app.handle("n")
        refute_nil app.prompt, "n should ask for the new name"
        assert_match(/rename @docs/, app.prompt.label)
        "papers".each_char { |char| app.handle(char) }
        app.handle("\r")

        assert_nil app.workspace.group("docs")
        refute_nil app.workspace.group("papers")
        assert_includes app.workspace.group("everything").members, "papers",
          "the member list that named @docs should now name @papers"
      end
    end

    test "deleting a group asks first, and drops it from every member list" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")

        app.handle("x")
        refute_nil app.prompt, "x should confirm"
        assert_match(/group @docs/, app.prompt.label, "and say it is a group, not a bundle")
        app.handle("y")

        assert_nil app.workspace.group("docs")
        refute_includes app.workspace.group("everything").members, "docs",
          "okf cascade-drops the slug from every member list"
        assert_equal 4, app.workspace.entries.length, "and touches no bundle"
      end
    end

    test "deleting a group can be declined" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        app.handle("x")

        app.handle("n")

        refute_nil app.workspace.group("docs"), "n should cancel"
      end
    end

    test "n and x from the bundles pane act on the bundle, not the group" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        assert app.bundles_pane?

        app.handle("x")

        refute_nil app.prompt
        assert_match(/@conformant/, app.prompt.label, "the row this pane has selected")
        refute_match(/group/, app.prompt.label)
      end
    end

    # ── the guards ───────────────────────────────────────────────────────────

    test "the bundle-only keys do not act from the groups pane" do
      with_groups do |home, registry|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        before_default = app.workspace.entries.find(&:default?).slug
        before_scope = app.workspace.scope.dup
        before_file = File.read(registry.path)

        app.handle("d") # make default
        app.handle(" ") # toggle scope
        app.handle("a") # register a directory

        assert_equal before_default, app.workspace.entries.find(&:default?).slug,
          "a group cannot be the default bundle"
        assert_equal before_scope, app.workspace.scope, "space is a per-bundle toggle"
        assert_nil app.prompt, "and `a` belongs to the bundles pane"
        assert_equal before_file, File.read(registry.path)
      end
    end

    test "the registry keys do not act while the members have focus" do
      with_groups do |home, registry|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        app.handle(OKF::TUI::App::TAB)
        before = File.read(registry.path)

        %w[d x n c a +].each { |key| app.handle(key) }

        assert_nil app.prompt, "no prompt should open for a pane that owns none of these"
        assert_equal before, File.read(registry.path)
      end
    end

    test "a group write is refused on an ad-hoc workspace" do
      app = app_for(dirs: %w[conformant minimal], keys: "1")

      message = app.workspace.create_group("pair", %w[conformant])

      assert_match(/no registry to change/, message)
    end

    test "okf's own refusals reach the status line" do
      # A group cannot contain itself, and okf is what knows that.
      with_groups do |home|
        app = app_for(home: home, keys: "1")

        message = app.workspace.add_to_group("docs", %w[docs])

        assert_match(/could not add to @docs/, message)
        assert_match(/cycle/, message, "okf's own words, not a paraphrase")
      end
    end

    # ── the filter ───────────────────────────────────────────────────────────

    test "the filter finds a group by its members" do
      with_groups do |home|
        # @nested is a member of @docs and a resolved leaf of @everything.
        app = app_for(home: home, keys: "1/nested")

        assert_equal %w[docs everything], app.visible_groups.map(&:slug)
      end
    end

    test "a filter matching no group empties that pane only" do
      with_groups do |home|
        # @unhealthy is in no group, so nothing in the group pane matches it.
        app = app_for(home: home, keys: "1/unhealthy")

        assert_equal %w[unhealthy], app.visible_entries.map(&:slug)
        assert_empty app.visible_groups
        assert_match(/unhealthy/, plain(frame_for(app)))
      end
    end

    test "a filter that empties the groups pane cannot leave focus in it" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        assert app.groups_pane?

        # Typing a filter from the groups pane: `/` then a term that matches no group.
        app.handle("/")
        "unhealthy".each_char { |char| app.handle(char) }

        assert_empty app.visible_groups
        refute app.groups_pane?, "focus cannot stay in a pane with nothing in it"
      end
    end

    # ── the scope keys, where they are needed ────────────────────────────────

    # "It is not clear how to control the scope" — and it was not: neither `A` nor
    # `N` appeared on a bundle row at all, and the footer truncates, so at 80 columns
    # everything from `d` rightward is already off screen. What the visible prefix
    # names is the whole of what a narrow terminal teaches.
    test "the bundles pane names the scope keys, ahead of the config keys" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        assert app.bundles_pane?

        hints = app.status_hints
        assert_match(%r{A/N}, hints.flatten.join(" "),
          "how to reset the scope has to be reachable from here")

        scope_at = hints.index { |key, _| key == "A/N" }
        config_at = hints.index { |key, _| key == "d" }
        refute_nil scope_at
        refute_nil config_at
        assert_operator scope_at, :<, config_at,
          "the scope is one of the two axes this view is about; it comes before the config keys"
      end
    end

    test "the footer offers + join group, where a add used to be" do
      # `a add` gave up the slot: of the two keys a reader would have called "add",
      # only `+` adds to a group, and `a` is still taught by view 6 and by the empty
      # registry. It does not spell the slug out — the groups pane below carries a
      # cursor on the row, which is a thing the reader can point at.
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        refute_nil focus_bundle(app, "minimal")

        hints = app.status_hints
        join = hints.find { |key, _| key == "+" }
        refute_nil join, "the key that adds to the group below belongs in the bundles footer"
        assert_equal "join group", join.last
        assert_nil hints.find { |key, _| key == "a" },
          "the word add beside + named the wrong one of the two"
        assert_nil hints.find { |key, _| key == "-" },
          "removal lives in the members pane, where every member has a row"
      end
    end

    test "the footer offers no + when there is no group to join" do
      with_registry(:conformant, :minimal) do |home|
        app = app_for(home: home, keys: "1")

        assert_nil app.status_hints.find { |key, _| key == "+" }
        assert_match(/c/, app.status_hints.flatten.join(" "), "c is how the first group gets made")
      end
    end

    test "the groups pane keeps a visible cursor while the bundles have focus" do
      # What makes "+ join group" answerable. The footer used to name the slug
      # instead, which claimed a selection nothing on the screen agreed with.
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "everything")
        refute_nil focus_bundle(app, "minimal")
        assert app.bundles_pane?

        # No column trimming: an unfocused box is drawn with the same │ the right
        # pane's border uses, so splitting on it would empty the row. The count
        # picks the group row out of the detail pane's mention of the same slug.
        marked = plain(frame_for(app)).lines.find do |line|
          line.include?("@everything") && line.include?("bundles")
        end
        refute_nil marked
        assert_includes marked, "▸", "the row + would act on has to be pointed at"
      end
    end

    # ── a registry filter that finds nothing ─────────────────────────────────

    test "Enter escalates a registry filter that matched no bundle" do
      # A filter here looks through a dozen slugs. A term matching none of them is
      # usually a question about what the bundles say, and browse answers that
      # with the same key.
      with_groups do |home|
        app = app_for(home: home, keys: "1/zzz<enter>")

        assert_equal :search, app.view, "Enter on a dead end should widen, not sit there"
        assert_equal "zzz", app.query
        assert_equal app.workspace.entries.length, app.workspace.scope.length,
          "escalating searches every bundle, not whatever was scoped"
      end
    end

    test "the dead end says the key that leads out of it" do
      with_groups do |home|
        app = app_for(home: home, keys: "1/zzz")
        frame = plain(frame_for(app))

        assert_match(/no bundle matches/, frame)
        assert_match(/searches every bundle/, frame, "a dead end has to name the way out")
        assert_match(/search all bundles/, app.status_hints.flatten.join(" "))
      end
    end

    test "a filter that still matches a bundle opens it, and does not escalate" do
      with_groups do |home|
        app = app_for(home: home, keys: "1/minimal<enter>")

        refute app.filter_found_nothing?, "there is a row here to act on"
        assert_equal :bundles, app.view
      end
    end

    test "a filter matching a group but no bundle has found something" do
      # It is both panes or neither. Reading only the bundles pane made a filter that
      # named a group escalate on the Enter that was accepting it — the filter went,
      # the view went, and the group the user was pointing at went with them.
      with_groups do |home|
        app = app_for(home: home, keys: "1/doc")
        assert_empty app.visible_entries, "no bundle is called doc"
        refute_empty app.visible_groups, "but @docs is"

        refute app.filter_found_nothing?
        app.handle("\r")
        assert_equal :bundles, app.view, "Enter accepted the filter; it did not widen"
        assert_equal "doc", app.filter
      end
    end

    test "the footer follows the focused pane" do
      with_groups do |home|
        app = app_for(home: home, keys: "1")
        refute_nil focus_group(app, "docs")
        assert_match(/its members/, app.status_hints.flatten.join(" "), "the groups pane")

        app.handle(OKF::TUI::App::TAB)
        assert_match(/pick a member/, app.status_hints.flatten.join(" "), "the members pane")
      end
    end

    private

    # Two groups, one nesting the other, because a flat group cannot show the
    # difference between "members" and "the bundles it resolves to" — the whole
    # reason okf made groups recursive.
    #
    # @unhealthy is deliberately in no group: without a bundle outside every group
    # there is no needle that can filter the groups away, and "@everything covers
    # everything" would make the filter look broken when it is working.
    def with_groups
      with_registry(:conformant, :minimal, :nested, :unhealthy) do |home, registry|
        registry.set_group("docs", %w[@minimal @nested])
        registry.set_group("everything", %w[@conformant @docs])
        yield home, registry
      end
    end

    # Focus the groups pane with `slug` selected, the way a user does: Tab until the
    # groups have focus, then step down to it. Bounded at both stages on purpose — a
    # `while` waiting on a condition the code under test controls turns a regression
    # into a hung suite rather than a failure, which this suite has already learned
    # the hard way.
    def focus_group(app, slug)
      OKF::TUI::App::PANES.length.times do
        break if app.groups_pane?

        app.handle(OKF::TUI::App::TAB)
      end
      return nil unless app.groups_pane?

      (app.visible_groups.length + 1).times do
        return app.selected_group if app.selected_group&.slug == slug

        app.handle(OKF::TUI::App::DOWN)
      end
      nil
    end

    # The bundles pane, with `slug` under its cursor — the row `+` and `-` act on.
    # Bounded like #focus_group, and for the same reason.
    def focus_bundle(app, slug)
      OKF::TUI::App::PANES.length.times do
        break if app.bundles_pane?

        app.handle(OKF::TUI::App::TAB)
      end
      return nil unless app.bundles_pane?

      (app.visible_entries.length + 1).times do
        return app.selected_entry if app.selected_entry&.slug == slug

        app.handle(OKF::TUI::App::DOWN)
      end
      nil
    end

    # Write the registry JSON directly, for the states okf's own API refuses to
    # produce. Only two tests use it, and both are about a file someone edited by
    # hand — which is a real thing to survive, since the registry is a plain file
    # okf invites you to commit.
    def hand_edit(registry)
      data = JSON.parse(File.read(registry.path))
      yield data
      File.write(registry.path, JSON.pretty_generate(data))
    end
  end
end
