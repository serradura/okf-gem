# frozen_string_literal: true

module OKF
  module Pro
    # The door the other guards do not cover.
    #
    # `guard-verified` and `journal-guard` are PreToolUse on Edit/Write/
    # MultiEdit — they read a `file_path` and the text being added. A shell
    # command has neither: `cat > .okf/reference/x.md <<'EOF' … verified: …`
    # writes the same bytes with no file_path to scope on and no new_string
    # to scan, so every trust rule in this repo used to step aside for a tool
    # the agent already has. That is the contract's forbidden case — not a
    # gate that refused, a gate that was never asked.
    #
    # This cannot parse shell, and does not pretend to. It answers one
    # narrow question — does this command look like it writes markdown
    # inside a bundle? — and routes the answer to the owner, who can read
    # the command. Asking is the honest verdict for a check that cannot
    # decide: it costs one prompt when wrong, and unattended it fails
    # closed, exactly like the attestation gate it backstops.
    module ShellGuard
      # Mutation, in the spellings a shell actually uses. Redirections and
      # in-place editors first, then the file-movers.
      MUTATORS = [
        # `cat … > file`, `… >> file`, with two exclusions, both of them
        # reads this used to call writes. A guard that fires on reads is a
        # guard people switch off.
        #
        # Redirections to /dev/ are excluded: `2>/dev/null` is a read-only
        # command discarding its stderr, and counting it as a write made
        # every `grep … 2>/dev/null` in a repo that happens to contain
        # markdown a prompt.
        #
        # An ASCII arrow is excluded by the lookbehind, because a `>` after
        # `-` or `=` is not a position a redirection can occupy. Nothing
        # anchored this before, so `-->` and `=>` read as writes — worst of
        # all in a bundle, where `-->` closes the HTML comment the skill
        # mandates on every keyed rule and is also mermaid's edge, and `=>`
        # is in every quoted Ruby hash. The second alternative covers the
        # doubled arrows (`->>`, `-->>`), whose trailing `>` is preceded by
        # a `>` rather than by the `-` that gives it away.
        %r{(?<![-=]|[-=]>)>{1,2}[[:blank:]]*(?!/dev/)[^|&\s]}, # cat … > file, … >> file
        /\btee\b/,
        /\b(?:sed|perl|ruby|python3?|node|awk)\b[^|;]*-i\b/, # in-place editors
        /\b(?:cp|mv|rm|install|truncate|dd|rsync|ln)\b/,
        /\b(?:File\.write|File\.open|open\([^)]*['"]w)/ # inline interpreter writes
      ].freeze

      # A markdown path anywhere in the command, minus the quoting and
      # separators a shell puts around it.
      MARKDOWN = %r{[^\s'"`|;&()<>]*\.md\b}.freeze

      # What separates one COMMAND from the next, for the one question below
      # that has to look past the whole string.
      #
      # A single `|` is deliberately absent: a pipeline is one command, not
      # two, and splitting on it put this gem's own redirect target in a
      # segment of its own — `okf pro snapshot | tee -a .okf/log.md`, the
      # prescribed way to append the Snapshot line, was recorded as friction.
      # That is the good path counted as evidence against itself, which is the
      # one failure the exclusion exists to prevent. `||` is still a separator
      # and is listed first so the doubled form wins the alternation.
      SEPARATORS = /&&|\|\||;|\n/.freeze

      module_function

      def check(event)
        command = event.command
        return [] if command.empty?
        return [] unless MUTATORS.any? { |m| command.match?(m) }

        # Scoped like every other guard: no bundle here, not this repo's
        # business. The cwd is the only anchor a shell command offers —
        # there is no file_path to walk up from — so this is the one check
        # that must root through it.
        root = BundleRoot.enclosing(event.cwd)
        return [] if root.nil?
        return [] unless touches_bundle?(command, root)

        # Recorded here rather than at a hook event of its own, because
        # `settings.json` is SEEDED: a new registration would never reach an
        # adopter through `upgrade`, so friction has to ride a path already
        # wired. This is the honest point for it — a markdown write inside the
        # bundle, arriving through Bash, is by definition a thing the verbs did
        # not cover. Own commands are skipped, or the good path would be
        # counted as evidence against itself.
        #
        # It records INTENT: PreToolUse fires before the owner may deny.
        unless own_write?(command)
          Friction.record(root, "shell", Friction.classify_command(command), command.lines.first.to_s.strip[0, 200])
        end

        { "ask" => "This shell command looks like it writes markdown inside the bundle:\n  " \
                   "#{command.lines.first.to_s.strip}\n" \
                   "Shell writes bypass the trust guards — nothing checked this for a forged " \
                   "'verified:' block or an edit to a past journal day. Approve only if you " \
                   "have read the command and it does neither; otherwise deny and use Edit or " \
                   "Write, which the guards can see." }
      end

      # Whether the WRITE belongs to this gem — not whether the command mentions
      # it. `Friction.own_command?` exists so the good path is not counted as
      # evidence against itself (`okf pro snapshot >> .okf/log.md` is the
      # prescribed way to add the Snapshot line), and asking it of the whole
      # string let a mention anywhere suppress the record: `okf pro state &&
      # cat notes.md > .okf/board.md` prompted the owner and counted nothing.
      # An agent chaining a read with a write is exactly the pattern that
      # produces it, so the under-count was in the commonest shape.
      #
      # So it is asked of the SEGMENT that carries the mutator. A segment with
      # no mutator is nobody's write — `cd repo && okf pro promote alpha` is
      # still this gem's — and a mutator in a segment this gem does not own is
      # a hand-write whatever else the line says.
      #
      # Splitting on separators is NOT shell parsing and may not become one:
      # a separator inside quotes mis-splits, and the only consequence of that
      # is a telemetry row. The PROMPT above is decided from the whole command
      # and is unaffected, so nothing about the guard's safety rides on this.
      #
      # The confessed residue, since a bounded error is only bounded if it is
      # written down: a `;` or `&&` inside quoted content splits a command that
      # is genuinely this gem's, and the fragment carrying the mutator word is
      # then read as somebody else's write; and a capture whose TEXT names
      # `board.md` trips the laundering guard above. Both over-count. That is
      # the lesser error — an over-count points a maintainer at a verb that
      # already exists, while the under-counts these replaced hid the commonest
      # shape there is and the worst one there is — and neither can refuse
      # anything.
      def own_write?(command)
        segments = command.to_s.split(SEPARATORS)
        return false unless segments.any? { |segment| Friction.own_command?(segment) }
        # A pipeline is one command, and that must not become a way to launder
        # a hand-write: `okf pro board | sed s/a/b/ > .okf/board.md` begins with
        # this gem and ends by regenerating the board, which is failure mode 07
        # by name. No verb pipes into a path a verb covers — `snapshot` has no
        # `--write` and appends to `log.md`, which no verb covers — so an own
        # command aimed at the board is friction whatever produced the bytes.
        return false if Friction.classify_command(command) == "board.md"

        segments.none? do |segment|
          !Friction.own_command?(segment) && MUTATORS.any? { |m| segment.match?(m) }
        end
      end

      # The bundle by name is enough on its own. A markdown path is enough
      # only if it could be in the bundle: relative — resolved against a cwd
      # already known to be inside one — or absolute and under the root. An
      # absolute path elsewhere is not this repo's markdown, and treating a
      # gem's CHANGELOG.md as a bundle write is how the prompt stopped
      # carrying information.
      #
      # Relative paths stay conservative rather than being resolved against
      # the cwd, because a `cd` earlier in the command would make that
      # resolution a guess, and this guard asks when it cannot decide.
      def touches_bundle?(command, root)
        return true if command.match?(/#{Regexp.escape(BundleRoot::DIR)}\b/)

        command.scan(MARKDOWN).any? do |path|
          !path.start_with?("/") || path.start_with?("#{root}/")
        end
      end
    end
  end
end
