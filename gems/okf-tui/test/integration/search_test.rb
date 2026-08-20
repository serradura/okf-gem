# frozen_string_literal: true

require "test_helper"

module Integration
  # The search view: what typing costs, when a search runs, and where the focus
  # is. Every one of these is invisible on a screenshot — a search per keystroke
  # renders identically to a search per submit.
  class SearchTest < OKF::TUI::TestCase
    WORD = "orphan"

    test "arriving at the search view does not grab the field" do
      with_registry("okf-docs", "unhealthy") do |home|
        app = app_for(home: home, keys: "3")

        refute app.editing_query?, "the field should not have focus on arrival"

        # A view that swallows every printable key the moment you reach it takes
        # the number keys away from navigation.
        app.handle("4")
        assert_equal :graph, app.view, "a digit typed into the field instead of switching views"
      end
    end

    test "typing runs no search and Enter runs exactly one" do
      with_registry("okf-docs", "unhealthy") do |home|
        app = app_for(home: home, keys: "3/")

        searches = 0
        app.workspace.define_singleton_method(:search) do |_query, mode: :fuzzy|
          searches += 1
          _ = mode
          []
        end

        # Painting happens after every keystroke, so ask for the hits each time —
        # that is exactly what the view does.
        WORD.each_char do |char|
          app.handle(char)
          app.search_hits
        end

        assert_equal 0, searches, "typing #{WORD.length} characters ran #{searches} searches"
        assert app.search_pending?, "the query should stay pending until Enter"

        app.handle("\r")
        app.search_hits
        assert_equal 1, searches, "Enter should run exactly one search"
        refute app.search_pending?, "nothing should be pending once searched"

        app.search_hits
        assert_equal 1, searches, "an unchanged query searched again"
      end
    end

    test "Esc releases the field without leaving the view" do
      with_registry("okf-docs", "unhealthy") do |home|
        app = app_for(home: home, keys: "3/#{WORD}<enter>")
        refute_empty app.search_hits, "the fixtures should produce hits to navigate"

        app.handle(OKF::TUI::App::ESCAPE)
        assert_equal :search, app.view, "Esc left the search view"
        refute app.editing_query?, "Esc should release the field"

        app.handle(OKF::TUI::App::ESCAPE)
        assert_equal :search, app.view, "a second Esc left the search view"

        before = app.cursor
        app.handle(OKF::TUI::App::DOWN)
        assert_equal before + 1, app.cursor, "the arrows do not reach the results after Esc"

        app.handle("/")
        assert app.editing_query?, "/ should return to the field"
      end
    end

    test "Esc drops an unsearched edit rather than running it" do
      with_registry("okf-docs", "unhealthy") do |home|
        app = app_for(home: home, keys: "3/#{WORD}<enter>")
        searched = app.searched.dup

        app.handle("x")
        assert app.search_pending?, "typing should leave the query pending"

        app.handle(OKF::TUI::App::ESCAPE)
        assert_equal searched, app.query, "Esc should revert the field to the searched query"
        refute app.search_pending?, "nothing should be pending after Esc"
      end
    end

    test "one index spans every bundle in scope" do
      with_registry("okf-docs", "unhealthy") do |home|
        app = app_for(home: home, keys: "3/#{WORD}<enter>")

        assert_equal 2, app.workspace.scope.length
        slugs = app.search_hits.map { |hit| hit[:slug] }.uniq
        refute_empty slugs, "a cross-bundle search should label its hits"
        assert slugs.all? { |slug| app.workspace.entry(slug) }, "every hit should name a bundle in scope"
      end
    end

    test "opening a hit switches to the bundle it lives in" do
      with_registry("okf-docs", "unhealthy") do |home|
        app = app_for(home: home, keys: "3/#{WORD}<enter>")
        hit = app.search_hits.first

        app.handle("\r")
        assert_equal :browse, app.view, "Enter on a hit should open browse"
        assert_equal hit[:slug], app.workspace.active_slug, "browse should be showing the hit's bundle"
        assert_equal hit[:id], app.selected_row[:id], "browse opened the wrong concept"
      end
    end

    test "a filter that matches nothing offers the wider search" do
      with_registry("okf-docs", "unhealthy") do |home|
        app = app_for(home: home, keys: "2/#{WORD}")

        assert app.filter_found_nothing?, "the filter should have found nothing to escalate from"
        refute_nil app.escalation_offer, "an empty filter should offer the wider search"

        app.handle("\r")
        assert_equal :search, app.view, "Enter should escalate to the search view"
        assert_equal WORD, app.searched, "the term should carry over"
        refute_empty app.search_hits, "the search should already have run"
        assert_equal app.workspace.entries.length, app.workspace.scope.length, "escalating should widen the scope"
        assert_empty app.filter, "the filter should be cleared behind it"
      end
    end

    test "a filter that matches does not offer to escalate" do
      with_registry("okf-docs") do |home|
        app = app_for(home: home, keys: "2/cli")

        refute app.filter_found_nothing?, "a filter with matches should not offer to escalate"
        app.handle("\r")
        assert_equal :browse, app.view, "Enter left browse despite the filter matching"
      end
    end

    # ── the held corpus ──────────────────────────────────────────────────────
    #
    # `fuzzy: true` requires a capability only the full-text engine declares, so
    # every search here routes to the index — and rebuilding that index per query
    # is what okf 1.11.0 added `prepare`/`with` to stop. These assert the
    # mechanism, because its absence is invisible: a rebuilt corpus returns the
    # same rows, just slowly.

    test "nothing is indexed until the first search" do
      with_registry("okf-docs", "unhealthy") do |home|
        # Arriving at the view and typing is not asking a question.
        app = app_for(home: home, keys: "3/#{WORD}")

        assert_nil corpus_of(app),
          "a session that has not searched should not have paid to index every bundle"
      end
    end

    test "the corpus is built once and held across queries" do
      with_registry("okf-docs", "unhealthy") do |home|
        app = app_for(home: home, keys: "3/#{WORD}<enter>")
        refute_empty app.search_hits, "the fixtures should produce hits"
        first = corpus_of(app)

        refute_nil first, "the first search should have prepared a corpus"

        app.handle(OKF::TUI::App::ESCAPE)
        app.handle("/")
        "index".each_char { |char| app.handle(char) }
        app.handle("\r")
        app.search_hits

        assert_same first, corpus_of(app),
          "a second query over the same scope should reuse the corpus, not rebuild it"
      end
    end

    test "a scope change rebuilds the corpus" do
      with_registry("okf-docs", "unhealthy") do |home|
        app = app_for(home: home, keys: "3/#{WORD}<enter>")
        app.search_hits
        first = corpus_of(app)
        refute_nil first

        # Narrow the scope to one bundle, then ask again.
        app.workspace.scope_only("okf-docs")
        app.workspace.search(WORD)

        refute_same first, corpus_of(app),
          "a corpus spanning two bundles cannot answer a one-bundle scope"
        assert_equal 1, app.workspace.scope.length
      end
    end

    test "a reload drops the corpus" do
      with_registry("okf-docs", "unhealthy") do |home|
        app = app_for(home: home, keys: "3/#{WORD}<enter>")
        app.search_hits
        refute_nil corpus_of(app)

        app.workspace.reload

        assert_nil corpus_of(app),
          "the entries were re-read, so a corpus built from the old ones is stale — " \
          "a held index outliving its set is a wrong answer, not a slow one"
      end
    end

    test "a held corpus ranks exactly as rebuilding would" do
      # The correctness half. Holding a corpus is only a performance change, so
      # the rows and their order must be identical to what .across returns — if
      # they ever differ, the optimisation changed the product.
      with_registry("okf-docs", "unhealthy") do |home|
        app = app_for(home: home, keys: "3")
        workspace = app.workspace
        pairs = workspace.entries.select(&:loaded?).map { |entry| [ entry.slug, entry.model.bundle ] }

        rebuilt = OKF::Bundle::Search.across(pairs, [ WORD ], fuzzy: true)
        held = workspace.search(WORD)

        refute_empty held, "the fixtures should produce hits for #{WORD}"
        assert_equal rebuilt.map { |row| [ row[:slug], row[:id], row[:score] ] },
          held.map { |row| [ row[:slug], row[:id], row[:score] ] },
          "the held corpus returned a different ranking than a rebuild"
      end
    end

    # ── the engine behind the query ──────────────────────────────────────────
    #
    # okf's index and scan disagree *by design*, and each is wrong for what the
    # other is right for. The view offered only the index, which left every term
    # glued to a symbol — a constant, an env var, a version — unfindable, with
    # nothing on screen saying so.

    test "the three modes cycle, and say what they are for" do
      with_registry("okf-docs") do |home|
        app = app_for(home: home, keys: "3")
        assert_equal :fuzzy, app.search_mode, "the ranked index is still the default"
        refute app.editing_query?, "arriving at the view does not grab the field"

        app.handle("e")
        assert_equal :text, app.search_mode
        app.handle("e")
        assert_equal :regexp, app.search_mode
        app.handle("e")
        assert_equal :fuzzy, app.search_mode, "and round again"
      end
    end

    test "e is a letter while the field has focus" do
      with_registry("okf-docs") do |home|
        app = app_for(home: home, keys: "3/")
        assert app.editing_query?

        app.handle("e")

        assert_equal "e", app.query, "it has to type, or no query could contain the letter"
        assert_equal :fuzzy, app.search_mode
        assert_match(/then e changes the mode/, app.status_hints.flatten.join(" "),
          "and the hint has to say where the key went")
      end
    end

    test "the mode is on screen, not just in a keystroke" do
      with_registry("okf-docs") do |home|
        frame = plain(render(home: home, keys: "3"))

        assert_match(/mode\s+fuzzy/, frame)
        assert_match(/\(e\)/, frame, "and how to change it")
      end
    end

    test "text mode finds what the index tokenizer cannot" do
      # okf documents this: a backtick is not punctuation, so a word inside a code
      # span indexes as `` `minifts` `` and the query does not match it. The fixture
      # carries the same shape — a term that appears only inside backticks.
      with_registry("okf-docs") do |home|
        app = app_for(home: home, keys: "3")
        indexed = app.workspace.search("MiniSearch", mode: :fuzzy).map { |hit| hit[:id] }
        raw = app.workspace.search("MiniSearch", mode: :text).map { |hit| hit[:id] }

        refute_empty raw, "the scan reads the text as written"
        assert_operator raw.length, :>=, indexed.length,
          "the raw scan should reach at least what the tokenizer does"
      end
    end

    test "a regexp is a pattern, and only one engine can answer it" do
      with_registry("okf-docs") do |home|
        app = app_for(home: home, keys: "3")

        hits = app.workspace.search("okf_(version|format)", mode: :regexp)

        refute_empty hits, "the scan answers a pattern the index has no capability for"
        assert_nil app.workspace.search_error
      end
    end

    test "a bad pattern says so rather than reading as no matches" do
      # The failure shape this whole view keeps having to avoid: an unparseable
      # regexp rescued into an empty result is indistinguishable from a term that is
      # genuinely absent.
      with_registry("okf-docs") do |home|
        app = app_for(home: home, keys: "3")

        hits = app.workspace.search("kernel(", mode: :regexp)

        assert_empty hits
        refute_nil app.workspace.search_error, "the reason has to survive to the screen"
        assert_match(/bad pattern/, app.workspace.search_error)
      end
    end

    test "the error clears once a query runs" do
      with_registry("okf-docs") do |home|
        app = app_for(home: home, keys: "3")
        app.workspace.search("kernel(", mode: :regexp)
        refute_nil app.workspace.search_error

        app.workspace.search("okf", mode: :text)

        assert_nil app.workspace.search_error, "an error must not outlive the query it described"
      end
    end

    test "changing the mode re-asks rather than relabelling the old answer" do
      with_registry("okf-docs", "unhealthy") do |home|
        # Esc first: the field keeps focus after Enter so the query can be refined,
        # and while it has focus every letter belongs to the query.
        app = app_for(home: home, keys: "3/#{WORD}<enter><esc>")
        app.search_hits
        asked = []
        app.workspace.define_singleton_method(:search) do |_query, mode: :fuzzy|
          asked << mode
          []
        end

        app.handle("e")
        app.search_hits

        assert_equal [ :text ], asked, "the hits are keyed on the mode, so they rerun"
      end
    end

    test "the held corpus serves every mode" do
      # The scan declares no `prepare`, so it holds documents rather than an index —
      # which is still the expensive half to rebuild.
      with_registry("okf-docs", "unhealthy") do |home|
        app = app_for(home: home, keys: "3")
        app.workspace.search(WORD, mode: :fuzzy)
        corpus = corpus_of(app)
        refute_nil corpus

        app.workspace.search(WORD, mode: :text)

        assert_same corpus, corpus_of(app), "one corpus, whichever engine reads it"
      end
    end

    private

    # The corpus is a cache, so asserting on it means reading it. Named here so
    # the reach into Workspace happens in one place rather than five.
    def corpus_of(app)
      app.workspace.instance_variable_get(:@corpus)
    end
  end
end
