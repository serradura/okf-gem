# frozen_string_literal: true

module OKF
  module Pro
    # The write contract, made enforceable.
    #
    #   Additive and targeted, never regenerative. A write verb may append a
    #   line or edit the line it was given. No verb rewrites a file it did not
    #   fully derive from that file's own prior contents.
    #
    # Failure mode 07 — Agent Drift — is an LLM regenerating a view and dropping
    # a task, silently: no error, no diff anyone reads, one commitment gone. The
    # verdict that closed it was "derivation exists as a checker and never as a
    # generator", and the status quo it was written against is the failure
    # rather than a defence: today the agent rewrites `board.md` with a heredoc,
    # which is exactly the silent-drop hazard performed by exactly the actor the
    # record names.
    #
    # So a write verb does not promise to be careful. It states the delta it
    # intends, computes the new text purely, and hands both to this module,
    # which compares the LINE MULTISETS and refuses when the actual delta is not
    # the intended one. A Ruby function that provably cannot drop a line is the
    # remedy for a heredoc that can, and the difference between the two is that
    # this one is checked.
    #
    # Pure: text in, findings out. No disk, no bundle, no dates.
    module Conserve
      module_function

      # `added:` / `removed:` are the lines the caller means to add and take
      # away. `moved:` is the third shape, and it is invisible to a multiset by
      # construction — a line that changed sections is neither added nor
      # removed — so it is asserted directly: still there before, still there
      # after. Without that, "move it" and "delete it and add it back" and "do
      # nothing" are the same claim.
      #
      # Returns findings; empty means the file may be written.
      def check(before, after, added: [], removed: [], moved: [])
        was = counts(before)
        now = counts(after)

        findings = delta_findings(subtract(now, was), counts_of(added), "added") +
                   delta_findings(subtract(was, now), counts_of(removed), "removed")

        Array(moved).each do |line|
          key = normalize(line)
          findings << "conservation: the line to move is not in the file as it stands: #{key}" unless was[key]
          findings << "conservation: the line to move is gone from the result: #{key}" unless now[key]
        end
        findings
      end

      # One direction of the comparison, both ways round: what happened and
      # was not intended, and what was intended and did not happen. Both are
      # refusals — an edit that did less than it said is as much a lie as one
      # that did more, and the second is how a promotion silently no-ops.
      def delta_findings(actual, intended, verb)
        findings = subtract(actual, intended).map do |line, n|
          "conservation: #{n} line(s) #{verb} that the edit did not intend: #{line}"
        end
        subtract(intended, actual).each do |line, n|
          findings << "conservation: #{n} line(s) the edit meant to have #{verb} are not: #{line}"
        end
        findings
      end

      # Trailing newline stripped, nothing else. Whitespace inside a line is
      # content on a board — the leading `- ` is the counters' own grammar —
      # and normalising it away would let an edit reindent the file past a
      # guard whose whole job is to notice.
      def normalize(line)
        line.to_s.chomp
      end

      def counts(text)
        counts_of(text.to_s.lines)
      end

      def counts_of(lines)
        Array(lines).each_with_object({}) do |line, acc|
          key = normalize(line)
          acc[key] = (acc[key] || 0) + 1
        end
      end

      def subtract(left, right)
        left.each_with_object({}) do |(line, n), acc|
          surplus = n - (right[line] || 0)
          acc[line] = surplus if surplus.positive?
        end
      end
    end
  end
end
