# frozen_string_literal: true

module OKF
  module Pro
    # log.md as data. Pure, for the same reason Board is.
    module Log
      module_function

      # The shape of the line Rule 2 appends: a list bullet, then the word,
      # then its colon — bolding optional, spacing free. Substring matching
      # ("any line containing Snapshot") was a hole in both directions: a
      # prose bullet like "- Rewrote the Snapshot checker" under today's
      # heading posed as the day's snapshot, so the stop gate skipped its
      # accurate missing-line refusal and reported twelve bogus
      # disagreements instead — and the audit passed CI on a mention with
      # no real snapshot anywhere.
      SNAPSHOT_LINE = /\A[[:blank:]]*[*+-][[:blank:]]+\*{0,2}Snapshot\*{0,2}[[:blank:]]*:/.freeze

      # Under *that* day's heading and no further. The shell version set its flag
      # at the day heading and never cleared it, so yesterday's snapshot
      # satisfied today — which is exactly the check being asked for.
      def snapshot_under?(text, day)
        !snapshot_line(text, day).nil?
      end

      # The one walk over the log's day blocks — every public reader below
      # consumes it, so the heading rule, the calendar rule, and the
      # last-line-wins rule cannot drift apart again (they did, twice: a
      # hand-rolled heading compare beside DAY_HEADING, then a calendar
      # check present in one loop and absent from the other). Yields
      # [day, line] per block in file order: day is the heading's captured,
      # calendar-valid date; line is the LAST snapshot line within that
      # block — a corrected line is appended rather than history rewritten,
      # and the last word is the current one — or nil when the block has
      # none.
      def each_day_block(text)
        day = nil
        line = nil
        text.to_s.each_line do |l|
          if l.start_with?("## ")
            yield [ day, line ] if day
            day = accepted_day(l)
            line = nil
            next
          end
          line = l if day && l.match?(SNAPSHOT_LINE)
        end
        yield [ day, line ] if day
      end

      # The heading acceptance rule, ONCE: the captured date when the line
      # is a calendar-valid day heading, else nil. Both walks — the block
      # iterator above and the audit's partition below — call this, so a
      # tolerance change cannot land in one and leave the other silently
      # disagreeing about which days exist.
      def accepted_day(line)
        match = line.match(DAY_HEADING)
        match && Board.parse_date(match[1]) ? match[1] : nil
      end

      # The day's Snapshot line. The same date can head two blocks — two
      # sessions in one day, or a merge — and every block counts, but the
      # file runs newest-first, so the FIRST block holding a snapshot wins:
      # taking the last block in file order handed the stale bottom copy to
      # the very gate that verifies counters against the board.
      def snapshot_line(text, day)
        each_day_block(text) do |d, line|
          return line if line && d == day.to_s
        end
        nil
      end

      # The full shape, anchored at both ends: unanchored, `## 2026-08-123`
      # captured a valid-looking date out of a typo and adopted the block,
      # while `## 2026-8-12` (missing zero-pad) matched nothing and fell
      # out of BOTH buckets — neither checked nor reported.
      DAY_HEADING = /^## (\d{4}-\d{2}-\d{2})[[:blank:]\r]*$/.freeze

      # What counts as an ATTEMPT at a day heading: `## ` then a digit.
      # "## Notes" is a legal non-day heading; "## 2026-8-12" is a day
      # heading gone wrong, and the difference is what keeps malformed_days
      # from flagging prose while still catching every typo class.
      DAYISH_HEADING = /^## [[:blank:]]*\d/.freeze

      # One scan, one partition: every heading that attempts a date lands in
      # exactly one bucket, so a rule change cannot open a gap where a
      # heading is neither checked nor reported. days() is the calendar's
      # accepted list — a typo'd `## 2026-08-32` string-sorts above every
      # real date, and unvalidated it became the "newest day" the audit
      # interrogated while the genuine newest day carried none.
      def day_partition(text)
        good = []
        bad = []
        text.to_s.each_line do |line|
          next unless line.match?(DAYISH_HEADING)

          day = accepted_day(line)
          if day
            good << day
          else
            bad << line.chomp.rstrip.sub(/\A## /, "")
          end
        end
        [ good, bad ]
      end

      def days(text)
        day_partition(text)[0]
      end

      # The headings days() refused, for the audit to say out loud — a
      # heading no check will ever look under must not rot in silence.
      def malformed_days(text)
        day_partition(text)[1]
      end

      # The maximum date, not the first heading. The file's own convention is
      # newest-first, but prose is the only thing that ever said so — an entry
      # appended at the bottom made the audit interrogate the *oldest* day,
      # which had its snapshot, and CI passed while the real newest day had
      # none. What CI asks about is the newest day rather than today, because
      # a push can land on a day nobody worked and a gate that fails on the
      # calendar is a gate people learn to ignore.
      def newest_day(text)
        days(text).max
      end

      # The most recent snapshot in the file, by date, WITH the day it was found
      # under. The session banner and `okf pro state` both label the parsed
      # counters "as of" that day rather than as live, and a label re-derived
      # by a second scan would be a second chance to disagree with the line it
      # labels. (A line-only sibling stood here until `state` became the one
      # source both surfaces read; it was a two-line delegation to this, and
      # only a unit test still called it.)
      #
      # By DATE, not by position. Grepping the whole file and taking the last
      # hit read the file's *bottom*, which in a newest-first log is the oldest
      # entry: from day two onward the banner reported the first-ever counters,
      # inverting the delta it exists to show.
      #
      # One pass, O(filesize), because this runs at every session start on a
      # file that only grows: the composed version cost a full rescan per
      # candidate day, which was seconds on a years-old log exactly when
      # discipline had lapsed and the banner mattered most. Two scalars, not
      # per-day hashes — the strict greater-than keeps the first block of a
      # repeated day, the newest-first winner, for free, and there is no second
      # copy of the walk left to drift.
      def latest_snapshot_entry(text)
        best_day = nil
        best_line = nil
        each_day_block(text) do |day, line|
          next unless line
          next unless best_day.nil? || day > best_day

          best_day = day
          best_line = line
        end
        [ best_day, best_line ]
      end
    end
  end
end
