# frozen_string_literal: true

module OKF
  module Pro
    module Board
      # The board's text transforms — text in, text out, and nothing else.
      #
      # Every write verb's whole computation lives here, so that the shell
      # around it is a read, a conservation check and a rename. That split is
      # what makes `Conserve` worth having: a transform that also wrote its own
      # result could satisfy its own guard, and a writer that satisfies its own
      # gate proves nothing.
      #
      # The transforms return `[text, delta]`, where delta is the claim the
      # caller hands to `Conserve` — never a promise this module keeps by
      # being careful.
      module Edit
        # The budget face, as one line, with the declared count isolated. The
        # anchoring is `Board.budget`'s, deliberately: a header this cannot
        # rewrite is a header that one cannot read, and the two disagreeing is
        # how a promotion leaves the face lying about the section under it.
        BUDGET_LINE = %r{^(\*{0,2}[Ii]n [Ff]light:\*{0,2}[^\S\n]*)(\d+)([^\S\n]*/)}.freeze

        module_function

        # A dated capture line, in the one shape the Inbox counter reads.
        def capture_line(text, today)
          "- #{today} — #{text.to_s.strip}"
        end

        # Appended after the section's LAST `- ` line, or immediately after the
        # heading when the section is empty. Not at the end of the block: a
        # section can carry prose or a stack of comments below its lines, and
        # an append that landed under those would read as belonging to them.
        #
        # Walks the RAW text, not the visible text — a comment stripped here
        # would be a comment deleted, which is the regeneration this whole
        # module exists to make impossible. The two agree on what a heading and
        # a board line are, because a balanced single-line comment starts with
        # `<`, and so does neither.
        def append_to_section(text, section, line)
          lines = Pro.newline_terminated(text).lines
          at = insert_point(lines, section)
          return [ nil, "board has no '## #{section}' section to append to" ] if at.nil?

          lines.insert(at, "#{line}\n")
          [ lines.join, nil ]
        end

        def insert_point(lines, section)
          heading = "## #{section}"
          start = lines.index { |l| l.start_with?("## ") && l.chomp.rstrip == heading }
          return nil if start.nil?

          at = start + 1
          last = at
          index = at
          while index < lines.size
            break if lines[index].start_with?("## ")

            last = index + 1 if lines[index].start_with?("- ")
            index += 1
          end
          last
        end

        # The line, gone, and nothing else. Matched by exact content so a
        # near-duplicate elsewhere on the board survives; every occurrence is
        # removed, because a board carrying the same line twice is carrying one
        # commitment twice and the caller's delta says how many.
        def remove_line(text, line)
          wanted = line.to_s.chomp
          body = Pro.newline_terminated(text)
          kept = body.lines.reject { |l| l.chomp == wanted }
          [ kept.join, body.lines.size - kept.size ]
        end

        # Out of one section and into another, as one transform, so the
        # intended delta is a MOVE and the guard can hold it to that. Doing it
        # as a remove and an append would state two deltas that a dropped line
        # satisfies just as well.
        def move_line(text, line, to_section)
          removed, count = remove_line(text, line)
          return [ nil, no_such_line ] if count.zero?

          append_to_section(removed, to_section, line.to_s.chomp)
        end

        # The one way a line `okf pro board` just listed can fail to match: the
        # selectors read the board's VISIBLE text and this walks the raw text,
        # so a line carrying a trailing `<!-- ... -->` is listed without its
        # comment and looked up with it still there. Refusing is the right
        # answer — moving the visible half would drop the comment, and dropping
        # anything is what `Conserve` exists to prevent — but a message saying
        # only "not on the board" sends the reader looking for the wrong thing.
        def no_such_line
          "that exact line is not on the board. If it carries a trailing " \
            "`<!-- ... -->` comment, `okf pro board` lists it without the comment and this " \
            "verb will not move it: take the comment off the line first, or move it by hand."
        end

        # The declared half of `In flight: k/CAP`. Returns the new text and the
        # two lines the caller must declare, or nil when the board has lost its
        # header — which is Rule 3's own refusal and not this module's to fix.
        def set_declared(text, count)
          lines = Pro.newline_terminated(text).lines
          at = lines.index { |l| l.match?(BUDGET_LINE) }
          return [ nil, nil, nil ] if at.nil?

          old = lines[at]
          # Block form: a header carrying `\\1` in its trailing prose would
          # otherwise be read as a backreference by the replacement string.
          fresh = old.sub(BUDGET_LINE) { "#{Regexp.last_match(1)}#{count}#{Regexp.last_match(3)}" }
          return [ lines.join, nil, nil ] if fresh == old

          # Spliced by INDEX. The header is found per line, and putting it back
          # with `String#sub` searched the whole text for that line's characters
          # — so any earlier line whose tail happened to equal the header
          # matched first, and the prose was rewritten while the header stayed
          # stale. `Conserve` caught the mismatch, which made the verb refuse
          # while naming a line nobody had touched.
          lines[at] = fresh
          [ lines.join, old.chomp, fresh.chomp ]
        end

        # ── selectors ────────────────────────────────────────────────────────
        #
        # Keyed, never positional. okf-principles forbids a positional index
        # for exactly the reason this file exists: agents rewrite, and "the
        # third line under Backlog" names a different commitment after any edit
        # anyone makes. A `/projects/<slug>` link is the board's own key; a
        # substring is the fallback, and both REFUSE on ambiguity rather than
        # picking — a verb that guesses which commitment you meant is a verb
        # that moves the wrong one and reports success.
        # Selectors that identify no single target. An empty one was refused
        # from the start, because the target pass builds the prefix
        # `/projects` out of it and selects every project line on the board —
        # a selector that names nothing selecting everything, in a verb that
        # then moves it.
        #
        # `/` and `/projects` are that same hazard reached by another spelling,
        # and the guard missed them: both chomp to a prefix that is a proper
        # ANCESTOR of every linked line, so `start_with?` turns the name into a
        # wildcard. `select` only refuses on MORE than one match, so with
        # exactly one linked line in range the verb moved it and reported
        # success. A directory every project sits under names none of them.
        NAMES_NOTHING = [ "", "/projects" ].freeze

        def names_nothing?(selector)
          NAMES_NOTHING.include?(selector.to_s.strip.chomp("/"))
        end

        def select(rows, selector, sections: nil)
          return [ nil, no_match(selector, sections) ] if names_nothing?(selector)

          candidates = sections ? rows.select { |r| sections.include?(r.section) } : rows
          matches = by_target(candidates, selector)
          matches = by_substring(candidates, selector) if matches.empty?

          return [ nil, no_match(selector, sections) ] if matches.empty?
          return [ nil, ambiguous(selector, matches) ] if matches.size > 1

          [ matches.first, nil ]
        end

        # `alpha` and `/projects/alpha` and `/projects/alpha/index.md` all name
        # the same commitment, because a board line links the project directory
        # and a concept inside it interchangeably.
        def by_target(rows, selector)
          prefix = selector.to_s.start_with?("/") ? selector.to_s : "/projects/#{selector}"
          prefix = prefix.chomp("/").downcase
          rows.select do |row|
            row.targets.any? do |target|
              t = target.downcase.chomp("/")
              t == prefix || t.start_with?("#{prefix}/")
            end
          end
        end

        def by_substring(rows, selector)
          needle = selector.to_s.strip.downcase
          return [] if needle.empty?

          rows.select { |row| row.text.downcase.include?(needle) }
        end

        def no_match(selector, sections)
          where = sections ? " under #{sections.join(" or ")}" : ""
          "no board line#{where} matches '#{selector}' — neither as a /projects/ link nor as a " \
            "substring of a line. `okf pro board` lists what is there."
        end

        def ambiguous(selector, matches)
          "'#{selector}' matches #{matches.size} board lines, and picking one would move a " \
            "commitment nobody named:\n#{matches.map { |r| "  [#{r.section}] #{r.text}" }.join("\n")}\n" \
            "Name the project link, or a substring only one line carries."
        end
      end
    end
  end
end
