# frozen_string_literal: true

module OKF
  module Pro
    # The trust rules. Both are PreToolUse, so they deny the write rather than
    # complain after it, and both scope through Target first: `verified:` and
    # the journal calendar are bundle vocabulary, and a guard that fired on
    # them anywhere — the README quoting the frontmatter format, a scratch
    # file under .tmp/ — was a false block that trains people to switch the
    # guard off.
    module Guards
      # The block-style spelling, and the fast path. It is NOT the whole
      # rule: YAML frontmatter may be a flow mapping — `{type: Briefing,
      # verified: 2026-08-01}` — which the okf reader parses as a real
      # attestation and this pattern never sees. A gate that reads a
      # narrower grammar than the parser it defends is a gate with a door
      # cut into it, so the flow spelling gets its own pattern below.
      # Patterns rather than a YAML parse, because the added text of an
      # Edit is a FRAGMENT — it need not be valid YAML, or even contain
      # the fences — and a parser that failed on a fragment would decline
      # to see the very attestation it was called to catch.
      ATTESTATION = /^[[:blank:]]*verified[[:blank:]]*:/.freeze

      # `verified` as a key ANYWHERE in a flow mapping — after `{`, after a
      # comma, at any nesting. Matched against the added text only when it
      # actually contains a flow mapping, so prose that happens to say
      # "verified:" in a sentence does not trip it.
      FLOW_ATTESTATION = /[{,][[:blank:]]*['"]?verified['"]?[[:blank:]]*:/.freeze

      JOURNAL_ENTRY = %r{\Ajournal/(\d{4}-\d{2}-\d{2})\.md\z}.freeze

      module_function

      # Every spelling of the attestation the okf reader would accept. The
      # test is deliberately generous: this gate ASKS, so a false positive
      # costs one prompt and a miss costs a forged signature.
      def attests?(text)
        text = text.to_s
        ATTESTATION.match?(text) || FLOW_ATTESTATION.match?(text)
      end

      # `verified:` is the owner's signature, and an agent that can type it
      # unchecked can forge it. Everything downstream — the To-read line, the
      # briefing's standing, the audit — rests on that block meaning a person
      # actually read the source. This is the most load-bearing gate in the repo.
      #
      # It asks rather than denies, because the invariant was never who holds
      # the pen — it is who decided. The owner reviews with the agent and the
      # agent promotes the change; this gate turns that write into an explicit
      # owner approval, and the approval IS the attestation. Where nobody can
      # approve — an unattended session — "ask" has no approver and the write
      # is refused, which is the fail-closed floor the old outright denial had.
      def guard_verified(event)
        return [] if Target.for(event).nil?
        return [] unless attests?(event.added_text)

        { "ask" => "This edit writes 'verified:' — owner attestation. The agent is the scribe; " \
                   "your approval is the attestation. Approve ONLY if you have actually reviewed " \
                   "this content yourself. If you have not, deny — unverified is the truth." }
      end

      # A past day is a record. Editing it does not correct history, it destroys
      # the one artefact that says what was known at the time — that stays a
      # flat refusal. Creating a missing past day is different, and it is the
      # owner's call, not the agent's: Rule 2's fallback is reconstructing
      # yesterday's missing entry, declared as reconstructed — but "the file
      # does not exist" alone would let an agent fabricate any date in the
      # past as quietly as filing a note, and the same guard would then defend
      # the forgery as history. So creation asks, exactly like `verified:`:
      # interactive, the owner approves the reconstruction; unattended, no
      # approver, fail closed.
      def journal_guard(event, today: Date.today)
        target = Target.for(event)
        return [] if target.nil?

        match = target.rel.match(JOURNAL_ENTRY)
        return [] unless match
        return [] unless match[1] < today.to_s

        unless target.exist?(target.rel)
          return { "ask" => "This creates journal/#{match[1]}.md — a PAST day that has no entry. " \
                            "Approve ONLY if this is a declared reconstruction of a day you " \
                            "actually worked (Rule 2's fallback). A fabricated record is worse " \
                            "than a gap: this guard will defend whatever you approve as history." }
        end

        [ "BLOCKED — journal/#{match[1]}.md is a past day. Records are append-only; " \
          "corrections go in today's entry, pointing back." ]
      end
    end
  end
end
