# frozen_string_literal: true

require "test_helper"

# Pure text in, numbers out. Rule 3 is enforced entirely on what this module
# counts, so the counting rules are worth pinning without a bundle in the way.
class BoardTest < OKF::Pro::TestCase
  # grammar() checks the section invariant directly — every canonical
  # section present as an exact heading — so grammar fixtures carry the
  # full frame, with the section bodies under test spliced in.
  def full_board(sections = {}, prefix = nil)
    body = OKF::Pro::Board::SECTIONS.map do |name|
      "## #{name}\n#{sections[name] || ""}"
    end.join("\n")
    [ prefix, body ].compact.join("\n\n")
  end
  BOARD = <<~MD
    # Board

    **In flight: 2/5** · updated 2026-08-12

    ## In flight
    - one
    - two

    ## Backlog
    - three
    - four
    - five

    ## Waiting

    ## Inbox
    - six
  MD

  def test_counts_only_the_named_section
    assert_equal 2, OKF::Pro::Board.count(BOARD, "In flight")
    assert_equal 3, OKF::Pro::Board.count(BOARD, "Backlog")
    assert_equal 1, OKF::Pro::Board.count(BOARD, "Inbox")
  end

  def test_an_empty_section_counts_zero
    assert_equal 0, OKF::Pro::Board.count(BOARD, "Waiting")
  end

  def test_an_absent_section_counts_zero
    assert_equal 0, OKF::Pro::Board.count(BOARD, "Deadlines")
  end

  # The header line itself starts with `**`, not `- `, and the prose above the
  # first section must not leak into any count.
  def test_only_list_lines_count
    board = "# Board\n\n**In flight: 0/5**\n\n## In flight\nsome prose\n  - indented\n- real\n"

    assert_equal 1, OKF::Pro::Board.count(board, "In flight")
  end

  def test_reads_the_budget_header
    budget = OKF::Pro::Board.budget(BOARD)

    assert_equal 2, budget.declared
    assert_equal 5, budget.cap
  end

  def test_budget_is_nil_when_the_header_is_gone
    assert_nil OKF::Pro::Board.budget("# Board\n\n## In flight\n- one\n")
  end

  # Matched by shape, not by the words. A sentence mentioning the phrase must
  # not be mistaken for the budget face.
  def test_prose_mentioning_in_flight_is_not_a_budget
    assert_nil OKF::Pro::Board.budget("Nothing is in flight: everything is waiting.\n")
  end

  def test_budget_tolerates_spacing_and_case
    budget = OKF::Pro::Board.budget("in flight:   3 / 7\n")

    assert_equal 3, budget.declared
    assert_equal 7, budget.cap
  end

  def test_handles_empty_input
    assert_equal 0, OKF::Pro::Board.count("", "In flight")
    assert_nil OKF::Pro::Board.budget("")
  end
  # ── links and dates ───────────────────────────────────────────────────────

  def test_targets_reads_markdown_links
    line = "- [/projects/home-move/](/projects/home-move/index.md) — call the movers"

    assert_includes OKF::Pro::Board.targets(line), "/projects/home-move/index.md"
  end

  # Capture lines use the bare form — five seconds does not stop to type a
  # link twice.
  def test_targets_reads_bare_bracket_links
    line = "- 2026-08-12 — Resolve: [/reference/a.md] says X, [/glossary/b.md] says Y"

    assert_equal [ "/reference/a.md", "/glossary/b.md" ], OKF::Pro::Board.targets(line)
  end

  def test_targets_ignores_links_that_leave_the_bundle
    assert_empty OKF::Pro::Board.targets("- [the spec](https://example.com/spec) — external")
  end

  def test_targets_on_a_plain_line_is_empty
    assert_empty OKF::Pro::Board.targets("- promote to /projects/storage-unit/ when real")
  end

  def test_line_date_reads_the_leading_capture_date
    assert_equal Date.new(2026, 8, 12), OKF::Pro::Board.line_date("- 2026-08-12 — heard a thing")
  end

  def test_line_date_is_nil_without_one
    assert_nil OKF::Pro::Board.line_date("- no date here")
  end

  # A counter must not invent: a date the calendar rejects is absent, not
  # approximated.
  def test_line_date_rejects_impossible_dates
    assert_nil OKF::Pro::Board.line_date("- 2026-13-99 — typo")
  end

  def test_chase_date_reads_the_chase_marker
    line = "- Landlord: inspection date — asked 2026-08-12, chase 2026-08-15"

    assert_equal Date.new(2026, 8, 15), OKF::Pro::Board.chase_date(line)
  end

  def test_chase_date_is_nil_without_a_marker
    assert_nil OKF::Pro::Board.chase_date("- Landlord: asked 2026-08-12, no chase set")
  end

  # \D* crawled across newlines: a header that lost its numbers fabricated a
  # budget from the next N/M anywhere below — an Inbox line's "3/4 of the
  # deck" became declared 3, cap 4, and the lost-header refusal never fired.
  def test_budget_is_nil_when_the_header_lost_its_numbers
    board = "**In flight:**\n\n- capture: finished 3/4 of the deck\n"

    assert_nil OKF::Pro::Board.budget(board)
  end

  def test_budget_still_reads_its_own_line
    assert_equal 2, OKF::Pro::Board.budget("**In flight: 2/5** · whatever").declared
  end

  # Fragments are reader aids; the file on disk has none. A kept fragment made
  # a resolving link fail the existence check.
  def test_targets_strip_fragments
    line = "- read [context](/reference/x.md#tiers) and [/glossary/y.md#top]"

    assert_equal [ "/reference/x.md", "/glossary/y.md" ], OKF::Pro::Board.targets(line)
  end

  # The first anchoring fix stopped \\D* crossing newlines but left the match
  # unanchored to the line, and \\s* around the slash still crossed them.
  def test_budget_ignores_in_flight_mid_capture_line
    board = "**In flight:**\n\n- deck in flight: 3/4 done\n"

    assert_nil OKF::Pro::Board.budget(board)
  end

  def test_budget_does_not_read_a_date_below_as_the_cap
    board = "In flight: 3 /\n2026-08-10 — a dated line\n"

    assert_nil OKF::Pro::Board.budget(board)
  end

  # ── the date grammar, loudly ──────────────────────────────────────────────

  # A dated line the counters cannot parse used to count as zero, silently —
  # "- Due Aug 18: filing" made "deadlines within 7d" say 0, the stop gate
  # agreed with itself, and the deadline landed unclaimed. Unreadable is a
  # finding now, not a rounding error.
  def test_dated_lines_in_the_documented_grammar_raise_nothing
    board = full_board(
      "Waiting" => "- Landlord: inspection — asked 2026-08-01, chase 2026-08-15\n",
      "Inbox" => "- 2026-08-12 — heard about the movers at lunch\n",
      "Deadlines" => "- 2026-08-18 — file the insurance claim\n"
    )

    assert_empty OKF::Pro::Board.grammar(board)
  end

  def test_an_undated_deadline_is_a_finding
    findings = OKF::Pro::Board.grammar(full_board("Deadlines" => "- Due Aug 18: filing\n"))

    assert_equal 1, findings.size
    assert_match(/7-day warning cannot see it.*Due Aug 18/, findings.first)
  end

  def test_a_waiting_line_without_a_chase_date_is_a_finding
    findings = OKF::Pro::Board.grammar(full_board("Waiting" => "- Landlord: inspection — chase by 08-20\n"))

    assert_equal 1, findings.size
    assert_match(/past-chase counter cannot see it/, findings.first)
  end

  def test_an_undated_inbox_capture_is_a_finding
    findings = OKF::Pro::Board.grammar(full_board("Inbox" => "- heard something at lunch\n"))

    assert_equal 1, findings.size
    assert_match(/oldest-capture counter cannot see it/, findings.first)
  end

  # A date the calendar rejects already parsed to nil ("a counter must not
  # invent"); now the nil is loud instead of a silent zero.
  def test_a_calendar_rejected_date_is_a_finding
    refute_empty OKF::Pro::Board.grammar(full_board("Deadlines" => "- 2026-13-01 — impossible month\n"))
  end

  def test_backlog_and_to_read_lines_are_exempt
    board = full_board("Backlog" => "- sort the storage unit\n",
      "To read" => "- [/reference/quote.md] — unread\n")

    assert_empty OKF::Pro::Board.grammar(board)
  end

  # The word is boundary-anchored: without it, "purchase 2026-09-01" read as
  # a chase date, satisfied the grammar check built to demand one, and
  # reported an overdue chase nobody ever set.
  def test_a_word_ending_in_chase_is_not_a_chase_date
    line = "- Bookstore: purchase 2026-09-01 pre-order, no chase set"

    assert_nil OKF::Pro::Board.chase_date(line)
    assert_match(/past-chase counter cannot see it/,
      OKF::Pro::Board.grammar(full_board("Waiting" => "#{line}\n")).first)
  end

  def test_a_real_chase_after_other_words_still_parses
    assert_equal Date.new(2026, 8, 15),
      OKF::Pro::Board.chase_date("- Landlord: inspection — asked 2026-08-01, chase 2026-08-15")
  end

  # ── stray bullets ─────────────────────────────────────────────────────────

  # section_lines reads '- ' at column zero, everywhere — so a '*' bullet or
  # an indented dash was a line every counter was blind to, including the
  # cap, and the date checks inherited the blindness by reading only the
  # lines the counters read. The stray-bullet pass walks the raw text.
  def test_a_star_bulleted_deadline_is_a_finding_not_a_silent_zero
    board = full_board("Deadlines" => "* 2026-08-18 - file the claim\n")

    assert_equal 0, OKF::Pro::Board.count(board, "Deadlines")
    assert_match(/no counter can see it.*file the claim/, OKF::Pro::Board.grammar(board).first)
  end

  def test_an_indented_dash_is_a_finding
    refute_empty OKF::Pro::Board.grammar(full_board("In flight" => "  - hidden from the cap\n"))
  end

  # A bulleted example inside an HTML comment is documentation, not a board
  # line — flagging it turned a comment after any heading into a refusal at
  # every Stop until the documentation was deleted.
  # A longer note is a STACK of single-line comments — the only comment
  # shape the board accepts, because every multi-line region model failed
  # open under splicing.
  def test_a_bulleted_example_inside_html_comments_is_not_a_stray
    board = full_board("Inbox" => <<~SECTION)
      - 2026-08-12 — a real capture
      <!-- capture format: -->
      <!--   - 2026-08-12 — the words you heard -->
      <!--   * never use star bullets -->
    SECTION

    assert_empty OKF::Pro::Board.grammar(board)
    assert_equal 1, OKF::Pro::Board.count(board, "Inbox")
  end

  def test_a_stray_after_a_comment_block_is_still_flagged
    board = "## Inbox\n<!-- one-line comment -->\n  - still hidden from the counters\n"

    refute_empty OKF::Pro::Board.grammar(board)
  end

  def test_the_budget_header_and_html_comments_are_not_stray_bullets
    board = full_board({ "In flight" => "- 2026-08-12 real\n" },
      "# Board\n\n**In flight: 1/5**\n\n<!-- a comment -->")

    assert_empty OKF::Pro::Board.grammar(board)
  end

  # ── comments, character-granular and shared ───────────────────────────────

  # An opener that never closes is confessed — and, crucially, nothing is
  # hidden: the unterminated region is treated as board text, because six
  # readers consume the visible text and only grammar() can confess, so a
  # silent truncation zeroed the banner's counters and told the writer to
  # "fix" a correct budget header.
  def test_an_unterminated_comment_is_confessed_and_hides_nothing
    board = "## Inbox\n<!-- oops, never closed\n  - hidden stray\n* starred deadline\n"

    findings = OKF::Pro::Board.grammar(board)

    assert(findings.any? { |f| f =~ /has no '-->'/ }, findings.inspect)
    assert(findings.any? { |f| f =~ /no counter can see it.*hidden stray/ }, findings.inspect)
    assert(findings.any? { |f| f =~ /no counter can see it.*starred deadline/ }, findings.inspect)
  end

  def test_an_unterminated_comment_leaves_the_counters_honest
    board = <<~MD
      **In flight: 3/5**

      <!-- a note that never closes

      ## In flight
      - one
      - two
      - three
    MD

    assert_equal 3, OKF::Pro::Board.count(board, "In flight")
    assert_empty OKF::Pro::Budget.check_text(board)
    assert(OKF::Pro::Board.grammar(board).any? { |f| f =~ /has no '-->'/ })
  end

  # Every reader consumes the same visible text: a commented sample line
  # must not be counted by the cap while the stray pass calls it invisible —
  # that split produced a refusal whose only exit was deleting the docs.
  def test_a_commented_sample_line_is_invisible_to_the_counters_too
    board = <<~MD
      **In flight: 1/5**

      ## In flight
      - the real demand
      <!-- example: -->
      <!-- - 2026-08-12 a sample line -->
    MD

    assert_equal 1, OKF::Pro::Board.count(board, "In flight")
    assert_empty OKF::Pro::Budget.check_text(board)
  end

  def test_a_commented_undated_capture_is_not_date_flagged
    board = full_board("Inbox" => "<!-- - a sample capture with no date -->\n- 2026-08-12 — real\n")

    assert_empty OKF::Pro::Board.grammar(board)
  end

  # The board's comment rule is deliberately narrower than HTML's: a
  # region opens only when `<!--` opens its line. Character-granular
  # mid-line openers were tried and failed open — a `<!--` in one
  # capture's prose plus a `-->` in another's silently swallowed every
  # real line between them from every counter at once. The trade is a
  # LOUD false positive instead: documentation opened mid-line gets its
  # example bullets flagged, and the flag says what to do.
  def test_a_mid_line_opener_swallows_nothing_and_is_confessed
    board = full_board("Inbox" => "- 2026-08-12 note about the <!-- opener\n- 2026-08-13 real capture\n- 2026-08-14 close with -->\n")

    findings = OKF::Pro::Board.grammar(board)

    assert_equal 3, OKF::Pro::Board.count(board, "Inbox")
    assert_equal 1, findings.size
    assert_match(/has no '-->'/, findings.first)
  end

  def test_documentation_opened_mid_line_is_flagged_loudly_not_swallowed
    board = "## Inbox\n- 2026-08-12 — real capture <!-- format:\n  - example bullet one\n-->\n"

    assert_equal 1, OKF::Pro::Board.count(board, "Inbox")
    assert(OKF::Pro::Board.grammar(board).any? { |f| f =~ /example bullet one/ })
  end

  def test_a_balanced_inline_comment_is_stripped_wherever_it_sits
    board = full_board("Inbox" => "- 2026-08-12 — capture <!-- aside --> with a tail\n")

    assert_equal 1, OKF::Pro::Board.count(board, "Inbox")
    assert_empty OKF::Pro::Board.grammar(board)
  end

  def test_content_after_the_closer_is_still_board
    board = "## Inbox\n<!-- docs\n-->  - urgent but hidden from the counters\n"

    refute_empty OKF::Pro::Board.grammar(board)
  end

  def test_two_comments_do_not_fuse_and_swallow_the_board_between_them
    board = "## Inbox\n<!-- one -->\n  - stray between comments\n<!-- two -->\n"

    refute_empty OKF::Pro::Board.grammar(board)
  end

  # ── exact section headings ────────────────────────────────────────────────

  # The same defect shape log.rb paid for: a prefix test folded a decorated
  # heading into the section it prefixes, inflating the count and turning a
  # correct budget header into a refusal.
  def test_a_decorated_heading_is_its_own_section_not_a_prefix_match
    board = <<~MD
      **In flight: 2/5**

      ## In flight
      - one
      - two

      ## In flight — parked
      - three
      - four
    MD

    assert_equal 2, OKF::Pro::Board.count(board, "In flight")
    assert_empty OKF::Pro::Budget.check_text(board)
  end

  # ── the fixpoint, and the splices that broke every richer model ──────────

  # Stripping visible text must change nothing — the counters and the
  # grammar both read "visible", and a strip that shifted under a second
  # pass let them read different boards. The gnarly fixture is a splice
  # that only reaches a fixpoint after two passes of the naive gsub.
  def test_stripping_visible_text_is_a_fixpoint
    gnarly = "## Inbox\nx<!<!-- c -->--y--> z\n<!-- a --><!-- b\n- 2026-08-12 — real\n--> tail\n"
    once = OKF::Pro::Board.visible(gnarly)

    assert_equal once, OKF::Pro::Board.visible(once)
  end

  # The round-12 repros, pinned: a closer spliced against a new opener, and
  # a balanced comment followed by a dangling one — neither may swallow a
  # real line, and both leave the dangling '<!--' confessed.
  def test_a_closer_spliced_to_a_new_opener_swallows_nothing
    board = "## Inbox\n<!-- a\n--><!-- b\n- no date capture\n-->\n- 2026-08-13 second\n"

    findings = OKF::Pro::Board.grammar(board)

    assert_equal 2, OKF::Pro::Board.count(board, "Inbox")
    assert(findings.any? { |f| f =~ /has no '-->'/ }, findings.inspect)
    assert(findings.any? { |f| f =~ /oldest-capture counter cannot see it.*no date capture/ }, findings.inspect)
  end

  def test_a_balanced_comment_before_a_dangling_opener_swallows_nothing
    board = "## Inbox\n<!-- tag --> <!-- note\n- 2026-08-12 real capture\n-->\n"

    assert_equal 1, OKF::Pro::Board.count(board, "Inbox")
    assert(OKF::Pro::Board.grammar(board).any? { |f| f =~ /has no '-->'/ })
  end

  # The round-12 Waiting repro: a chase date inside an intended comment
  # must not feed the past-chase counter in silence — the dangling opener
  # is confessed, and the writer decides.
  def test_a_dangling_opener_hiding_a_chase_date_is_confessed
    board = "## Waiting\n- waiting on Bob <!-- maybe chase 2026-01-01 later\n"

    assert(OKF::Pro::Board.grammar(board).any? { |f| f =~ /has no '-->'/ })
  end

  # ── near-miss headings ────────────────────────────────────────────────────

  # Exact heading matching cuts both ways: "## Deadlines — Q3" was a quiet
  # zero — every counter disengaged, nothing said. A near-miss of a known
  # section is a finding; an unrelated custom heading stays the adopter's
  # business.
  # The invariant is checked directly — "every section exists" — so a
  # decorated or re-spelled replacement of a core heading surfaces as the
  # missing real section, every typo class at once ('## inbox',
  # '## In Flight', '## Deadlines — Q3', '## Deadline' were all quiet
  # zeros under the near-miss heuristic this replaces).
  def test_a_decorated_core_heading_is_confessed_not_a_quiet_zero
    board = full_board.sub("## Deadlines", "## Deadlines — Q3") +
            "- 2026-08-14 — file the insurance claim\n"

    findings = OKF::Pro::Board.grammar(board)

    assert_empty OKF::Pro::Board.section_lines(board, "Deadlines")
    assert(findings.any? { |f| f =~ /has no '## Deadlines' section/ }, findings.inspect)
  end

  def test_a_lowercased_core_heading_is_confessed
    board = full_board.sub("## Inbox", "## inbox")

    assert(OKF::Pro::Board.grammar(board).any? { |f| f =~ /has no '## Inbox' section/ })
  end

  def test_a_truncated_core_heading_is_confessed
    board = full_board.sub("## Deadlines", "## Deadline")

    assert(OKF::Pro::Board.grammar(board).any? { |f| f =~ /has no '## Deadlines' section/ })
  end

  def test_an_unrelated_custom_heading_is_not_flagged
    assert_empty OKF::Pro::Board.grammar(full_board + "\n## Someday\n- 2026-08-12 — maybe\n")
  end

  # The pattern the near-miss heuristic permanently nagged: an intentional
  # sibling BESIDE the real section is the adopter's business.
  def test_a_decorated_sibling_beside_the_real_section_is_fine
    board = full_board("In flight" => "- one\n") + "\n## In flight — parked\n- three\n"

    assert_empty OKF::Pro::Board.grammar(board)
  end

  # A second effective strip pass means fragments spliced into a comment
  # no single reading of the board contains — text was swallowed that the
  # writer never wrapped, and silence there was exactly the claim the old
  # "splicing cannot break this" docstring got wrong.
  def test_a_resplice_is_confessed
    board = full_board("Waiting" => "- waiting on Bob <!<!-- tag -->-- chase 2026-01-01 -->\n")

    _visible, _unclosed, respliced = OKF::Pro::Board.strip_comments(board)

    assert respliced
    assert(OKF::Pro::Board.grammar(board).any? { |f| f =~ /settled after a second pass/ })
  end

  def test_a_single_pass_strip_is_not_a_resplice
    _visible, _unclosed, respliced = OKF::Pro::Board.strip_comments("- x <!-- a --> y\n")

    refute respliced
  end
end
