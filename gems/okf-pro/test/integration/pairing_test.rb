# frozen_string_literal: true

require "test_helper"

# The board↔work invariants: everything open is on the board, and everything
# on the board is still owed something. These are what an editor-made commit
# bypasses entirely, which is why they are also the CI door's payload.
class PairingTest < OKF::Pro::TestCase
  # `closed?` contained against `<bundle>/projects`, not against the bundle
  # root, so `SafeRead` refused any project index whose realpath left
  # `projects/` — including one that never leaves the BUNDLE. A project
  # legitimately archived behind a symlink read as open forever, and the audit
  # demanded a board line for a project that was closed months ago.
  def test_a_project_symlinked_within_the_bundle_is_still_read
    with_bundle do |b|
      b.write("archive/beta/index.md", "# Beta — closed 2026-08-01\n\nDone.\n")
      root = b.bundle_path
      FileUtils.mkdir_p(File.join(root, "projects"))
      File.symlink(File.join("..", "archive", "beta"), File.join(root, "projects", "beta"))

      assert OKF::Pro::Pairing.closed?(root, File.join(root, "projects", "beta", "index.md"))
      refute_includes OKF::Pro::Pairing.open_projects(root), "beta"
    end
  end

  BRIEFING_BODY = "# Summary\n\nAn agent read the source so nobody else had to. Yet.\n"

  def test_a_project_with_a_board_line_passes
    with_bundle do |b|
      b.write("projects/home-move/index.md", "# Home move\n\nOngoing.\n")
      b.in_flight("[/projects/home-move/](/projects/home-move/index.md) — call the movers")

      assert_empty OKF::Pro::Pairing.failures(b.path)
    end
  end

  def test_an_unpaired_project_is_reported
    with_bundle do |b|
      b.write("projects/home-move/index.md", "# Home move\n\nOngoing.\n")

      failures = OKF::Pro::Pairing.failures(b.path)

      assert_equal 1, failures.size
      assert_match(%r{projects/home-move has no board line}, failures.first)
    end
  end

  # Closure is declared on the index's first line. That is the whole reason
  # closing a project moves no files.
  def test_a_closed_project_needs_no_board_line
    with_bundle do |b|
      b.write("projects/home-move/index.md", "# Home move — closed 2026-08-12\n\nDone.\n")

      assert_empty OKF::Pro::Pairing.failures(b.path)
    end
  end

  def test_closed_further_down_the_body_does_not_count
    with_bundle do |b|
      b.write("projects/home-move/index.md",
        "# Home move\n\nOngoing.\n\nThe storage unit was closed last year.\n")

      refute_empty OKF::Pro::Pairing.failures(b.path)
    end
  end

  def test_an_unverified_briefing_needs_a_read_owed_line
    with_bundle do |b|
      b.concept("reference/movers-quote.md", type: "Briefing", body: BRIEFING_BODY,
        generated: { by: "claude", at: "2026-08-12" })

      failures = OKF::Pro::Pairing.failures(b.path)

      assert_equal 1, failures.size
      assert_match(/unverified briefing reference\/movers-quote\.md/, failures.first)
      assert_match(/silently left the attention system/, failures.first)
    end
  end

  def test_an_unverified_briefing_on_the_board_passes
    with_bundle do |b|
      b.concept("reference/movers-quote.md", type: "Briefing", body: BRIEFING_BODY,
        generated: { by: "claude", at: "2026-08-12" })
      b.inbox("[/reference/movers-quote.md] — the movers' quote (agent-summarised, unread)")

      assert_empty OKF::Pro::Pairing.failures(b.path)
    end
  end

  # The owner's attestation is what takes the briefing out of the attention
  # system. This is the one place in the suite the key is written, and it is
  # written into a temp directory that exists for the length of one test —
  # never into this bundle, where only the owner may type it.
  def test_an_attested_briefing_is_no_longer_owed
    with_bundle do |b|
      b.concept("reference/movers-quote.md", type: "Briefing", body: BRIEFING_BODY,
        generated: { by: "claude", at: "2026-08-12" },
        verified: { by: "human:owner", at: "2026-08-13" })

      assert_empty OKF::Pro::Pairing.failures(b.path)
    end
  end

  # §5.3 is the whole of the rule now, and this is the case it added: a nightly
  # process confirming a briefing against its source is a real verification —
  # the concept is machine-confirmed, not unverified — and it still does not
  # discharge the owner's read. Testing `verified` for truthiness said it did,
  # and the To-read line vanished for a briefing nobody had read.
  def test_a_machine_verification_does_not_discharge_the_owners_read
    with_bundle do |b|
      b.concept("reference/movers-quote.md", type: "Briefing", body: BRIEFING_BODY,
        generated: { by: "claude/opus-5", at: "2026-08-12" },
        verified: { by: "process:nightly-recheck", at: "2026-08-13" })

      failures = OKF::Pro::Pairing.failures(b.path)

      assert_equal 1, failures.size
      assert_match(/has no read-owed board line/, failures.first)
    end
  end

  # And the same fact from the other side: with the line present, a
  # machine-confirmed briefing is not "already verified, drop the line". The two
  # checks are exact opposites, and a briefing that fell through both would
  # leave the attention system with nobody noticing.
  def test_a_machine_verified_briefing_keeps_its_read_owed_line
    with_bundle do |b|
      b.concept("reference/movers-quote.md", type: "Briefing", body: BRIEFING_BODY,
        generated: { by: "claude/opus-5", at: "2026-08-12" },
        verified: { by: "process:nightly-recheck", at: "2026-08-13" })
      b.board_lines("To read", "[/reference/movers-quote.md] — agent-summarised")

      assert_empty OKF::Pro::Pairing.failures(b.path)
    end
  end

  # A concept nobody generated was written by a person in the first place, so
  # there is nothing outstanding to attest to.
  def test_a_hand_written_reference_is_not_a_briefing
    with_bundle do |b|
      b.concept("reference/hand-notes.md", type: "Briefing", body: BRIEFING_BODY)

      assert_empty OKF::Pro::Pairing.failures(b.path)
    end
  end

  def test_generated_concepts_outside_reference_are_not_briefings
    with_bundle do |b|
      b.concept("learnings/a-conclusion.md", type: "Learning",
        generated: { by: "claude", at: "2026-08-12" })

      assert_empty OKF::Pro::Pairing.failures(b.path)
    end
  end

  def test_matching_is_case_insensitive
    with_bundle do |b|
      b.write("projects/Home-Move/index.md", "# Home move\n\nOngoing.\n")
      b.in_flight("[/projects/home-move/](/projects/home-move/index.md) — call the movers")

      assert_empty OKF::Pro::Pairing.failures(b.path)
    end
  end

  # ── the one shell-out ─────────────────────────────────────────────────────

  def test_a_repository_with_uncommitted_markdown_is_dirty
    with_bundle(git: true) do |b|
      b.concept("glossary/term.md", type: "Term")

      assert OKF::Pro::Pairing.dirty_markdown?(b.path)
    end
  end

  # Only a git that ran and answered may disengage the stop gate. A root
  # outside any repository makes git fail rather than vanish, and that used
  # to read as "no work happened" — the silent-disarm hole.
  def test_a_directory_with_no_repository_fails_closed_as_dirty
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")

      assert OKF::Pro::Pairing.dirty_markdown?(b.path)
    end
  end
  # ── strictness: pairing is by link, never by substring ────────────────────

  # The first cut asked `board.include?(slug)`, which a slug mentioned in any
  # unrelated capture line satisfied — a false pass in the fail-open direction.
  def test_a_prose_mention_does_not_pair_a_project
    with_bundle do |b|
      b.write("projects/home-move/index.md", "# Home move\n\nOngoing.\n")
      b.inbox("heard something about the home-move at lunch")

      assert_match(%r{projects/home-move has no board line},
        OKF::Pro::Pairing.failures(b.path).first)
    end
  end

  # ── the reverse direction ─────────────────────────────────────────────────

  def test_a_board_link_to_nothing_is_reported
    with_bundle do |b|
      b.inbox("2026-08-12 — Resolve: [/reference/vanished.md] says X, memory says Y")

      failures = OKF::Pro::Pairing.failures(b.path)

      assert_equal 1, failures.size
      assert_match(%r{links /reference/vanished\.md, which does not exist}, failures.first)
    end
  end

  def test_a_board_line_still_linking_a_closed_project_is_reported
    with_bundle do |b|
      b.write("projects/home-move/index.md", "# Home move — closed 2026-08-12\n\nDone.\n")
      b.in_flight("[/projects/home-move/](/projects/home-move/index.md) — call the movers")

      failures = OKF::Pro::Pairing.failures(b.path)

      assert_equal 1, failures.size
      assert_match(%r{still links projects/home-move, which is closed}, failures.first)
    end
  end

  def test_a_read_owed_line_for_a_verified_briefing_is_reported
    with_bundle do |b|
      b.concept("reference/movers-quote.md", type: "Briefing", body: BRIEFING_BODY,
        generated: { by: "claude", at: "2026-08-12" },
        verified: { by: "human:owner", at: "2026-08-13" })
      b.board_lines("To read", "[/reference/movers-quote.md] — agent-summarised")

      failures = OKF::Pro::Pairing.failures(b.path)

      assert_equal 1, failures.size
      assert_match(/already verified/, failures.first)
      assert_match(/reading removes the line/, failures.first)
    end
  end

  # Documents live outside bundles too; a read-owed line with no bundle link
  # is not this check's business.
  def test_a_read_owed_line_without_a_bundle_link_is_fine
    with_bundle do |b|
      b.board_lines("To read", "Q3 planning doc from Maria, in the shared drive")

      assert_empty OKF::Pro::Pairing.failures(b.path)
    end
  end

  def test_a_healthy_board_passes_in_both_directions
    with_bundle do |b|
      b.concept("reference/movers-quote.md", type: "Briefing", body: BRIEFING_BODY,
        generated: { by: "claude", at: "2026-08-12" })
      b.write("projects/home-move/index.md", "# Home move\n\nOngoing.\n")
      b.in_flight("[/projects/home-move/](/projects/home-move/index.md) — call the movers")
      b.board_lines("To read", "[/reference/movers-quote.md] — agent-summarised, unread")
      b.inbox("2026-08-12 — Resolve: [/reference/movers-quote.md] says X, the term says Y")

      assert_empty OKF::Pro::Pairing.failures(b.path)
    end
  end

  # Closure needs the dated marker, not the vocabulary. /closed/i as a bare
  # substring cut both ways on a project literally named for it: the live
  # project's board line was refused as stale, and the same misread exempted
  # it from the unpaired check when it had no line at all.
  def test_a_project_named_closed_loop_is_open
    with_bundle do |b|
      b.write("projects/closed-loop-eval/index.md", "# Closed-loop evaluation rig\n\nLive.\n")
      b.in_flight("[/projects/closed-loop-eval/](/projects/closed-loop-eval/index.md) — wire the rig")

      assert_empty OKF::Pro::Pairing.failures(b.path)
    end
  end

  def test_a_boardless_project_named_closed_loop_is_reported_unpaired
    with_bundle do |b|
      b.write("projects/closed-loop-eval/index.md", "# Closed-loop evaluation rig\n\nLive.\n")

      failures = OKF::Pro::Pairing.failures(b.path)

      assert_equal 1, failures.size
      assert_match(%r{projects/closed-loop-eval has no board line}, failures.first)
    end
  end

  def test_disclosed_in_the_title_is_not_closure
    with_bundle do |b|
      b.write("projects/audit-prep/index.md", "# What we disclosed in the audit 2026-01-05\n\nOngoing.\n")

      refute OKF::Pro::Pairing.closed?(b.dir, File.join(b.dir, "projects/audit-prep/index.md"))
    end
  end

  def test_the_closure_word_without_a_date_is_not_closure
    with_bundle do |b|
      b.write("projects/home-move/index.md", "# Home move — closed\n\nNo date given.\n")

      refute OKF::Pro::Pairing.closed?(b.dir, File.join(b.dir, "projects/home-move/index.md"))
    end
  end

  # A #fragment resolves for the reader; the entry list only ever holds the
  # file. Keeping the fragment failed a link that lands fine.
  def test_a_board_link_with_a_fragment_is_not_broken
    with_bundle do |b|
      b.concept("reference/movers-quote.md", type: "Briefing", body: BRIEFING_BODY)
      b.inbox("2026-08-10 — re-read [the quote](/reference/movers-quote.md#terms)")

      assert_empty OKF::Pro::Pairing.broken_targets(b.path, OKF::Pro.read_text(File.join(b.dir, "board.md")))
    end
  end

  # Two independent substring tests — the word somewhere AND a date somewhere
  # — closed any project whose title mentioned both. The marker is one tied
  # pattern, and hyphen-joined names are names.
  def test_a_dated_closed_loop_title_is_still_open
    with_bundle do |b|
      b.write("projects/closed-loop-eval/index.md",
        "# Closed-loop evaluation rig — kickoff 2026-01-05\n\nLive.\n")
      b.in_flight("[/projects/closed-loop-eval/](/projects/closed-loop-eval/index.md) — wire the rig")

      assert_empty OKF::Pro::Pairing.failures(b.path)
    end
  end

  # The old convention read the top three lines, and real bundles used them.
  # A marker on line two must not silently reopen a closed project.
  def test_a_closure_marker_on_line_two_still_counts
    with_bundle do |b|
      b.write("projects/home-move/index.md", "# Home move\nClosed 2026-05-01.\n\nDone.\n")

      assert_empty OKF::Pro::Pairing.failures(b.path)
    end
  end

  # ENOENT is the same "nobody can tell" as a failing git, and the branch is
  # pinned here by making the spawn itself impossible: an empty PATH.
  def test_dirty_markdown_fails_closed_when_git_is_absent
    with_bundle do |b|
      empty = Dir.mktmpdir("no-git-")
      was = ENV.fetch("PATH", nil)
      ENV["PATH"] = empty
      begin
        assert OKF::Pro::Pairing.dirty_markdown?(b.path)
      ensure
        ENV["PATH"] = was
        Dir.rmdir(empty)
      end
    end
  end

  # Prose is not a marker. "closed the deal with the vendor on 2026-08-05" in
  # an index's top lines used to close the project — and with no board line
  # the misread was silent: the project simply vanished from the unpaired
  # check. Adjacency of word and date is what a marker has and a sentence
  # does not.
  def test_prose_about_closing_a_deal_does_not_close_the_project
    with_bundle do |b|
      b.write("projects/vendor-deal/index.md",
        "# Vendor deal\nKickoff 2026-08-01 — closed the deal with the vendor on 2026-08-05.\n\nLive.\n")

      failures = OKF::Pro::Pairing.failures(b.path)

      assert_equal 1, failures.size
      assert_match(%r{projects/vendor-deal has no board line}, failures.first)
    end
  end

  # The marker's grammar, pinned spelling by spelling: punctuation and
  # emphasis may sit between the word and the date; words may not. Every
  # branch of MARKER is covered here because a gate whose alternates have no
  # test can be widened or dropped with the suite still green.
  def test_every_documented_closure_spelling_counts
    [ "# Home move — closed 2026-08-12",
      "Closed: 2026-05-01.",
      "# Home move — Closed — 2026-08-12",
      "**Closed** 2026-08-12",
      "closed (2026-08-12)",
      "closed:2026-08-12" ].each do |line|
      assert OKF::Pro::Pairing.marker?(line), "expected marker: #{line.inspect}"
    end
  end

  def test_sentences_about_closing_are_not_markers
    [ "The office closed on 2026-01-05.",
      "closed the deal with the vendor on 2026-08-05",
      "# Closed-loop evaluation rig — kickoff 2026-01-05",
      "We disclosed 2026-01-05 figures.",
      "not closed: 2026-08-12",
      "Never closed 2026-08-12",
      "**not** closed 2026-08-12",
      "not  closed 2026-08-12",
      "wasn't closed 2026-08-12",
      "wasn\u2019t closed 2026-08-12",
      "no longer closed 2026-08-12",
      "we closed, 2026-01-05, the books",
      "# Home move — closed" ].each do |line|
      refute OKF::Pro::Pairing.marker?(line), "expected no marker: #{line.inspect}"
    end
  end

  # Visible lines only, here too: a commented-out sample line is not a
  # pairing target, so its link cannot rot into a broken-target finding.
  def test_a_commented_board_line_is_not_a_pairing_target
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      dir = b.path
      board_path = File.join(dir, "board.md")
      board = OKF::Pro.read_text(board_path)
      File.write(board_path, board + "\n<!-- example: -->\n<!-- - [/reference/ghost.md] — a sample link -->\n")

      assert_empty OKF::Pro::Pairing.failures(dir)
    end
  end
end
