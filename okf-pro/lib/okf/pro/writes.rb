# frozen_string_literal: true

module OKF
  module Pro
    # The mechanical writers — the shapes with exactly one correct form.
    #
    # WHAT THESE ARE FOR. A dated Inbox line, a promotion, the day's journal
    # file, the three mechanical moves of closure: each has one right answer,
    # and each was being reconstructed from prose on every use — a third of a
    # measured session's tool output was the skill's guides, read to learn the
    # grammar of a line. Grammar a Ruby function knows is grammar nobody has to
    # re-read.
    #
    # THE WRITE CONTRACT, and it is the whole design:
    #
    #   Additive and targeted, never regenerative. A write verb may append a
    #   line or edit the line it was given. No verb rewrites a file it did not
    #   fully derive from that file's own prior contents. A writer never
    #   satisfies its own gate.
    #
    # Every method below is the same four steps: read, transform PURELY (in
    # Board::Edit or Log::Edit, which cannot touch the disk), state the delta
    # to `Conserve` and refuse if the actual delta differs, then write. The
    # refusal is exit 2 and nothing lands — fail-closed applied to writes.
    #
    # TWO SAFETY PROPERTIES, held by construction rather than by guarding —
    # necessary, because a verb invoked through Bash is seen by neither
    # `guard-verified` (Edit/Write only) nor `shell-guard` (no mutator pattern
    # in `okf pro capture`):
    #
    #   1. No verb interpolates agent-supplied text into frontmatter, ever.
    #      Agent text reaches a board line body or a journal entry body and
    #      nowhere else — and a newline in it is refused rather than escaped,
    #      because a text that spans lines is a text that can carry a `---`.
    #   2. Selectors are keyed, never positional, and refuse on ambiguity.
    #
    # And one thing they deliberately do NOT do: `snapshot` gains no `--write`.
    # A writer and a checker sharing a code path agree trivially and prove
    # nothing, so the stop gate keeps its independent read.
    module Writes
      # What every verb hands back: whether it may exit 0, and the lines to
      # print. Failures print to stderr and exit 2; the caller does not have to
      # know which message means which.
      Result = Struct.new(:ok, :messages)

      module_function

      def ok(*messages)
        Result.new(true, messages.flatten)
      end

      def refuse(*messages)
        Result.new(false, messages.flatten)
      end

      # ── capture ──────────────────────────────────────────────────────────

      # `BundleRoot.resolve` accepts an index beside EITHER core file, so a
      # bundle can legitimately resolve with no board at all. Every verb below
      # edits one, and "could not run (Errno::ENOENT)" is a true answer to the
      # wrong question.
      def no_board(root, verb)
        refuse("okf pro #{verb} — #{root} has no board.md to edit. `okf pro audit` reports the " \
               "missing core file; this verb will not create one, because a board written by a " \
               "verb is a board nobody decided the shape of.")
      end

      def board?(root)
        File.file?(File.join(root, "board.md"))
      end

      def capture(root, text, today: Date.today)
        return no_board(root, "capture") unless board?(root)

        escape = escaping(root, "capture", "board.md")
        return escape if escape

        body = text.to_s
        return refuse("okf pro capture — takes the words to capture: `okf pro capture \"what you heard\"`.") if body.strip.empty?

        if body.include?("\n")
          return refuse("okf pro capture — the text spans lines, and a capture is one line: the Inbox " \
                        "counter reads a line at a time, and a multi-line write is the one shape that " \
                        "could carry a `---` into a file this verb is not allowed to restructure.")
        end

        board_path = File.join(root, "board.md")
        before = Pro.read_text(board_path)
        line = ::OKF::Pro::Board::Edit.capture_line(body, today)
        after, error = ::OKF::Pro::Board::Edit.append_to_section(before, "Inbox", line)
        return refuse("okf pro capture — #{error}") if error

        commit(board_path, before, after, "capture", added: [ line ]) do
          [ "okf pro capture — one line added to Inbox:", "  #{line}" ]
        end
      end

      # ── promote / demote ─────────────────────────────────────────────────

      PROMOTE_FROM = %w[Inbox Backlog].freeze

      def promote(root, selector)
        return no_board(root, "promote") unless board?(root)

        escape = escaping(root, "promote", "board.md")
        return escape if escape

        board_path = File.join(root, "board.md")
        before = Pro.read_text(board_path)
        row, error = ::OKF::Pro::Board::Edit.select(Board.rows(before), selector, sections: PROMOTE_FROM)
        return refuse("okf pro promote — #{error}") if error

        budget = Board.budget(before)
        return refuse(no_header("promote")) if budget.nil?

        count = Board.count(before, "In flight")
        if count + 1 > budget.cap
          return refuse("okf pro promote — RULE 3: #{count} in flight against a cap of #{budget.cap}, " \
                        "so promoting makes #{count + 1}. Promotion requires demotion (`okf pro demote`), " \
                        "or a visible renegotiation of the cap — which is journal-worthy, and yours to make.")
        end

        move(board_path, before, row, "In flight", count + 1, "promote")
      end

      def demote(root, selector)
        return no_board(root, "demote") unless board?(root)

        escape = escaping(root, "demote", "board.md")
        return escape if escape

        board_path = File.join(root, "board.md")
        before = Pro.read_text(board_path)
        row, error = ::OKF::Pro::Board::Edit.select(Board.rows(before), selector, sections: [ "In flight" ])
        return refuse("okf pro demote — #{error}") if error

        return refuse(no_header("demote")) if Board.budget(before).nil?

        move(board_path, before, row, "Backlog", Board.count(before, "In flight") - 1, "demote")
      end

      # One line between two sections, and the budget face kept truthful in the
      # same write. The face is not decoration: `cap-check` refuses a header
      # that disagrees with the section under it, so a move that left it stale
      # would hand the next edit somebody else's refusal.
      def move(board_path, before, row, to_section, declared, verb)
        moved, error = ::OKF::Pro::Board::Edit.move_line(before, row.text, to_section)
        return refuse("okf pro #{verb} — #{error}") if error

        after, old_header, new_header = ::OKF::Pro::Board::Edit.set_declared(moved, declared)
        return refuse(no_header(verb)) if after.nil?

        commit(board_path, before, after, verb,
          moved: [ row.text ],
          added: [ new_header ].compact,
          removed: [ old_header ].compact) do
          [ "okf pro #{verb} — moved from #{row.section} to #{to_section}:",
            "  #{row.text}",
            new_header ? "  header now reads #{new_header.strip}" : nil,
            *dormancy_note(to_section) ].compact
        end
      end

      def no_header(verb)
        "okf pro #{verb} — board.md has lost its 'In flight: k/CAP' header, which is Rule 3's " \
          "visible budget and this verb's only source for the cap. Restore it first; guessing a " \
          "cap is how a budget stops meaning anything."
      end

      # The judgment half, said out loud rather than done. A promoted demand
      # owes a next action and a journal line; neither is mechanical, and a
      # verb that wrote either would be writing prose.
      def dormancy_note(to_section)
        return [] unless to_section == "In flight"

        [ "  Owed, and yours: a next-action line and a journal entry linking it — a promotion nobody",
          "  journaled is a slot the dormancy question cannot see moving." ]
      end

      # ── journal open ─────────────────────────────────────────────────────

      # The seeded index's own sentence. Removed only when it is still exactly
      # that — an adopter who reworded it owns their words, and a verb that
      # pattern-matched near-misses would be editing prose it did not write.
      EMPTY_JOURNAL_NOTE = "Nothing recorded yet. The first entry is the first day this bundle is used,\n" \
                           "dated by you, not by the template.\n"

      # `no_board`'s policy, for the other seeded file a verb edits. An index
      # rebuilt from the one line this verb knows how to write comes back
      # holding only that line — the `# Journal` heading and the seeded prose
      # gone — which is regeneration wearing an append's clothes, and the shape
      # constraint 8 forbids outright.
      def no_index(root)
        refuse("okf pro journal open — #{root}/journal/index.md does not exist, and this verb " \
               "adds a line to that index rather than writing one: an index rebuilt from the " \
               "single line it knows would lose the heading and the prose around it. Restore it " \
               "first — a `# Journal` heading is all this verb needs — because every day already " \
               "written is an orphan until it is back, which is what `okf pro audit` reports.")
      end

      def journal_open(root, today: Date.today)
        day = today.to_s
        entry_path = File.join(root, "journal", "#{day}.md")
        index_path = File.join(root, "journal", "index.md")
        return refuse("okf pro journal open — #{root}/journal/ does not exist.") unless File.directory?(File.dirname(entry_path))
        return no_index(root) unless File.file?(index_path)

        escape = escaping(root, "journal open", "journal/index.md", "journal/#{day}.md")
        return escape if escape

        before = Pro.read_text(index_path)
        indexed = before.include?("(#{day}.md)")
        exists = File.exist?(entry_path)

        if exists && indexed
          return ok("okf pro journal open — journal/#{day}.md is already open. Write the day into it " \
                    "with Edit; this verb only creates the file and its index line.")
        end

        unless indexed
          after, added, removed = journal_index(before, day)
          findings = Conserve.check(before, after, added: added, removed: removed)
          return refuse(conservation_refusal("journal open", index_path, findings)) unless findings.empty?
        end

        # A file that did not exist has nothing to conserve — the guard
        # compares a delta against a prior text, and there is none. The
        # conservation that matters here is the INDEX's, which did exist.
        #
        # Two writes, and atomicity stated honestly, exactly as `Scaffold` does:
        # each file is written atomically and the PAIR is not. The residue of a
        # half-done pair is a day with no index line, which is why the two
        # conditions above are asked SEPARATELY rather than off `File.exist?`
        # alone: re-running the verb finishes the half that did not land, and
        # a fixed-up state repairs itself instead of needing a maintainer.
        Scaffold.write_atomically(entry_path, journal_entry(day), false) unless exists
        Scaffold.write_atomically(index_path, after, false) unless indexed
        ok("okf pro journal open — journal/#{day}.md #{exists ? "was already there and is now" : "created and"} indexed.",
          "  The day itself is yours to write: what happened, what it meant, what was decided.")
      end

      # The delta is declared NET, because that is the only delta `Conserve`
      # can see: it compares line multisets, so a blank line removed and then
      # added back is invisible to it and undeclarable. Hence no tidying pass —
      # the note comes out, the entry goes on the end, and a separator is added
      # only where there is not one already.
      def journal_index(before, day)
        lines = Pro.newline_terminated(before).lines
        note = EMPTY_JOURNAL_NOTE.lines
        at = sublist_index(lines, note)
        removed = at ? lines.slice!(at, note.size) : []

        entry = "* [#{day}](#{day}.md) - the day's record.\n"
        added = []
        added << "\n" unless lines.empty? || lines.last.strip.empty? || lines.last.start_with?("*")
        added << entry
        lines.concat(added)
        [ lines.join, added, removed ]
      end

      def sublist_index(lines, sub)
        return nil if sub.empty?

        (0..(lines.size - sub.size)).find { |i| lines[i, sub.size] == sub }
      end

      def journal_entry(day)
        <<~ENTRY
          ---
          type: Journal Entry
          title: "#{day}"
          description: What happened on #{day}, what it meant, and what was decided.
          ---

          # #{day}

          <!-- What happened, what it meant, what was decided. Delete this line. -->
        ENTRY
      end

      # ── close ────────────────────────────────────────────────────────────

      # WHAT IT WRITES IS DECIDED BEFORE ANYTHING IS WRITTEN.
      #
      # Three files change, and `Scaffold.write_atomically` makes each write
      # atomic and the SET not. So the ordering is the safety: every check runs
      # and every new text is computed — purely, in `Board::Edit` and
      # `Log::Edit`, which cannot touch the disk — and only then does anything
      # land. Checking as it went left a real half-closed bundle: a board that
      # had lost its budget header refused at step two with the index already
      # marked, so the project read as closed while its board line survived and
      # no log entry existed, and the message said nothing had happened.
      #
      # The residue of a crash mid-sequence is still real and still visible —
      # `okf pro audit` reports the pairing failure — but a REFUSAL now writes
      # nothing at all, which is what the message claims.
      Plan = Struct.new(:path, :text)

      def close(root, project, today: Date.today)
        return no_board(root, "close") unless board?(root)

        # The three spellings `Board::Edit.by_target` treats as one commitment
        # are one commitment here too — `alpha`, `/projects/alpha/`, and the
        # `/projects/alpha/index.md` a board line actually carries, which is
        # what `okf pro board` prints. A verb that refuses the string it just
        # showed you is a verb you stop trusting.
        #
        # Dropping the index filename is not the normalisation the check below
        # forbids: that one is about a path that LEAVES `projects/`, and this
        # runs before it, so `/projects/../../etc/index.md` still arrives at
        # `../../etc` and is still refused.
        slug = project.to_s.sub(%r{\A/?projects/}, "").chomp("/").sub(%r{/index\.md\z}, "")

        # One directory name, and nothing that can leave `projects/`. This verb
        # marks a file's first line and removes board lines, and `File.join`
        # resolves `..` happily — `okf pro close ../../somewhere` would put a
        # closure marker on a stranger's index. A project is one segment by the
        # structure's own rule (`projects/<slug>/`), so anything else is a
        # refusal rather than a normalisation: quietly rewriting a path the
        # caller gave is how a traversal becomes an edit nobody sees.
        unless slug.match?(%r{\A[^/\\]+\z}) && ![ ".", ".." ].include?(slug)
          return refuse("okf pro close — '#{project}' is not a project name. A project is one " \
                        "directory under projects/, so its name carries no slash and is not a " \
                        "relative path. `okf pro state` lists the open ones.")
        end

        dir = File.join(root, "projects", slug)
        return refuse("okf pro close — #{root}/projects/#{slug}/ does not exist. `okf pro state` lists the open projects.") unless File.directory?(dir)

        index_path = File.join(dir, "index.md")
        return refuse("okf pro close — projects/#{slug}/index.md does not exist, and closure is a marker on its first line.") unless File.file?(index_path)

        escape = escaping(root, "close", "projects/#{slug}/index.md", "board.md", "log.md")
        return escape if escape

        board_path = File.join(root, "board.md")
        log_path = File.join(root, "log.md")
        already = Pairing.closed?(root, index_path)
        lines = Board.rows(Pro.read_text(board_path)).select { |row| ::OKF::Pro::Board::Edit.by_target([ row ], slug).any? }

        return ok("okf pro close — projects/#{slug} is already closed and carries no board line. Nothing to do.") if already && lines.empty?

        plans = []
        unless already
          plan, refusal = plan_marker(index_path, slug, today)
          return refusal if refusal

          plans << plan
        end

        board_plan, refusal = plan_board(board_path, lines)
        return refusal if refusal

        plans << board_plan if board_plan

        log_plan, refusal = plan_log(log_path, slug, lines.size, today)
        return refusal if refusal

        plans << log_plan
        plans.each { |plan| Scaffold.write_atomically(plan.path, plan.text, false) }

        ok([ "okf pro close — projects/#{slug}:",
             already ? "  index.md already carried the closure marker" : "  index.md marked closed #{today}",
             "  #{lines.size} board line(s) removed",
             "  log.md entry added under #{today}",
             *snapshot_owed(log_path, today),
             "Owed, and yours: the durable part of this work belongs in learnings/ or glossary/ —",
             "extract it now, or it is archived with the project and relearned later at full price." ])
      end

      # Said here because this verb is what creates the obligation. Writing a
      # log entry gives the day a `## <date>` heading, and from that moment the
      # audit — which the pre-commit door runs — asks that day for its Snapshot
      # line. A verb that quietly turned the next commit into a refusal without
      # naming the fix would be teaching its user that the gates are arbitrary.
      def snapshot_owed(log_path, today)
        return [] unless File.exist?(log_path)
        return [] if Log.snapshot_line(Pro.read_text(log_path), today.to_s)

        [ "  #{today} now has a log heading and owes its Snapshot line — the audit the pre-commit",
          "  door runs asks the newest day for one. `okf pro snapshot` computes it." ]
      end

      # THE DECISION THE CHECKER ALREADY MAKES, MADE AGAIN AT THE WRITE DOOR.
      #
      # `Pairing.closed?` reads this same index through `Pro.read_contained` and
      # answers "open" when the link leaves the bundle. Nothing carried that
      # answer across to the writer, which read and rewrote the path with the
      # uncontained pair — so `okf pro close escapee` marked a stranger's
      # `index.md`, exited 0, and left `okf pro audit` still reporting the
      # project as neither on the board nor closed. Run twice it appended a
      # second marker, so it was unbounded as well as wrong.
      #
      # `.okf/contract/containment-directions.md` is the rule and it decides
      # this direction too: pick the one that leaves the demand visible. A
      # refusal keeps the board line and keeps the project being asked about;
      # a marker written outside the bundle is a stranger's file edited to
      # satisfy a checker that will not read it back.
      #
      # Asked of the INDEX, not of the directory holding it, because containing
      # the directory does not contain the file: an `index.md` symlinked out of
      # a perfectly contained `projects/<slug>/` is read by `Pro.read_text`
      # (which follows the link) and written back by `File.rename` (which does
      # not), so the marker came from a stranger's title and landed as a real
      # file inside the bundle. Containing the leaf contains both, because a
      # directory that escapes takes every path under it with it.
      #
      # Unrescued, deliberately. `File.file?` above has already resolved the
      # whole path, so a `SystemCallError` here is the ground moving under the
      # check — and `write_verb` runs every writer inside `guarded`, which
      # answers exactly that with exit 2 and "nothing was read or written". A
      # rescue returning false would say the same thing in a message about
      # symlinks, and would be a branch no fixture can reach.
      def contained?(root, path)
        ::OKF::Path.under?(File.realpath(root), File.realpath(path))
      end

      # EVERY file a verb reads and rewrites, not just the one that was found
      # first. Containing `projects/<slug>/index.md` and leaving `board.md`,
      # `log.md` and `journal/index.md` open left the identical hazard three
      # files over: `okf pro capture` read a stranger's board through the link,
      # appended, and renamed a temp over it — so the link became a real file
      # inside the bundle carrying content the bundle never owned.
      #
      # Checked before anything is read, and only for a file that exists: a
      # missing one is each verb's own refusal to make, with its own message.
      def escaping(root, verb, *rels)
        rels.each do |rel|
          path = File.join(root, rel)
          next unless File.exist?(path)
          next if contained?(root, path)

          return escape_refusal(verb, root, rel)
        end
        nil
      end

      def escape_refusal(verb, root, rel)
        refuse("okf pro #{verb} — #{rel} resolves outside #{root}, so this verb will not write " \
               "there. `Pro.read_text` follows a symlink and the atomic rename does not, so the " \
               "read would come from a file this bundle does not own and the write would replace " \
               "the link with it. Every gate reads this path contained (`Pairing.closed?` answers " \
               "\"open\" rather than read one), and a writer that did not would be the loosest " \
               "door on the strictest file. Edit it by hand if the link is deliberate.")
      end

      # A markdown heading, and nothing else. The marker goes on the TITLE —
      # that is the spelling the skill teaches and the only place `closed?`
      # looks, since it reads three lines from the top.
      #
      # The check is the shape of the line, not merely whether the result
      # satisfies `Pairing::MARKER`, and that distinction is the finding: an
      # index carrying YAML frontmatter starts with `---`, and
      # `Pairing.marker?("--- — closed 2026-08-17")` is TRUE — the regex needs
      # only the word and a date. So the satisfied-marker check passed, the
      # fence was destroyed, and the concept silently lost its `type`, `title`
      # and `description` while `okf validate` still exited 0. `Conserve`
      # cannot see it either: the mangling was the declared edit.
      HEADING = /\A\#{1,6}[[:blank:]]+\S/.freeze

      def plan_marker(index_path, slug, today)
        before = Pro.read_text(index_path)
        first = before.lines.first
        return [ nil, refuse("okf pro close — projects/#{slug}/index.md is empty; there is no first line to mark.") ] if first.nil?

        unless first.match?(HEADING)
          return [ nil, refuse("okf pro close — projects/#{slug}/index.md does not open with a heading " \
                               "(#{first.strip.inspect}). Closure marks the title, and this verb will not " \
                               "restructure a file to find one: an index carrying YAML frontmatter opens " \
                               "with `---`, and a marker appended there would destroy the fence while " \
                               "still reading as closed. Give it a `# Title` first line, or mark it by hand.") ]
        end

        marked = closure_marker(first, today)
        unless Pairing.marker?(marked)
          return [ nil, refuse("okf pro close — marking projects/#{slug}/index.md would not produce a closure " \
                               "marker the checker accepts (`#{marked}`). Fix its first line first.") ]
        end

        # Block form: a title carrying `\1` or `\0` would otherwise be read as a
        # backreference by the replacement string and splice the match back in.
        after = before.sub(first) { "#{marked}\n" }
        plan(index_path, before, after, "close", added: [ marked ], removed: [ first.chomp ])
      end

      # The one place this gem WRITES the closure marker, and it is separate so
      # the grammar can be pinned in all three directions at once: what the
      # skill teaches, what `Pairing::MARKER` accepts, and what this emits. Two
      # of those were already pinned to each other; a writer that emitted a
      # fourth spelling would leave a project the checker still reads as open,
      # with a sentence about closure in it.
      def closure_marker(first_line, today)
        "#{first_line.to_s.chomp.rstrip} — closed #{today}"
      end

      def plan_board(board_path, rows)
        return [ nil, nil ] if rows.empty?

        before = Pro.read_text(board_path)
        after = before
        rows.each { |row| after = ::OKF::Pro::Board::Edit.remove_line(after, row.text)[0] }

        # The face follows the section, and ONLY when the section moved. A
        # header that was already lying about a count this verb did not change
        # is Rule 3's finding to raise, not this verb's to quietly correct —
        # a writer that tidies what it was not asked about is regenerating.
        added = []
        removed = rows.map(&:text)
        if rows.any? { |row| row.section == "In flight" }
          after, old_header, new_header = ::OKF::Pro::Board::Edit.set_declared(after, Board.count(after, "In flight"))
          return [ nil, refuse(no_header("close")) ] if after.nil?

          if new_header
            added << new_header
            removed << old_header
          end
        end
        plan(board_path, before, after, "close", removed: removed, added: added)
      end

      def plan_log(log_path, slug, removed, today)
        before = File.exist?(log_path) ? Pro.read_text(log_path) : ""
        line = "* Closed [/projects/#{slug}/](/projects/#{slug}/index.md) — #{removed} board line(s) removed."
        after, added = ::OKF::Pro::Log::Edit.add_entry(before, today, line)
        plan(log_path, before, after, "close", added: added)
      end

      # ── the one write ────────────────────────────────────────────────────

      # Guard, then write, in that order and nowhere else. Every verb above
      # funnels through here, so "refuses rather than writing" is a property of
      # one method rather than a habit five of them share.
      def commit(path, before, after, verb, added: [], removed: [], moved: [])
        planned, refusal = plan(path, before, after, verb, added: added, removed: removed, moved: moved)
        return refusal if refusal

        Scaffold.write_atomically(planned.path, planned.text, false)
        ok(yield)
      end

      # The guard, without the write — for a verb that changes more than one
      # file and must decide about all of them before it changes any.
      # Returns `[Plan, nil]` or `[nil, Result]`.
      def plan(path, before, after, verb, added: [], removed: [], moved: [])
        findings = Conserve.check(before, after, added: added, removed: removed, moved: moved)
        return [ nil, refuse(conservation_refusal(verb, path, findings)) ] unless findings.empty?

        [ Plan.new(path, after), nil ]
      end

      def conservation_refusal(verb, path, findings)
        [ "okf pro #{verb} — refused, and #{path} is untouched. The edit this verb computed does not " \
          "match the change it declared, which is the one failure a mechanical writer must not " \
          "commit: a view rewritten with a line quietly gone is failure mode 07, and this check is " \
          "why this verb cannot be it.",
          *findings.map { |f| "  #{f}" } ]
      end
    end
  end
end
