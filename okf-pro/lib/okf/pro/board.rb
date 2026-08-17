# frozen_string_literal: true

module OKF
  module Pro
    # board.md as data. Pure text in, numbers out — no disk, no bundle, so the
    # counting rules that Rule 3 enforces can be tested without a fixture.
    module Board
      Budget = Struct.new(:declared, :cap)

      # Comments, as the BOARD defines them — one line, balanced:
      # `<!-- ... -->` is stripped wherever it sits, and a longer note is a
      # stack of single-line comments. Every richer model failed open in a
      # review round: character-granular regions let a `<!--` in one
      # capture's prose swallow real lines up to a `-->` in another's; and
      # line-start regions were position-dependent, so splicing the text
      # after a closer changed what a second strip saw and the counters
      # read a different board than the grammar. Balanced-on-one-line is
      # the shape that survives ALMOST any splice — nested fragments can
      # still juxtapose into a span no single reading of the source
      # contains, which is why strip_comments runs to a fixpoint and
      # confesses when it needed more than one pass. The rule is narrow
      # enough to be predictable, not narrow enough to be inviolable, and
      # the difference is a finding rather than a comment's promise.
      INLINE_COMMENT = /<!--.*?-->/.freeze

      module_function

      # Board text with comments removed — THE definition of "visible", and
      # every reader consumes it: the counters, the budget face, the date
      # checks, the stray-bullet pass, pairing's link scan. Comment-awareness
      # bolted onto one pass split the module against itself: a commented
      # sample line was invisible to the stray check but counted by the cap
      # and flagged by the date check that read it anyway.
      #
      # The strip runs to a FIXPOINT, so re-stripping visible text is a
      # no-op by construction rather than by hope — pathological splices
      # can juxtapose fragments into a new balanced span, and a strip that
      # stopped after one pass let the second reader see a different board.
      # Returns [visible, unclosed?, respliced?]: any `<!--` still standing has no
      # closer on its line — an intended comment gone wrong, and it is NOT
      # hidden. The caller confesses it, because comment-intended text read
      # as board content (a stray chase date, a sample capture) must not
      # drive counters in silence.
      def strip_comments(text)
        visible = text.to_s
        passes = 0
        loop do
          stripped = visible.gsub(INLINE_COMMENT, "")
          break if stripped == visible

          visible = stripped
          passes += 1
        end
        # A second effective pass means the first strip spliced fragments
        # into a comment no single reading of the source contains — text
        # was swallowed that the writer never wrapped. Rare and contrived,
        # but silent was exactly how the docstring's old "splicing cannot
        # break this" claim failed, so convergence beyond one pass is a
        # confession, not a curiosity.
        [ visible, visible.include?("<!--"), passes > 1 ]
      end

      def visible(text)
        strip_comments(text)[0]
      end

      # Lines under a `## <name>` heading, up to the next `## `. The board's
      # sections are the unit Rule 3 counts, so one reader serves the cap check
      # and the session banner alike.
      def section_lines(text, name)
        visible_section_lines(visible(text), name)
      end

      # The section walk over text a caller already made visible — grammar()
      # strips once and shares; the public section_lines strips for everyone
      # else, and the fixpoint strip makes the double path harmless.
      def visible_section_lines(visible_text, name)
        heading = "## #{name}"
        inside = false
        visible_text.each_line.with_object([]) do |line, acc|
          if line.start_with?("## ")
            # Exact, not a prefix — the same defect log.rb already paid
            # for: start_with? folded "## In flight — parked" into
            # "In flight", inflating the count and turning a correct
            # budget header into a refusal.
            inside = (line.chomp.rstrip == heading)
            next
          end
          acc << line if inside && line.start_with?("- ")
        end
      end

      def count(text, name)
        section_lines(text, name).size
      end

      # One row per visible board line, in file order, with everything a
      # reader would otherwise re-derive by hand: which section it sits under,
      # the two date shapes the counters read, and its bundle links.
      #
      # Section is carried on the row rather than looked up per line, because
      # "which section is this line in" is the question every board edit asks
      # first and the one an agent answers today by counting headings in a
      # `cat`. Pure, like everything else here — the age in days is the
      # caller's, since it needs a calendar and this module has none.
      Row = Struct.new(:section, :text, :line_date, :chase_date, :targets)

      def rows(text)
        section = nil
        visible(text).each_line.with_object([]) do |line, acc|
          if line.start_with?("## ")
            section = line.chomp.rstrip.sub(/\A## /, "")
            next
          end
          next unless section && line.start_with?("- ")

          stripped = line.chomp
          acc << Row.new(section, stripped, line_date(stripped), chase_date(stripped), targets(stripped))
        end
      end

      # The `In flight: k/CAP` header, or nil when the board has lost it. Matched
      # by its shape rather than by the first line containing the words, so a
      # sentence mentioning "in flight" elsewhere cannot be mistaken for the
      # budget face. The whole shape must sit on one line that IS the header:
      # anchored at line start (a capture line's "- deck in flight: 3/4" is
      # not the budget), digits and slash on that same line (`\D*` crawled
      # across newlines and fabricated a cap from the next N/M below; `\s*`
      # around the slash did the same one token later, reading a date on the
      # following line as a cap of 2026).
      def budget(text)
        match = visible(text).match(%r{^\*{0,2}[Ii]n [Ff]light:\*{0,2}[^\S\n]*(\d+)[^\S\n]*/[^\S\n]*(\d+)})
        return nil unless match

        Budget.new(match[1].to_i, match[2].to_i)
      end

      # Every bundle-absolute link target on a line. Two spellings, both real:
      # the markdown form `[text](/path)` project lines use, and the bare
      # `[/path]` form capture and conflict lines use — five-second capture
      # does not stop to type a link twice. Anything not starting with `/` is
      # not a bundle link and is not this module's business.
      def targets(line)
        text = line.to_s
        markdown = text.scan(%r{\]\((/[^)\s]+)\)}).flatten
        bare = text.scan(%r{\[(/[^\]\s]+)\](?!\()}).flatten
        # Fragments are for readers; the file they resolve against has none.
        # Kept, `/reference/x.md#tiers` failed the existence check against an
        # entry list that only ever holds `/reference/x.md`.
        (markdown + bare).map { |t| t.sub(/#.*/, "") }
      end

      # The leading `- YYYY-MM-DD` date a capture line carries, or nil. A date
      # the calendar rejects (month 13) is treated as absent rather than
      # guessed at — these feed counters, and a counter must not invent.
      def line_date(line)
        match = line.to_s.match(/\A-\s+(\d{4}-\d{2}-\d{2})/)
        return nil unless match

        parse_date(match[1])
      end

      # The `chase YYYY-MM-DD` date on a Waiting line, or nil. The chase date
      # is the only thing standing between a dependency and a month of drift,
      # which is why the snapshot counts the ones already past. The word is
      # boundary-anchored: without it, "purchase 2026-09-01" read as a chase
      # date, satisfied the grammar check built to demand one, and reported
      # an overdue chase nobody ever set.
      def chase_date(line)
        match = line.to_s.match(/\bchase\s+(\d{4}-\d{2}-\d{2})/)
        return nil unless match

        parse_date(match[1])
      end

      def parse_date(text)
        Date.parse(text)
      rescue ArgumentError
        nil
      end

      # A board line the counters can see starts `- ` at column zero —
      # section_lines reads exactly that, everywhere. Any other bullet is a
      # line every counter is blind to, including the cap: `* 2026-08-18 —
      # file the claim` under Deadlines counted as zero lines, and so did an
      # in-flight demand behind an indented dash. The counters' own bullet
      # rule, flagged instead of silently skipped.
      STRAY_BULLET = /\A(?:[*+][[:blank:]]|[[:blank:]]+[-*+][[:blank:]])/.freeze

      # The counters read three shapes, exactly — a leading `- YYYY-MM-DD` on
      # Inbox and Deadlines lines, a literal `chase YYYY-MM-DD` on Waiting
      # lines — and a dated line in any other spelling parses to nil and is
      # silently compacted out of every count. Silent is the problem:
      # "- Due Aug 18: filing" made "deadlines within 7d" say 0, the stop
      # gate agreed with itself, and the deadline landed unclaimed. So the
      # unreadable line is a finding, raised at the audit and the stop gate,
      # instead of a zero nobody can distinguish from a quiet board. The
      # same goes for the bullet itself: a check that only read the lines
      # the counters read would have inherited their blindness, so the
      # stray-bullet pass walks the raw section text instead.
      def grammar(text)
        visible_text, unclosed, respliced = strip_comments(text)
        findings = []
        if unclosed
          findings << "a '<!--' has no '-->' on its own line. Nothing is hidden — only a " \
                      "balanced single-line comment is a comment — but finish it or remove it: " \
                      "comment-intended text is being read as board content. For longer notes, " \
                      "stack single-line comments."
        end
        if respliced
          findings << "comment stripping only settled after a second pass — fragments spliced " \
                      "into a comment no single reading of the board contains, and text may " \
                      "have been swallowed with them. Rewrite the line without nested '<!--' " \
                      "fragments."
        end
        findings.concat(missing_sections(visible_text))
        findings.concat(stray_bullets(visible_text))
        findings.concat(date_findings(visible_text))
        findings
      end

      # The six sections the counters read, exactly as the skill names them.
      SECTIONS = [ "In flight", "Backlog", "Waiting", "Inbox", "To read", "Deadlines" ].freeze

      # The section invariant, checked directly: each of the six canonical
      # sections is present as an EXACT heading. A near-miss heuristic at
      # this spot was at the wrong depth — it missed the commonest
      # quiet-zero typos ('## inbox', '## In Flight', '##  Inbox' all
      # disengaged every counter in silence) while permanently nagging the
      # legitimate sibling pattern ('## In flight — parked' beside the
      # real section). The claim was never "no heading resembles a
      # section"; it is "every section exists", and checking that subsumes
      # every typo, decoration, and deletion class at once.
      def missing_sections(visible_text)
        present = visible_text.each_line.map do |line|
          line.chomp.rstrip.sub(/\A## /, "") if line.start_with?("## ")
        end.compact
        (SECTIONS - present).map do |name|
          "board has no '## #{name}' section — the counters match that heading exactly, so " \
            "its class of lines has nowhere to land. Restore it; a re-spelled or decorated " \
            "variant does not count."
        end
      end

      # The three date shapes, checked over text the caller already made
      # visible — grammar() strips once and every pass here reads that one
      # strip, through visible_section_lines.
      def date_findings(visible_text)
        findings = []
        visible_section_lines(visible_text, "Inbox").each do |line|
          next if line_date(line)

          findings << "Inbox line carries no leading '- YYYY-MM-DD' date, so the oldest-capture " \
                      "counter cannot see it: #{line.strip}"
        end
        visible_section_lines(visible_text, "Deadlines").each do |line|
          next if line_date(line)

          findings << "Deadlines line carries no leading '- YYYY-MM-DD' date, so the 7-day " \
                      "warning cannot see it: #{line.strip}"
        end
        visible_section_lines(visible_text, "Waiting").each do |line|
          next if chase_date(line)

          findings << "Waiting line carries no 'chase YYYY-MM-DD' date, so the past-chase " \
                      "counter cannot see it: #{line.strip}"
        end
        findings
      end

      # `past_first_heading` is exactly what it says: the pass covers the
      # whole board body from the first section on — the sections' order is
      # the board's own, and a stray bullet between two sections is as
      # invisible to the counters as one inside them. Callers hand this the
      # board's VISIBLE text; grammar() strips comments once for the whole
      # pass, because a bulleted example inside documentation is not a
      # board line, and flagging one turned a comment into a refusal at
      # every Stop until the documentation was deleted.
      def stray_bullets(text)
        past_first_heading = false
        text.to_s.each_line.with_object([]) do |line, acc|
          past_first_heading = true if line.start_with?("## ")
          next unless past_first_heading && line.match?(STRAY_BULLET)

          acc << "board line does not start with '- ' at column zero, so no counter " \
                 "can see it: #{line.strip}"
        end
      end
    end
  end
end
