# frozen_string_literal: true

require "test_helper"

# Where the bundle is, given where the agent is.
#
# The hook event carries a working directory, which is the repository root.
# The bundle is `.okf/` under it. Every check that reads the corpus makes that
# hop, and it makes it here — six copies of the rule would be six chances for
# one of them to drift and start silently checking nothing.
class BundleRootTest < OKF::Pro::TestCase
  def test_finds_a_nested_bundle_from_the_repository_root
    with_bundle(nested: true) do |b|
      b.concept("glossary/term.md", type: "Term")

      assert_equal b.bundle_path, OKF::Pro::BundleRoot.resolve(b.path)
      refute_equal b.path, b.bundle_path
    end
  end

  # The shape this template shipped with. An adopter who prefers the
  # repository root to *be* the bundle is not broken by the move.
  def test_falls_back_to_the_root_when_there_is_no_nest
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")

      assert_equal b.path, OKF::Pro::BundleRoot.resolve(b.path)
    end
  end

  def test_the_nest_wins_when_both_exist
    with_bundle(nested: true) do |b|
      b.concept("glossary/term.md", type: "Term")
      dir = b.path
      File.write(File.join(dir, "index.md"), "---\nokf_version: \"0.1\"\n---\n\n# Decoy\n")

      assert_equal b.bundle_path, OKF::Pro::BundleRoot.resolve(dir)
    end
  end

  def test_a_directory_with_no_bundle_resolves_to_nothing
    Dir.mktmpdir { |dir| assert_nil OKF::Pro::BundleRoot.resolve(dir) }
  end

  def test_an_okf_directory_without_an_index_is_not_a_bundle
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".okf"))
      File.write(File.join(dir, ".okf", "notes.md"), "# Notes\n")

      assert_nil OKF::Pro::BundleRoot.resolve(dir)
    end
  end

  # ── the checks that had to learn the hop ──────────────────────────────────

  # `.okf` is a dot-path, and Target rejects dot segments. It has to, or every
  # scratch file under `.tmp/` would be validated. The rejection is computed
  # from the path *relative to the bundle root*, so the bundle's own dotted
  # name is not one of the segments being judged.
  def test_a_concept_inside_the_nest_is_a_target
    with_bundle(nested: true) do |b|
      b.concept("glossary/term.md", type: "Term")
      target = OKF::Pro::Target.for(edit_event(b.path, ".okf/glossary/term.md"))

      refute_nil target
      assert_equal "glossary/term.md", target.rel
      assert_equal b.bundle_path, target.root
    end
  end

  # README.md and CLAUDE.md live here. They are documentation and
  # instructions, not concepts, and no conformance rule reaches them.
  def test_a_file_at_the_repository_root_is_outside_the_bundle
    with_bundle(nested: true) do |b|
      b.concept("glossary/term.md", type: "Term")
      dir = b.path
      File.write(File.join(dir, "README.md"), "# Readme\n\nNo frontmatter, and none needed.\n")

      assert_nil OKF::Pro::Target.for(edit_event(dir, "README.md"))
    end
  end

  def test_scratch_under_the_nest_is_still_skipped
    with_bundle(nested: true) do |b|
      b.concept("glossary/term.md", type: "Term")

      assert_nil OKF::Pro::Target.for(edit_event(b.path, ".okf/.tmp/scratch.md"))
    end
  end

  def test_audit_finds_the_nested_bundle_from_the_repository_root
    with_bundle(nested: true) do |b|
      b.concept("glossary/term.md", type: "Term")
      b.snapshot_on("2026-08-12")

      assert_empty OKF::Pro::Audit.call(b.path)
    end
  end

  def test_audit_reports_findings_through_the_nest
    with_bundle(nested: true) do |b|
      b.raw("glossary/broken.md", "# Broken\n\nNo frontmatter.\n")
      b.snapshot_on("2026-08-12")

      assert_match(/validate/, OKF::Pro::Audit.call(b.path).first)
    end
  end

  def test_session_context_reads_the_nested_board
    with_bundle(nested: true) do |b|
      b.in_flight("one", "two").snapshot_on("2026-08-12")

      assert_match(%r{in flight 2/5}, OKF::Pro::Closing.session_context(event(cwd: b.path))[0])
    end
  end

  def test_stop_gate_pairs_against_the_nested_board
    with_bundle(nested: true, git: true) do |b|
      b.concept("glossary/term.md", type: "Term")
      b.write("projects/orphan/index.md", "# Orphan\n\nOngoing.\n")
      b.log_day("2026-08-12", "* **Creation**: something.")

      refusal = OKF::Pro::Closing.stop_gate(event(cwd: b.path), today: Date.new(2026, 8, 12)).first

      assert_match(%r{projects/orphan has no board line}, refusal)
    end
  end
  # ── containing: the bundle a file belongs to, by its own ancestry ─────────

  def test_containing_walks_up_from_a_deep_file_to_the_root_index
    with_bundle(nested: true) do |b|
      b.path # materialise the fixture
      file = File.join(b.dir, "journal", "2020-01-01.md")

      assert_equal b.dir, OKF::Pro::BundleRoot.containing(file)
    end
  end

  # Directory indexes are free-form prose, and this bundle is about OKF — one
  # that MENTIONS okf_version must not stop the walk. Matching the bare token
  # anywhere did exactly that: the journal mis-rooted the bundle, rel lost its
  # journal/ prefix, and the append-only guard silently disarmed. Only the
  # frontmatter key counts, and directory indexes carry no frontmatter.
  def test_containing_is_not_fooled_by_the_token_in_index_prose
    with_bundle(nested: true) do |b|
      b.path # materialise first — finish rewrites journal/index.md, and a
      # write before it would be silently overwritten, leaving this
      # test green for any implementation at all
      File.write(File.join(b.dir, "journal", "index.md"),
        "# Journal\n\nThe okf_version field lives in the root index, not here.\nokf_version: quoted in prose, but no frontmatter above it.\n")
      file = File.join(b.dir, "journal", "2020-01-01.md")

      assert_equal b.dir, OKF::Pro::BundleRoot.containing(file)
    end
  end

  def test_containing_outside_any_bundle_is_nil
    Dir.mktmpdir("no-bundle-") do |dir|
      assert_nil OKF::Pro::BundleRoot.containing(File.join(dir, "x.md"))
    end
  end

  # An invalid byte in an ancestor index used to raise out of match?, and an
  # exception exits the checker with a code the hook protocol reads as
  # NON-BLOCKING — every guard failing open at once, from one bad byte.
  def test_containing_survives_invalid_utf8_in_an_index
    with_bundle(nested: true) do |b|
      b.path
      File.binwrite(File.join(b.dir, "journal", "index.md"),
        "---\ntitle: \xC3journal\n---\n# Journal\n")
      file = File.join(b.dir, "journal", "2020-01-01.md")

      assert_equal b.dir, OKF::Pro::BundleRoot.containing(file)
    end
  end

  # The scan is bounded by the closing fence, not a line count — frontmatter
  # with many keys before okf_version must still be recognised as the root.
  def test_containing_reads_long_frontmatter
    with_bundle(nested: true) do |b|
      b.path
      keys = (1..30).map { |i| "key_#{i}: value" }.join("\n")
      File.write(File.join(b.dir, "index.md"),
        "---\n#{keys}\nokf_version: \"0.1\"\n---\n\n# Root\n")
      file = File.join(b.dir, "journal", "2020-01-01.md")

      assert_equal b.dir, OKF::Pro::BundleRoot.containing(file)
    end
  end

  # The fence rule is the okf gem's, exactly — one rule, not two that drift.
  # Each behavior here reverted silently once, so each is pinned.

  def rewrite_root_index(b, content)
    b.path
    File.write(File.join(b.dir, "index.md"), content)
    File.join(b.dir, "journal", "2020-01-01.md")
  end

  def test_a_fence_with_trailing_blanks_is_a_fence
    with_bundle(nested: true) do |b|
      file = rewrite_root_index(b, "--- \nokf_version: \"0.1\"\n---\n\n# Root\n")

      assert_equal b.dir, OKF::Pro::BundleRoot.containing(file)
    end
  end

  def test_an_indented_dash_line_inside_frontmatter_is_not_a_fence
    with_bundle(nested: true) do |b|
      file = rewrite_root_index(b,
        "---\nsummary: |\n  ---\nokf_version: \"0.1\"\n---\n\n# Root\n")

      assert_equal b.dir, OKF::Pro::BundleRoot.containing(file)
    end
  end

  # The frontmatter scan stays gem-exact — root_index? refuses each of
  # these — but the walk no longer keys on it alone: board.md and log.md
  # beside the index are the second proof, so a mangled or frontmatterless
  # root index re-arms the guards instead of disarming them. Both halves
  # are pinned, because each has silently reverted once.

  def test_a_bom_prefixed_index_is_not_root_frontmatter_but_still_governs
    with_bundle(nested: true) do |b|
      file = rewrite_root_index(b,
        "\ufeff---\nokf_version: \"0.1\"\n---\n\n# Root\n")

      refute OKF::Pro::BundleRoot.root_index?(b.dir),
        "the gem refuses a BOM; the frontmatter scan must refuse it too"
      assert_equal b.dir, OKF::Pro::BundleRoot.containing(file),
        "the skeleton still proves the bundle — a mangled index must not disarm the guards"
    end
  end

  def test_frontmatter_that_never_closes_is_not_root_frontmatter_but_still_governs
    with_bundle(nested: true) do |b|
      prose = (1..40).map { |i| "line #{i} of prose" }.join("\n")
      file = rewrite_root_index(b,
        "---\n#{prose}\nokf_version: mentioned in prose at column zero\n\n# Root\n")

      refute OKF::Pro::BundleRoot.root_index?(b.dir),
        "a mangled block must not let column-zero prose count as frontmatter"
      assert_equal b.dir, OKF::Pro::BundleRoot.containing(file)
    end
  end

  def test_frontmatter_closing_past_the_stated_bound_is_not_root_frontmatter
    with_bundle(nested: true) do |b|
      keys = (1..120).map { |i| "key_#{i}: value" }.join("\n")
      file = rewrite_root_index(b,
        "---\n#{keys}\nokf_version: \"0.1\"\n---\n\n# Root\n")

      refute OKF::Pro::BundleRoot.root_index?(b.dir),
        "the 101-line bound is a stated limit; this pins the cliff as deliberate"
      assert_equal b.dir, OKF::Pro::BundleRoot.containing(file)
    end
  end

  # ── enclosing: the walk the stop gate roots through ───────────────────────

  # Same discriminator as containing(), applied to a directory: the stop gate
  # and the session banner have only the session's cwd, and resolve() neither
  # walked up (silent disengage from an index-less subdirectory) nor
  # discriminated (a directory index mistaken for a root, then reported as a
  # broken core on every Stop).
  def test_enclosing_walks_up_from_a_subdirectory
    with_bundle(git: true) do |b|
      dir = b.path
      notes = File.join(dir, "projects", "x", "notes")
      FileUtils.mkdir_p(notes)

      assert_equal dir, OKF::Pro::BundleRoot.enclosing(notes)
    end
  end

  def test_enclosing_prefers_the_nested_bundle
    with_bundle(nested: true) do |b|
      assert_equal b.bundle_path, OKF::Pro::BundleRoot.enclosing(b.path)
    end
  end

  def test_enclosing_reaches_the_nested_bundle_from_inside_it
    with_bundle(nested: true, git: true) do |b|
      b.path
      notes = File.join(b.bundle_path, "projects", "x")
      FileUtils.mkdir_p(notes)

      assert_equal b.bundle_path, OKF::Pro::BundleRoot.enclosing(notes)
    end
  end

  def test_enclosing_is_not_fooled_by_a_directory_index
    with_bundle(git: true) do |b|
      dir = b.path
      sub = File.join(dir, "reference")
      FileUtils.mkdir_p(sub)
      File.write(File.join(sub, "index.md"), "# Reference\n\nA directory index, no frontmatter.\n")

      assert_equal dir, OKF::Pro::BundleRoot.enclosing(sub)
    end
  end

  def test_enclosing_finds_nothing_outside_any_bundle
    Dir.mktmpdir do |dir|
      deep = File.join(dir, "a", "b")
      FileUtils.mkdir_p(deep)

      assert_nil OKF::Pro::BundleRoot.enclosing(deep)
    end
  end

  # The fence. A bundle above the session's own repository is somebody
  # else's: unbounded, the walk adopted it, every Stop in the unrelated
  # tree was interrogated against a bundle the session never touched, and
  # the banner printed a stranger's counters.
  def test_enclosing_stops_at_the_repository_boundary
    with_bundle(nested: true) do |b|
      repo = File.join(b.path, "code")
      app = File.join(repo, "app")
      FileUtils.mkdir_p(File.join(repo, ".git"))
      FileUtils.mkdir_p(app)

      assert_nil OKF::Pro::BundleRoot.enclosing(app)
    end
  end

  # Outside any repository there is no fence to stop at, so there is no
  # walk either — resolve()'s pre-walk semantics, which cannot adopt
  # anything above the directory it was handed.
  def test_enclosing_does_not_walk_outside_a_repository
    with_bundle(nested: true) do |b|
      app = File.join(b.path, "code", "app")
      FileUtils.mkdir_p(app)

      assert_nil OKF::Pro::BundleRoot.enclosing(app)
    end
  end

  # The same fence, on the guards' walk: a file inside a nested repository
  # must not summon the guards of the tree above it. Fixed on enclosing()
  # alone, the two walks disagreed about the identical layout — the stop
  # gate refused the stranger's bundle while the guards adopted it.
  def test_containing_stops_at_the_repository_boundary
    with_bundle(nested: true) do |b|
      repo = File.join(b.path, "code")
      app = File.join(repo, "app")
      FileUtils.mkdir_p(File.join(repo, ".git"))
      FileUtils.mkdir_p(app)
      file = File.join(app, "notes.md")
      File.write(file, "# Notes\n")

      assert_nil OKF::Pro::BundleRoot.containing(file)
    end
  end

  def test_containing_still_reaches_the_bundle_inside_its_own_repository
    with_bundle(nested: true, git: true) do |b|
      b.path
      file = File.join(b.bundle_path, "glossary", "term.md")

      assert_equal b.bundle_path, OKF::Pro::BundleRoot.containing(file)
    end
  end

  # The fence's comment promises worktrees and submodules — where .git is a
  # plain FILE, not a directory. Asserted in prose only, File.exist? could
  # narrow to File.directory? with every test green while every worktree
  # session lost its fence.
  def test_the_fence_recognises_a_git_file_worktree_pointer
    with_bundle(nested: true) do |b|
      repo = File.join(b.path, "code")
      app = File.join(repo, "app")
      FileUtils.mkdir_p(app)
      File.write(File.join(repo, ".git"), "gitdir: ../.git/worktrees/code\n")

      assert_nil OKF::Pro::BundleRoot.enclosing(app)
    end
  end

  # Outside any repository the single-level look still discriminates with
  # root?: falling back to resolve() (any index.md) quietly reinstated the
  # directory-index-mistaken-for-a-root bug for every non-git tree.
  def test_enclosing_without_a_repository_is_not_fooled_by_a_directory_index
    with_bundle do |b|
      sub = File.join(b.path, "reference")
      FileUtils.mkdir_p(sub)
      File.write(File.join(sub, "index.md"), "# Reference\n\nA directory index, no frontmatter.\n")

      assert_nil OKF::Pro::BundleRoot.enclosing(sub)
    end
  end

  # The okf format allows a frontmatterless root index — the gem's own
  # validator accepts one — and a walk keyed on frontmatter alone skipped
  # such a bundle and kept climbing: the stop gate went from re-rooted to
  # silently disengaged.
  def test_enclosing_recognises_a_frontmatterless_root_by_its_skeleton
    with_bundle(git: true) do |b|
      dir = b.path
      File.write(File.join(dir, "index.md"), "# My bundle\n\nNo frontmatter, and legal.\n")
      notes = File.join(dir, "projects", "x")
      FileUtils.mkdir_p(notes)

      assert_equal dir, OKF::Pro::BundleRoot.enclosing(notes)
    end
  end

  # ── strong roots beat weak ones; among weak, the outermost wins ──────────

  # The round-12 mis-rooting: a concept legitimately filed as
  # reference/log.md beside reference/index.md made the first-hit weak walk
  # stop deep inside a real bundle, and every guard audited a nonexistent
  # board. The versioned root above must win.
  def test_a_core_named_concept_does_not_mis_root_the_guards
    with_bundle(nested: true, git: true) do |b|
      b.path
      ref = File.join(b.bundle_path, "reference")
      FileUtils.mkdir_p(ref)
      File.write(File.join(ref, "index.md"), "# Reference\n")
      File.write(File.join(ref, "log.md"), "---\ntype: Briefing\ntitle: Log\ndescription: A concept that happens to be named log.\n---\n\n# Log\n")
      file = File.join(ref, "term.md")
      File.write(file, "x")

      assert_equal b.bundle_path, OKF::Pro::BundleRoot.containing(file)
    end
  end

  # Same shape under a frontmatterless root: no strong proof anywhere, so
  # the OUTERMOST weak candidate inside the fence is the bundle — a real
  # root contains its directories, never the other way around.
  def test_among_weak_candidates_the_outermost_wins
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".git"))
      File.write(File.join(dir, "index.md"), "# My bundle\n")
      File.write(File.join(dir, "board.md"), "# Board\n")
      ref = File.join(dir, "reference")
      FileUtils.mkdir_p(ref)
      File.write(File.join(ref, "index.md"), "# Reference\n")
      File.write(File.join(ref, "log.md"), "a concept named log\n")
      file = File.join(ref, "term.md")
      File.write(file, "x")

      assert_equal dir, OKF::Pro::BundleRoot.containing(file)
    end
  end

  # The log.md half of the weak disjunction, tested on its own: deleting
  # that operand must fail a test, not just a comment.
  def test_a_bare_index_with_only_a_log_still_governs
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "index.md"), "# My bundle\n")
      File.write(File.join(dir, "log.md"), "# Update Log\n")
      file = File.join(dir, "term.md")
      File.write(file, "x")

      assert_equal dir, OKF::Pro::BundleRoot.containing(file)
    end
  end

  # ── the three tiers, under coincidence ────────────────────────────────────

  # A directory literally named .okf is the convention's own marker
  # (:anchored): outer-weak-wins let a coincidental index.md + log.md at
  # the repo root usurp a frontmatterless .okf bundle — and Target.for
  # then rejected the '.okf/...' rel path, so every write-time guard went
  # quiet while the stop gate rooted correctly. Two doors, two bundles.
  def test_a_nested_bundle_beats_outer_coincidence_for_the_guards
    Dir.mktmpdir do |repo|
      FileUtils.mkdir_p(File.join(repo, ".git"))
      File.write(File.join(repo, "index.md"), "# Docs page\n")
      File.write(File.join(repo, "log.md"), "# Changelog\n")
      okf = File.join(repo, ".okf")
      FileUtils.mkdir_p(File.join(okf, "reference"))
      File.write(File.join(okf, "index.md"), "# Bundle\n")
      File.write(File.join(okf, "board.md"), "# Board\n")
      file = File.join(okf, "reference", "x.md")
      File.write(file, "x")

      assert_equal okf, OKF::Pro::BundleRoot.containing(file)
    end
  end

  def test_an_inner_nested_bundle_beats_outer_coincidence_for_the_gate
    Dir.mktmpdir do |repo|
      FileUtils.mkdir_p(File.join(repo, ".git"))
      File.write(File.join(repo, "index.md"), "# Docs page\n")
      File.write(File.join(repo, "log.md"), "# Changelog\n")
      okf = File.join(repo, "docs", ".okf")
      FileUtils.mkdir_p(okf)
      File.write(File.join(okf, "index.md"), "# Bundle\n")
      File.write(File.join(okf, "board.md"), "# Board\n")
      src = File.join(repo, "docs", "src")
      FileUtils.mkdir_p(src)

      assert_equal okf, OKF::Pro::BundleRoot.enclosing(src)
    end
  end

  # Unfenced, "outermost" is unbounded: climbing toward the filesystem
  # root adopted a stranger's index+log over the bundle the file actually
  # lives in — so with no repository the nearest weak root wins.
  def test_without_a_fence_the_nearest_weak_root_wins
    Dir.mktmpdir do |dir|
      docs = File.join(dir, "Documents")
      brain = File.join(docs, "brain")
      FileUtils.mkdir_p(File.join(brain, "journal"))
      File.write(File.join(docs, "index.md"), "# Unrelated notes\n")
      File.write(File.join(docs, "log.md"), "# Unrelated log\n")
      File.write(File.join(brain, "index.md"), "# Bundle\n")
      File.write(File.join(brain, "board.md"), "# Board\n")
      file = File.join(brain, "journal", "2026-08-12.md")
      File.write(file, "x")

      assert_equal brain, OKF::Pro::BundleRoot.containing(file)
    end
  end

  # enclosing's plain-weak path, pinned: a frontmatterless root-layout
  # bundle still roots the stop gate from a subdirectory.
  def test_the_gate_reaches_a_frontmatterless_root_from_a_subdirectory
    Dir.mktmpdir do |repo|
      FileUtils.mkdir_p(File.join(repo, ".git"))
      File.write(File.join(repo, "index.md"), "# Bundle\n")
      File.write(File.join(repo, "log.md"), "# Update Log\n")
      sub = File.join(repo, "projects", "x")
      FileUtils.mkdir_p(sub)

      assert_equal repo, OKF::Pro::BundleRoot.enclosing(sub)
    end
  end

  # A root that does not contain the file is no root of it: the sibling
  # `.okf` probe adopted repo/.okf for repo/reference/x.md, the rel path
  # nil'd out inside Target.for, and every write-time guard skipped the
  # edit in silence. A file actually inside `.okf` meets it as the dir
  # itself on the way up, so containing loses nothing by not probing.
  def test_containing_never_returns_a_root_that_lacks_the_file
    Dir.mktmpdir do |repo|
      FileUtils.mkdir_p(File.join(repo, ".git"))
      File.write(File.join(repo, "index.md"), "# Bundle\n")
      File.write(File.join(repo, "board.md"), "# Board\n")
      stray = File.join(repo, ".okf")
      FileUtils.mkdir_p(stray)
      File.write(File.join(stray, "index.md"), "# Stray\n")
      File.write(File.join(stray, "log.md"), "# Stray log\n")
      FileUtils.mkdir_p(File.join(repo, "reference"))
      file = File.join(repo, "reference", "x.md")
      File.write(file, "x")

      root = OKF::Pro::BundleRoot.containing(file)

      assert_equal repo, root
      assert file.start_with?("#{root}/"), "the returned root must contain the file"
    end
  end
end
