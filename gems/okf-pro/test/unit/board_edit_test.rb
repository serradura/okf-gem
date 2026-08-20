# frozen_string_literal: true

require "test_helper"

# The board's text transforms, and the selector.
#
# Pure: text in, text out. Everything here is tested against a string rather
# than a fixture, for the reason `Board` itself is — the counting and editing
# rules are the subject, and a bundle on disk would put a filesystem between the
# test and the rule.
class BoardEditTest < OKF::Pro::TestCase
  Edit = OKF::Pro::Board::Edit

  BOARD = <<~BOARD
    # Board

    **In flight: 1/5** · updated 2026-08-10

    ## In flight
    - [/projects/alpha/](/projects/alpha/index.md) — call the movers

    ## Backlog
    - sort out the storage unit

    ## Waiting

    ## Inbox
    - 2026-08-01 — the invoice from acme

    ## To read

    ## Deadlines
  BOARD

  # ── append ──────────────────────────────────────────────────────────────

  test "an append lands after the section's last line, not at the end of the block" do
    text, error = Edit.append_to_section(BOARD, "Backlog", "- a second thing")

    assert_nil error
    assert_match(/## Backlog\n- sort out the storage unit\n- a second thing\n\n## Waiting/, text)
  end

  test "an append to an empty section lands right under its heading" do
    text, error = Edit.append_to_section(BOARD, "Waiting", "- Landlord: chase 2026-09-01")

    assert_nil error
    assert_match(/## Waiting\n- Landlord: chase 2026-09-01\n/, text)
  end

  # The last section is where a missing final newline would concatenate.
  test "an append to the last section terminates the file" do
    text, = Edit.append_to_section(BOARD.chomp, "Deadlines", "- 2026-09-01 — lease ends")

    assert_equal "- 2026-09-01 — lease ends\n", text.lines.last
  end

  test "a section the board does not have is an error rather than a guess" do
    text, error = Edit.append_to_section(BOARD, "Someday", "- a line")

    assert_nil text
    assert_match(/no '## Someday' section/, error)
  end

  # A comment is board text this must not delete: the transforms walk the RAW
  # text, and stripping comments here would be regeneration by another name.
  test "comments survive an append" do
    with_comment = BOARD.sub("## Backlog\n", "## Backlog\n<!-- a sample line: - do the thing -->\n")

    text, = Edit.append_to_section(with_comment, "Backlog", "- new")

    assert_includes text, "<!-- a sample line: - do the thing -->"
  end

  # ── the budget face ─────────────────────────────────────────────────────

  test "set_declared rewrites only the declared half of the header" do
    text, old, fresh = Edit.set_declared(BOARD, 3)

    assert_equal "**In flight: 1/5** · updated 2026-08-10", old
    assert_equal "**In flight: 3/5** · updated 2026-08-10", fresh
    assert_includes text, "**In flight: 3/5** · updated 2026-08-10"
  end

  test "set_declared to the number already there declares no delta" do
    text, old, fresh = Edit.set_declared(BOARD, 1)

    assert_equal BOARD, text
    assert_nil old
    assert_nil fresh
  end

  # Rule 3's own refusal, not this module's to paper over: a board with no
  # header has no cap, and inventing one is how a budget stops meaning anything.
  test "set_declared on a board with no header returns nothing to write" do
    text, = Edit.set_declared(BOARD.sub(/\*\*In flight.*\n/, ""), 2)

    assert_nil text
  end

  # The header is found per LINE and used to be spliced back per SUBSTRING, so
  # a line further up whose tail equalled the header matched first: the prose
  # was rewritten and the header left stale. `Conserve` caught the mismatch,
  # which made the verb refuse with the wrong line named and the board
  # unpromotable until the prose was edited.
  test "a prose line ending in the header's text is not the one rewritten" do
    text = "# Board\n\nSee **In flight: 1/5** · updated fixture\n\n" \
           "**In flight: 1/5** · updated fixture\n\n## In flight\n- a\n"
    after, old, fresh = OKF::Pro::Board::Edit.set_declared(text, 2)

    assert_includes after, "See **In flight: 1/5** · updated fixture\n"
    assert_includes after, "\n**In flight: 2/5** · updated fixture\n"
    assert_equal "**In flight: 1/5** · updated fixture", old
    assert_equal "**In flight: 2/5** · updated fixture", fresh
  end

  # ── move ────────────────────────────────────────────────────────────────

  test "a move takes the line out of one section and puts it in another" do
    line = "- sort out the storage unit"
    text, error = Edit.move_line(BOARD, line, "In flight")

    assert_nil error
    assert_match(/## Backlog\n\n## Waiting/, text)
    assert_match(/call the movers\n- sort out the storage unit\n/, text)
  end

  test "a move of a line that is not there is an error" do
    text, error = Edit.move_line(BOARD, "- nothing like this", "In flight")

    assert_nil text
    assert_match(/not on the board/, error)
  end

  # ── selectors ───────────────────────────────────────────────────────────

  def rows
    OKF::Pro::Board.rows(BOARD)
  end

  test "a bare slug selects the line linking that project" do
    row, error = Edit.select(rows, "alpha")

    assert_nil error
    assert_equal "In flight", row.section
  end

  test "a full link target selects the same line" do
    row, = Edit.select(rows, "/projects/alpha")

    assert_equal "In flight", row.section
  end

  test "a unique substring selects the line that carries it" do
    row, = Edit.select(rows, "storage")

    assert_equal "Backlog", row.section
  end

  test "sections narrow what a selector may reach" do
    row, error = Edit.select(rows, "alpha", sections: [ "Backlog" ])

    assert_nil row
    assert_match(/no board line under Backlog matches 'alpha'/, error)
  end

  # Positional indexes are what okf-principles forbids, and ambiguity is where
  # a positional answer would silently be given: two lines match, one is picked,
  # the wrong commitment moves and the verb reports success.
  test "an ambiguous substring refuses and names every match" do
    board = BOARD.sub("## Backlog\n", "## Backlog\n- the invoice from beta\n")

    row, error = Edit.select(OKF::Pro::Board.rows(board), "the invoice")

    assert_nil row
    assert_match(/matches 2 board lines/, error)
    assert_match(/\[Backlog\] - the invoice from beta/, error)
    assert_match(/\[Inbox\] - 2026-08-01 — the invoice from acme/, error)
  end

  test "a selector matching nothing says so rather than returning a line" do
    row, error = Edit.select(rows, "nothing at all")

    assert_nil row
    assert_match(/no board line matches 'nothing at all'/, error)
  end

  test "an empty selector matches nothing rather than everything" do
    row, error = Edit.select(rows, "")

    assert_nil row
    assert_match(/no board line matches/, error)
  end

  # The empty-selector guard's own reasoning, reached by another spelling: `/`
  # and `/projects` chomp to a prefix that is a proper ANCESTOR of every linked
  # line, so `start_with?` turns the name into a wildcard. With exactly one
  # linked line in range the verb moved it and reported success.
  test "a selector that names no single target matches nothing" do
    rows = OKF::Pro::Board.rows(<<~BOARD)
      ## Backlog
      - [alpha](/projects/alpha/index.md) — build the thing

      ## In flight
    BOARD

    [ "/", "/projects", "/projects/", " / " ].each do |selector|
      row, error = OKF::Pro::Board::Edit.select(rows, selector, sections: [ "Backlog" ])

      assert_nil row, "#{selector.inspect} selected a commitment it does not name"
      assert_match(/no board line/, error)
    end
  end

  # ── the capture line ────────────────────────────────────────────────────

  test "a capture line carries the leading date the Inbox counter reads" do
    line = Edit.capture_line("  the invoice from acme  ", Date.new(2026, 8, 17))

    assert_equal "- 2026-08-17 — the invoice from acme", line
    assert_equal Date.new(2026, 8, 17), OKF::Pro::Board.line_date(line)
  end
end
