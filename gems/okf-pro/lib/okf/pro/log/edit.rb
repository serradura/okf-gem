# frozen_string_literal: true

module OKF
  module Pro
    module Log
      # log.md's one text transform — a dated line, appended under its day.
      #
      # The counterpart of Board::Edit, and separate from it for the reason
      # `Log` is separate from `Board`: the log's newest-first convention is a
      # rule of this file alone, and it is the rule every earlier defect here
      # turned on — the audit interrogating the oldest day, the banner printing
      # day one's counters forever. A new day's heading therefore goes at the
      # TOP of the day sequence, not at the end of the file.
      #
      # Returns `[text, added]`, where `added` is the exact list of lines
      # spliced in — the caller's claim to `Conserve`, blank lines included,
      # because a blank line is a line and a guard that ignored them could be
      # walked past with one.
      module Edit
        module_function

        def add_entry(text, day, line)
          lines = Pro.newline_terminated(text).lines
          heading = "## #{day}"
          at = lines.index { |l| l.start_with?("## ") && l.chomp.rstrip == heading }
          at ? into_existing_day(lines, at, line) : as_a_new_day(lines, heading, line)
        end

        # After the day's last non-blank line, so the entry joins the day
        # rather than floating below it — and before whatever blank line
        # separates this day from the next.
        def into_existing_day(lines, at, line)
          index = at + 1
          last = at + 1
          while index < lines.size
            break if lines[index].start_with?("## ")

            last = index + 1 unless lines[index].strip.empty?
            index += 1
          end
          added = [ "#{line}\n" ]
          lines.insert(last, *added)
          [ lines.join, added ]
        end

        # Before the first existing day, which in a newest-first log is where
        # a newer day belongs. With no day at all yet, at the end — a brand-new
        # bundle ships an undated log whose whole body is its own preamble.
        def as_a_new_day(lines, heading, line)
          first = lines.index { |l| l.start_with?("## ") }
          if first
            added = [ "#{heading}\n", "\n", "#{line}\n", "\n" ]
            lines.insert(first, *added)
          else
            # The separator counts. It is a line the file did not have, and a
            # guard that let an unstated blank through is a guard an edit can
            # be walked past one blank at a time.
            added = []
            added << "\n" unless lines.empty? || lines.last.strip.empty?
            added.push("#{heading}\n", "\n", "#{line}\n")
            lines.concat(added)
          end
          [ lines.join, added ]
        end
      end
    end
  end
end
