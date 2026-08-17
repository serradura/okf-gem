# frozen_string_literal: true

# Hand-rolled where okf's Command already has `json_flags`/`emit_json`, and
# deliberately: those are PRIVATE instance methods on a class this module is not
# — `OKF::Pro::CLI` is a module, and the suite drives `CLI.run` directly rather
# than through `okf/plugin.rb`, so a parser inherited from the kernel would be
# untested at the one door every test goes through. The same argument the
# duplicated `help_rows` already carries.
require "optparse"

module OKF
  module Pro
    # Dispatch, and the exit codes the hook protocol reads.
    #
    # Every check has the same signature — event in, messages out, empty means
    # pass — so this table is the only place a check name is bound to behaviour,
    # and the only place an exit code is chosen. A drill runs exactly what a
    # session runs because both arrive here.
    module CLI
      CHECKS = {
        "guard-verified" => ->(event) { Guards.guard_verified(event) },
        "journal-guard" => ->(event) { Guards.journal_guard(event) },
        "shell-guard" => ->(event) { ShellGuard.check(event) },
        "check-okf" => ->(event) { Conformance.check(Target.for(event)) },
        "cap-check" => ->(event) { Budget.cap_check(Target.for(event)) },
        "reconcile-search" => ->(event) { Reconcile.search(Target.for(event), event) },
        "post-edit" => ->(event) { CLI.post_edit(event) },
        "stop-gate" => ->(event) { Closing.stop_gate(event) }
      }.freeze

      # Every name this module answers to. The hook door accepts a strictly
      # narrower set — CHECKS.keys plus session-context — enforced one layer up,
      # in OKF::CLI::Pro, because `run` dispatches the CI verbs off the same
      # first element: a settings.json typo spelling `hook audit` would otherwise
      # install a gate that reads no stdin, never blocks, and reports clean.
      # The generator's verbs. They take a destination rather than a bundle, so
      # they do not go through `dir_argument` — `setup` into an empty directory
      # is the whole point, and refusing one that holds no bundle would refuse
      # every first run.
      SCAFFOLD = %w[setup upgrade skill].freeze

      # The readers: one call answers what nine calls answered. No new logic —
      # every aggregation they print already existed and was consumed only by a
      # gate, which is why an agent working in a seeded bundle rediscovered the
      # board by reading raw markdown while the stop gate was computing it.
      READERS = %w[audit records snapshot unverified state board friction].freeze

      # The writers: the shapes with exactly one correct form. Each one is
      # additive and targeted, and each refuses through `Conserve` rather than
      # promising to be careful — see `writes.rb` for the contract.
      WRITERS = %w[capture promote demote journal close].freeze

      NAMES = (CHECKS.keys + [ "session-context" ] + READERS + WRITERS + SCAFFOLD).freeze

      # The names the hook door accepts, and the only ones. `run` dispatches the
      # CI verbs off the same first element, so without this the adapter would
      # forward `hook audit` into a verb that reads no stdin and cannot block.
      HOOK_NAMES = (CHECKS.keys + [ "session-context" ]).freeze

      # Written to stderr immediately before a check runs, and read by the
      # scaffold's `.claude/hooks/run`. It is the whole of the wrapper's identity
      # proof: a stray `okf` on PATH that exits 0 is indistinguishable from a
      # clean gate by status alone, and that is a gate silently switched off.
      # The wrapper strips this line before passing stderr on.
      #
      # Emitted here rather than at the door, so that its presence means the
      # check was actually reached — not merely that the plugin loaded. The
      # prototype proved the difference: its `okf pro contract` handshake
      # answered fine while the library was missing.
      MARKER = "okf-pro-enforcer v1"

      # What `dir_argument` returns instead of a path. Distinct from nil, which
      # is the legitimate "no argument given, use the working directory".
      REFUSED = :refused

      # The command list, and the single place it is described. `okf help`
      # prints a second copy through OKF::CLI::Pro.help_rows, and it has to:
      # reading this one would make every `okf help` load the whole library,
      # which is the cost deferring the require exists to avoid. The two are
      # joined by a test instead — the arrangement the closure grammar and the
      # dormancy window already use.
      USAGE = [
        [ "setup",      "[DIR]", "create or complete an agent's brain in DIR (default .)" ],
        [ "upgrade",    "[DIR]", "rewrite the gem-owned governance files; stage the rest" ],
        [ "state",      "[DIR]", "what is on the board, in one call — add --full for the corpus" ],
        [ "board",      "[DIR]", "one row per board line: section, dates, age, links" ],
        [ "capture",    "TEXT",  "append a dated Inbox line" ],
        [ "promote",    "SEL",   "Inbox or Backlog to In flight, refusing over the cap" ],
        [ "demote",     "SEL",   "In flight back to Backlog" ],
        [ "journal",    "open",  "create today's journal day and index it" ],
        [ "close",      "SLUG",  "the three mechanical closing moves for a project" ],
        [ "audit",      "[DIR]", "every invariant at once — the CI door" ],
        [ "records",    "[DIR]", "does the staged commit rewrite a past journal day?" ],
        [ "snapshot",   "[DIR]", "compute the day's counter line (prints, never writes)" ],
        [ "unverified", "[DIR]", "generated concepts still awaiting the owner's read" ],
        [ "friction",   "[DIR]", "what was done by hand that a verb could do" ],
        [ "skill",      "DEST",  "(re)install okf-pro's agent skill on its own" ],
        [ "hook",       "CHECK", "run one gate against a hook event on stdin" ]
      ].freeze

      # Which flags each verb accepts, declared rather than discovered: an
      # undeclared flag is a usage error the parser names, instead of a
      # positional that `dir_argument` then reports as a second directory.
      #
      # Absence from this table means "accepts none", not "is exempt from it":
      # `parse_flags` reads `FLAGS.fetch(verb, [])`, so a verb that routes
      # through it refuses an undeclared flag whether or not it is listed. The
      # verbs that skipped the parser entirely are how `okf pro audit --json`
      # came to hand `--json` to `BundleRoot.resolve` and report "holds no OKF
      # bundle" as a FINDING — exit 1, which a pipeline reads as a broken
      # bundle rather than as its own typo.
      FLAGS = {
        "state" => %i[json pretty full],
        "board" => %i[json pretty section],
        "snapshot" => %i[json pretty],
        "unverified" => %i[json pretty],
        "friction" => %i[json pretty issue clear]
      }.freeze

      # How each flag is spelled in the usage. Read FROM `FLAGS` rather than
      # typed beside it, so a flag added to one verb cannot be missing from the
      # help — `parse_flags` tells a user that `okf pro --help` lists what each
      # verb takes, and for a while that was simply untrue.
      FLAG_HELP = {
        json: "--json", pretty: "--pretty", full: "--full",
        section: "--section NAME", issue: "--issue", clear: "--clear"
      }.freeze

      # Where a friction report goes. It is about okf-pro, not about the
      # adopter's knowledge base, so it is this repository regardless of whose
      # tree the bundle lives in. Nothing is ever filed automatically.
      ISSUE_REPO = "serradura/okf-gem"

      HELP = %w[--help -h help].freeze

      # The bare semantic version, matching `okf --version` and
      # `okf mcp --version`. No gem name: the caller has already named the
      # extension on the command line, so a name in the output buys nothing and
      # costs a script a `cut`. (`okf tui --version` prints `okf-tui 1.0.0` and
      # is the odd one out; changing a released gem's output is not this gem's
      # to do.)
      VERSION_FLAGS = %w[--version -v version].freeze

      module_function

      # The three PostToolUse checks in one process, sharing one bundle read —
      # the read is the expensive part, and three separate invocations paid for
      # it three times over.
      def post_edit(event)
        target = Target.for(event)
        # The second friction point, and the same argument as the first: this
        # runs on every Edit/Write already, so recording here costs no hook
        # registration an adopter would never receive. Only the files a verb
        # covers count — an Edit to a concept body is judgment and always will
        # be, and counting it would report the system working as friction.
        Friction.record(target.root, "edit", target.rel) if target && Friction.covered_path?(target.rel)
        Conformance.check(target) + Budget.cap_check(target) + Reconcile.search(target, event)
      end

      def run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
        check = argv.shift.to_s

        # Asking for help is not an error, so it goes to stdout and exits 0.
        # Asking for nothing is: `okf pro` alone did nothing anyone requested,
        # and a 0 there would say it did.
        return usage(stdout, PASS) if HELP.include?(check)

        if VERSION_FLAGS.include?(check)
          stdout.puts VERSION
          return PASS
        end

        return usage(stderr, BLOCK) if check.empty?

        # Past this line the answer can only be PASS-with-a-check-run or BLOCK,
        # which is exactly what the marker claims. It is not emitted for the CI
        # verbs: they are read by a person and a pipeline, not by the wrapper.
        stderr.puts MARKER if HOOK_NAMES.include?(check)

        if READERS.include?(check) || WRITERS.include?(check)
          # Whitelisted before it is sent: the list above is the composition
          # table, and dispatching off an unvalidated name is how `hook audit`
          # became a gate that always said fine.
          return send(check, argv, stdout: stdout, stderr: stderr)
        end
        return scaffold(check, argv, stdout: stdout, stderr: stderr) if SCAFFOLD.include?(check)
        return session_context(stdin, stdout: stdout) if check == "session-context"

        handler = CHECKS[check]
        unless handler
          # An unknown check name is enforcement that did not run. The shell
          # dispatcher this replaces fell off the end of its `case` and exited 0
          # on a typo — silence in the one place the contract names.
          stderr.puts "ENFORCEMENT MISCONFIGURED — no check named '#{check}'. Known: #{NAMES.join(", ")}."
          return BLOCK
        end

        event = Event.from_stdin(stdin)
        if event.parse_error?
          stderr.puts "ENFORCEMENT DEGRADED — '#{check}' could not read its input: #{event.parse_error}. " \
                      "No check ran, so nothing here has been checked."
          return BLOCK
        end

        # The hook protocol reads every exit but 2 as NON-BLOCKING, so an
        # exception that escapes a check is not an error report — it is the
        # edit sailing through while the gate lies on the floor. Refusing on
        # any crash is the contract's floor: a gate that cannot check must
        # not wave things through.
        begin
          result = handler.call(event)
        rescue StandardError => e
          stderr.puts "ENFORCEMENT ERROR — '#{check}' crashed (#{e.class}: #{e.message}); " \
                      "nothing was checked, so the call is refused. A crash that passed " \
                      "would be indistinguishable from a clean bundle."
          return BLOCK
        end
        return PASS if result.empty?

        # A check that returns {"ask" => reason} is routing the decision to the
        # owner instead of refusing: the hook protocol reads exit 0 plus this
        # JSON as "prompt the user". Interactive, the owner approves or denies
        # in the moment; unattended, there is no approver and the write fails
        # closed at the permission layer. Arrays stay refusals, as ever.
        if result.is_a?(Hash)
          stdout.puts JSON.generate(
            "hookSpecificOutput" => {
              "hookEventName" => "PreToolUse",
              "permissionDecision" => "ask",
              "permissionDecisionReason" => result.fetch("ask")
            }
          )
          return PASS
        end

        stderr.puts result.join("\n")
        BLOCK
      end

      def audit(argv, stdout: $stdout, stderr: $stderr)
        options = parse_flags(argv, "audit", stdout, stderr)
        return options == :handled ? PASS : BLOCK unless options.is_a?(Hash)

        root = dir_argument(argv, "audit", stderr)
        return BLOCK if root == REFUSED

        begin
          msgs = Audit.call(root || Dir.pwd)
        rescue StandardError => e
          stderr.puts "okf pro audit — could not run (#{e.class}: #{e.message}); nothing was " \
                      "checked. This is exit 2, not 1: 1 means findings, and a pipeline that " \
                      "cannot tell a broken bundle from a broken checker learns to ignore both."
          return BLOCK
        end
        if msgs.empty?
          stdout.puts "okf pro audit — clean."
          return PASS
        end

        stderr.puts "okf pro audit — #{msgs.size} finding(s):\n#{msgs.join("\n")}"
        FAIL
      end

      # The append-only record, asked of the index. Separate from `audit`
      # because it reads a CHANGE (git's staged diff) rather than a STATE,
      # and the pre-commit door materialises a tree where that change is no
      # longer visible as one.
      def records(argv, stdout: $stdout, stderr: $stderr)
        options = parse_flags(argv, "records", stdout, stderr)
        return options == :handled ? PASS : BLOCK unless options.is_a?(Hash)

        root = dir_argument(argv, "records", stderr)
        return BLOCK if root == REFUSED

        begin
          msgs = Records.staged_violations(root || Dir.pwd)
        rescue StandardError => e
          stderr.puts "okf pro records — could not run (#{e.class}: #{e.message}); the staged " \
                      "diff was never read. Exit 2, for the reason `audit` gives."
          return BLOCK
        end
        if msgs.empty?
          stdout.puts "okf pro records — append-only."
          return PASS
        end

        stderr.puts "okf pro records — #{msgs.size} finding(s):\n#{msgs.join("\n")}"
        FAIL
      end

      # The checker-first half of derivation: computes the mechanical line for
      # a person to append. It prints and never writes — Agent Drift killed the
      # generator, and this is not one.
      def snapshot(argv, stdout: $stdout, stderr: $stderr)
        options = parse_flags(argv, "snapshot", stdout, stderr)
        return options == :handled ? PASS : BLOCK unless options.is_a?(Hash)

        root = bundle_for(argv, "snapshot", stderr)
        return BLOCK if root.nil?

        unless File.exist?(File.join(root, "board.md"))
          stderr.puts "okf pro snapshot — #{root} has no board.md to count."
          return BLOCK
        end

        counters = guarded("snapshot", stderr) { Snapshot.counters(root) }
        return BLOCK if counters.nil?

        # The rendered line travels WITH the counters rather than instead of
        # them. It is what a person appends to `log.md`, and a consumer that
        # had to re-render it from the twelve numbers would be a second
        # implementation of the one shape the stop gate verifies.
        line = Snapshot.render(counters)
        emit(stdout, options, { "line" => line, "counters" => counters }) { line }
        PASS
      end

      # Report-only, and for a shape of reason worth stating: absent
      # attestation is the truth, and a gate here would pressure toward the
      # one lie the system guards against.
      def unverified(argv, stdout: $stdout, stderr: $stderr)
        options = parse_flags(argv, "unverified", stdout, stderr)
        return options == :handled ? PASS : BLOCK unless options.is_a?(Hash)

        root = bundle_for(argv, "unverified", stderr)
        return BLOCK if root.nil?

        rows = guarded("unverified", stderr) { Attestation.rows(root) }
        return BLOCK if rows.nil?

        emit(stdout, options, rows) do
          if rows.empty?
            [ "okf pro unverified — nothing awaits a read." ]
          else
            [ "okf pro unverified — #{rows.size} concept(s) awaiting the owner's read " \
              "(the state is the truth, not a defect):", *Attestation.render(rows) ]
          end
        end
        PASS
      end

      # ── the readers ──────────────────────────────────────────────────────

      def state(argv, stdout: $stdout, stderr: $stderr)
        options = parse_flags(argv, "state", stdout, stderr)
        return options == :handled ? PASS : BLOCK unless options.is_a?(Hash)

        root = bundle_with_board(argv, "state", stderr)
        return BLOCK if root.nil?

        payload = guarded("state", stderr) { State.call(root, full: options[:full]) }
        return BLOCK if payload.nil?

        emit(stdout, options, payload) { State.render(payload) }
        PASS
      end

      def board(argv, stdout: $stdout, stderr: $stderr)
        options = parse_flags(argv, "board", stdout, stderr)
        return options == :handled ? PASS : BLOCK unless options.is_a?(Hash)

        root = bundle_with_board(argv, "board", stderr)
        return BLOCK if root.nil?

        text = Pro.read_text(File.join(root, "board.md"))
        rows = Board.rows(text)
        if options[:section]
          # An empty section and a misspelled one look identical in the output
          # and mean opposite things, so the heading is asked for by name. This
          # is the quiet-zero class the board's own grammar check exists for.
          unless section?(text, options[:section])
            stderr.puts "okf pro board — the board has no '## #{options[:section]}' section. " \
                        "An empty answer here would be indistinguishable from a section that is simply empty."
            return BLOCK
          end
          rows = rows.select { |row| row.section.casecmp(options[:section]).zero? }
        end

        today = Date.today
        payload = rows.map { |row| board_row(row, today) }
        emit(stdout, options, payload) { render_board(payload) }
        PASS
      end

      def section?(text, name)
        heading = "## #{name}"
        Board.visible(text).each_line.any? { |line| line.start_with?("## ") && line.chomp.rstrip.casecmp(heading).zero? }
      end

      def board_row(row, today)
        date = row.line_date
        {
          "section" => row.section,
          "text" => row.text,
          "date" => date&.to_s,
          "age" => date && (today - date).to_i,
          "chase" => row.chase_date&.to_s,
          "targets" => row.targets
        }
      end

      def render_board(rows)
        return [ "okf pro board — no lines." ] if rows.empty?

        rows.map do |row|
          age = row["age"] ? " (#{row["age"]}d)" : ""
          chase = row["chase"] ? " [chase #{row["chase"]}]" : ""
          "[#{row["section"]}]#{age}#{chase} #{row["text"]}"
        end
      end

      def friction(argv, stdout: $stdout, stderr: $stderr)
        options = parse_flags(argv, "friction", stdout, stderr)
        return options == :handled ? PASS : BLOCK unless options.is_a?(Hash)

        root = bundle_for(argv, "friction", stderr)
        return BLOCK if root.nil?

        return clear_friction(stdout, root) if options[:clear]

        report = Friction.report(root)
        rows = friction_rows(report)
        return issue_report(stdout, root, report, rows) if options[:issue]

        payload = { "available" => report.available, "recorded" => report.events.size,
                    "unreadable" => report.unreadable, "by" => rows }
        emit(stdout, options, payload) { render_friction(report, rows) }
        PASS
      end

      # Grouped by the DOOR as well as the file. An Edit to the board and a
      # shell redirect at it are different findings about the same path: one
      # says a verb went unused, the other says the trust guards were bypassed
      # entirely, and what covers them is not the same answer.
      def friction_rows(report)
        counts = report.events.each_with_object({}) do |event, acc|
          key = [ event["via"].to_s, event["what"].to_s ]
          acc[key] = (acc[key] || 0) + 1
        end
        counts.sort_by { |(via, what), n| [ -n, via, what ] }.map do |(via, what), n|
          { "via" => via, "what" => what, "count" => n, "covered by" => Friction.covered_by(via, what) }
        end
      end

      # The way out of a sticky marker, and the way to stop a lifetime total
      # nagging about a week nobody can change. It touches `.tmp/` and nothing
      # else — this is telemetry, not knowledge, and no bundle file is involved.
      def clear_friction(stdout, root)
        removed = Friction.clear(root)
        if removed.nil?
          stdout.puts "okf pro friction — could not clear #{File.dirname(Friction.log_path(root))}. " \
                      "Remove the files by hand: #{Friction.log_path(root)} and #{Friction.marker_path(root)}."
          return PASS
        end

        stdout.puts "okf pro friction — cleared (#{removed} file(s) removed). The count starts again from here."
        PASS
      end

      # Report-only, exit 0 — the family `unverified` belongs to. It measures
      # this gem, not the adopter's bundle, and a measurement that gated
      # something would start being gamed the day someone noticed.
      # Nothing readable and nothing recorded are different states, and this is
      # the surface a person meets first. `--issue` already treats them apart —
      # it declines to file for one and files for the other — so a default that
      # called an unparseable log "nothing recorded" made the human output the
      # one that lied.
      def unreadable_note(report)
        "okf pro friction — #{report.unreadable} recorded line(s) will not parse and nothing else " \
          "is recorded, so this is a corrupted log rather than a quiet one. Nothing here is a " \
          "zero. `okf pro friction --clear` starts the count again."
      end

      def render_friction(report, rows)
        return [ UNAVAILABLE_NOTE ] unless report.available

        if rows.empty?
          return [ unreadable_note(report) ] if report.unreadable.positive?

          return [ "okf pro friction — nothing recorded. Either the verbs covered it, or nothing was written by hand." ]
        end

        lines = [ "okf pro friction — #{report.events.size} bundle edit(s) recorded so far that a " \
                  "command could have done:" ]
        rows.each do |row|
          label = "#{row["via"]} #{row["what"]}"
          lines << "  #{label.ljust(16)} #{row["count"]}#{"   now: #{row["covered by"]}" if row["covered by"]}"
        end
        lines << "  #{report.unreadable} recorded line(s) could not be parsed and are not counted above." if report.unreadable.positive?
        lines << "If one of these should be an `okf pro` verb, please tell the maintainer — " \
                 "`okf pro friction --issue` prints a ready-to-paste report. It helps more than you think."
        lines << "The count is cumulative; `okf pro friction --clear` starts it again."
        lines
      end

      # Names the file, because "check that .tmp/ is writable" is not actionable
      # once the marker is the thing keeping the answer unknown — the directory
      # may be perfectly writable now and the report still says unknown, which
      # is correct and infuriating without the next sentence.
      UNAVAILABLE_NOTE = "okf pro friction — the recorder could not write at some point, so this is " \
                         "not zero, it is unknown. Check that .tmp/ is writable at the repository " \
                         "root, then `okf pro friction --clear` to start counting again."

      # Printed, never run. Filing an issue is outward-facing and irreversible,
      # and a hook that did it unattended would be both without anyone asking.
      def issue_report(stdout, root, report, rows)
        # Nothing counted, and the recorder says it counted honestly — so there
        # is nothing to file. The report drafted here was complete and
        # ready-to-paste and said "Recorded over 0 event(s)", which asks the
        # maintainer to act on an empty list.
        #
        # Two states are NOT that, and both still file. "The recorder could not
        # write" is something that happened; so is a log whose every line was
        # unparseable, which is a corrupted recorder rather than a quiet one —
        # zero rows with a positive `unreadable` is the shape that would
        # otherwise be reported as nothing at all.
        if rows.empty? && report.available && report.unreadable.zero?
          stdout.puts "okf pro friction — nothing recorded, so there is no report to file. " \
                      "Either the verbs covered it or nothing was written by hand; an issue " \
                      "whose body is an empty list asks the maintainer to act on nothing."
          return PASS
        end

        # Says what was counted, and claims nothing about what covers it. The
        # banner had just established that a shell redirect's answer is Edit or
        # Write rather than a verb, and a title reading "that a verb could
        # cover" over a body whose only row says otherwise asks the maintainer
        # for a verb this gem decided not to want. The `covered by` note on
        # each row is where that question is actually answered.
        title = "okf-pro: #{report.events.size} bundle edit(s) recorded by hand"
        body = issue_body(root, report, rows)
        if which("gh")
          stdout.puts "Run this — it is not run for you, because filing an issue is yours to decide:"
          stdout.puts
          stdout.puts "gh issue create --repo #{ISSUE_REPO} \\"
          stdout.puts "  --title #{shell_quote(title)} \\"
          stdout.puts "  --body #{shell_quote(body)}"
        else
          stdout.puts "`gh` is not on PATH, so here is the issue to paste:"
          stdout.puts
          stdout.puts "  https://github.com/#{ISSUE_REPO}/issues/new"
          stdout.puts
          stdout.puts "Title: #{title}"
          stdout.puts
          stdout.puts body
        end
        PASS
      end

      def issue_body(_root, report, rows)
        lines = [ "`okf pro friction` recorded these while working in a bundle. Each is an edit made",
                  "by hand inside it — some to a file a command already covers, some through a door",
                  "the trust guards cannot see at all. The `covered by` note says which.", "" ]
        # The evidence is printed whatever the recorder's state. Branching the
        # whole body on `available` dropped every row it had and then said "the
        # counts above are unknown" over a body with nothing above it — a
        # sentence about text that was not there, under a title that still
        # counted the rows. The marker is sticky by design, so one failed write
        # weeks ago made every later report evidence-free.
        rows.each do |row|
          covered = row["covered by"]
          lines << "* `#{row["via"]} #{row["what"]}` — #{row["count"]} time(s)#{" (covered by: #{covered})" if covered}"
        end
        lines << "" << "Recorded over #{report.events.size} event(s)."
        lines << "#{report.unreadable} recorded line(s) were unparseable and are excluded." if report.unreadable.positive?
        unless report.available
          lines << "The recorder could not write at some point, so this is a floor rather than a " \
                   "total: the real count is higher by an unknown amount."
        end
        lines << "" << "okf-pro #{VERSION}, ruby #{RUBY_VERSION}."
        lines.join("\n")
      end

      # Single-quoted with the one escape a POSIX shell accepts inside them.
      # The body is assembled from recorded `what` values, which are this gem's
      # own vocabulary — but printing a command a reader will paste is exactly
      # the place not to assume that.
      def shell_quote(text)
        # Block form, and it is load-bearing: in a replacement STRING, `\'` is
        # gsub's post-match special, so the string form of this substitution
        # spliced the rest of the text back in after every apostrophe. A block
        # return is taken literally.
        "'#{text.to_s.gsub("'") { "'\\''" }}'"
      end

      def which(name)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
          path = File.join(dir, name)
          File.file?(path) && File.executable?(path)
        end
      end

      # ── the writers ──────────────────────────────────────────────────────

      def capture(argv, stdout: $stdout, stderr: $stderr)
        answered = writer_flags(argv, "capture", stdout, stderr)
        return answered == :handled ? PASS : BLOCK unless answered == :ok

        text = argv.shift
        if text.nil?
          stderr.puts "okf pro capture — takes the words to capture: `okf pro capture \"what you heard\"`."
          return BLOCK
        end

        write_verb("capture", argv, stdout, stderr) { |root| Writes.capture(root, text) }
      end

      def promote(argv, stdout: $stdout, stderr: $stderr)
        selector_verb("promote", argv, stdout, stderr) { |root, selector| Writes.promote(root, selector) }
      end

      def demote(argv, stdout: $stdout, stderr: $stderr)
        selector_verb("demote", argv, stdout, stderr) { |root, selector| Writes.demote(root, selector) }
      end

      def journal(argv, stdout: $stdout, stderr: $stderr)
        answered = writer_flags(argv, "journal", stdout, stderr)
        return answered == :handled ? PASS : BLOCK unless answered == :ok

        sub = argv.shift
        unless sub == "open"
          stderr.puts "okf pro journal — takes one subcommand, `open`, and was given " \
                      "#{sub.nil? ? "none" : "'#{sub}'"}. `okf pro journal open` creates today's day " \
                      "file and its index line; what goes in it is yours to write."
          return BLOCK
        end

        write_verb("journal open", argv, stdout, stderr) { |root| Writes.journal_open(root) }
      end

      # `close` takes a PROJECT, not a board-line selector, and the difference
      # is not pedantry: `Writes.close` requires one directory segment, so the
      # `/projects/<slug>/index.md` form a board line actually carries — the
      # one `okf pro board` prints — is a refusal, and so is a substring. The
      # shared message offered both, which sends the reader to try what the
      # verb rejects.
      CLOSE_ARGUMENT = "takes the project to close: its directory name under projects/, or the " \
                       "`/projects/<slug>/` link a board line carries (with or without its " \
                       "`index.md`). It names one directory segment either way, so a substring " \
                       "of a board line is not one. `okf pro state` lists the open ones."

      def close(argv, stdout: $stdout, stderr: $stderr)
        selector_verb("close", argv, stdout, stderr, missing: CLOSE_ARGUMENT) { |root, slug| Writes.close(root, slug) }
      end

      SELECTOR_ARGUMENT = "takes what to act on: a `/projects/<slug>` link, a slug, or a " \
                          "substring only one board line carries. `okf pro board` lists them."

      def selector_verb(verb, argv, stdout, stderr, missing: SELECTOR_ARGUMENT)
        answered = writer_flags(argv, verb, stdout, stderr)
        return answered == :handled ? PASS : BLOCK unless answered == :ok

        selector = argv.shift
        if selector.nil?
          stderr.puts "okf pro #{verb} — #{missing}"
          return BLOCK
        end

        write_verb(verb, argv, stdout, stderr) { |root| yield(root, selector) }
      end

      # The writers take no flags, and that is precisely why they need this.
      #
      # Their first positional is CONTENT — the words to capture, the line to
      # move — so a mistyped or misremembered flag is not an error, it is data:
      # `okf pro capture --help` appended `- <date> — --help` to the Inbox and
      # exited 0. A verb whose failure mode is committing a garbage board line
      # must refuse a leading dash rather than swallow it.
      #
      # `--help` and `--version` are answered because every other verb answers
      # them, and `--` is the POSIX escape for the rare legitimate case of
      # content that really does begin with a dash.
      #
      # Returns `:ok` to carry on, `:handled` when the caller has been answered,
      # or nil on a refusal already reported.
      def writer_flags(argv, verb, stdout, stderr)
        first = argv.first.to_s
        return help_answer(stdout) if HELP.include?(first)
        return version_answer(stdout) if VERSION_FLAGS.include?(first)

        if first == "--"
          argv.shift
          return :ok
        end
        return :ok unless first.start_with?("-")

        stderr.puts "okf pro #{verb} — '#{first}' looks like a flag, and this verb takes none: its " \
                    "first argument is content, so a flag swallowed here becomes a board line " \
                    "nobody meant to write. If you really meant to #{verb} something starting with " \
                    "a dash, put `--` in front of it."
        nil
      end

      # The shape every writer shares: resolve, run, print, choose the code.
      # The write itself never happens here — `Writes` runs the conservation
      # guard and refuses before touching the disk, so this method cannot make
      # a partial write even by getting the ordering wrong.
      def write_verb(verb, argv, stdout, stderr)
        root = bundle_for(argv, verb, stderr)
        return BLOCK if root.nil?

        result = guarded(verb, stderr) { yield(root) }
        return BLOCK if result.nil?

        if result.ok
          stdout.puts result.messages unless result.messages.empty?
          return PASS
        end

        stderr.puts result.messages
        BLOCK
      end

      # ── the shared plumbing ──────────────────────────────────────────────

      # Parsed BEFORE `dir_argument`, which refuses any second positional and
      # would otherwise report `okf pro state . --json` as two directories.
      #
      # `--help` and `--version` are declared rather than left to OptionParser's
      # "officious" defaults, which call `exit` from inside the parse — a
      # process exit out of a library call, in a gem whose whole subject is
      # which exit code a gate returns.
      #
      # Returns the options Hash, `:help` when the caller asked for the usage,
      # or nil on a parse error already reported.
      def parse_flags(argv, verb, stdout, stderr)
        options = { json: false, pretty: false, full: false, issue: false, clear: false, section: nil }
        allowed = FLAGS.fetch(verb, [])
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf pro #{verb} [DIR]"
          o.on("--json") { options[:json] = true } if allowed.include?(:json)
          o.on("--pretty") { options[:json] = options[:pretty] = true } if allowed.include?(:pretty)
          o.on("--full") { options[:full] = true } if allowed.include?(:full)
          o.on("--issue") { options[:issue] = true } if allowed.include?(:issue)
          o.on("--clear") { options[:clear] = true } if allowed.include?(:clear)
          o.on("--section NAME") { |value| options[:section] = value } if allowed.include?(:section)
          o.on("-h", "--help") { options[:help] = true }
          o.on("-v", "--version") { options[:version] = true }
        end
        parser.parse!(argv)
        return version_answer(stdout) if options[:version]
        return help_answer(stdout) if options[:help]

        options
      rescue OptionParser::ParseError => e
        stderr.puts "okf pro #{verb} — #{e.message}. `okf pro --help` lists what each verb takes."
        nil
      end

      # Not the options Hash and not nil: the caller has already been answered,
      # and there is nothing left to do but exit 0.
      def help_answer(stdout)
        usage(stdout, PASS)
        :handled
      end

      def version_answer(stdout)
        stdout.puts VERSION
        :handled
      end

      def emit(stdout, options, payload)
        if options[:json]
          stdout.puts(options[:pretty] ? JSON.pretty_generate(payload) : JSON.generate(payload))
        else
          stdout.puts yield
        end
      end

      # A verb that cannot run exits 2, never 1 — 1 means findings, and a
      # pipeline that cannot tell a broken bundle from a broken checker learns
      # to ignore both. The same reasoning `audit` states at length.
      def guarded(verb, stderr)
        yield
      rescue StandardError => e
        stderr.puts "okf pro #{verb} — could not run (#{e.class}: #{e.message}); nothing was " \
                    "read or written. Exit 2, for the reason `audit` gives."
        nil
      end

      def bundle_for(argv, verb, stderr)
        start = dir_argument(argv, verb, stderr)
        return nil if start == REFUSED

        resolve_or_complain(start, verb, stderr)
      end

      def bundle_with_board(argv, verb, stderr)
        root = bundle_for(argv, verb, stderr)
        return nil if root.nil?
        return root if File.exist?(File.join(root, "board.md"))

        stderr.puts "okf pro #{verb} — #{root} has no board.md to read."
        nil
      end

      def scaffold(verb, argv, stdout: $stdout, stderr: $stderr)
        dest = argv.shift

        unless argv.empty?
          stderr.puts "okf pro #{verb} — takes one directory, and #{argv.size + 1} were given."
          return BLOCK
        end

        if verb == "skill"
          if dest.nil?
            stderr.puts "okf pro skill — needs a destination directory: `okf pro skill .claude/skills/okf-pro`."
            return BLOCK
          end
        else
          dest ||= Dir.pwd
        end

        if dest.to_s.start_with?("@")
          stderr.puts "okf pro #{verb} — '#{dest}' is a registry ref, and this verb takes a path. " \
                      "The registry names where a bundle is; this writes a repository around one."
          return BLOCK
        end

        Scaffold.public_send(verb, dest, out: stdout, err: stderr)
      end

      # The command list, plus the two things that surprise people — a ref is not
      # a path here, and `hook` does not speak this repo's exit codes. Both cost
      # something when they surprise someone, which is why they are in the usage
      # rather than only in the guide.
      def usage(stream, status)
        width = USAGE.map { |verb, arg, _| "#{verb} #{arg}".length }.max
        stream.puts "Usage: okf pro <command> [DIR]"
        stream.puts
        USAGE.each do |verb, arg, description|
          stream.puts format("  %-#{width}s   %s", "#{verb} #{arg}", description)
        end
        stream.puts
        stream.puts "  hook checks: #{HOOK_NAMES.first(5).join(", ")},"
        stream.puts "               #{HOOK_NAMES.drop(5).join(", ")}"
        stream.puts
        stream.puts "Flags:"
        FLAGS.each do |verb, flags|
          stream.puts format("  %-#{width}s   %s", verb, flags.map { |flag| FLAG_HELP.fetch(flag) }.join(" "))
        end
        stream.puts "  --pretty implies --json. `audit` and `records` take none — what they answer"
        stream.puts "  with is the exit code. The writers take no flags at all either: their first"
        stream.puts "  argument is content, so `--` is what escapes content that starts with a dash."
        stream.puts
        stream.puts "DIR takes a path, not an @slug: the registry names where a bundle is, and a"
        stream.puts "brain is the repository around one — the hooks, the git hooks, the workflow."
        stream.puts
        stream.puts "Exit codes: `hook` speaks the agent hook protocol — 0 pass, 2 block, and never"
        stream.puts "1, which that protocol reads as non-blocking. Every other command: 0 clean,"
        stream.puts "1 findings, 2 could not run."
        stream.puts
        stream.puts "okf pro --version"
        status
      end

      # Every bundle-taking verb reads one directory and nothing else.
      #
      # A leading `@` is refused by name rather than treated as a path. `okf
      # help` promises "Anywhere a `<dir>` goes, an `@slug` goes", and that
      # promise is the kernel's; this gem does not keep it yet, and okf-tui
      # already shipped the failure of pretending otherwise — a ref reached the
      # filesystem and came back "not a directory", which tells the user nothing
      # about what is actually missing.
      #
      # A second positional is refused for the reason ../AGENTS.md records
      # against `okf lint a b`: silently reading the first and ignoring the rest
      # is a wrong answer with a green exit code.
      def dir_argument(argv, verb, stderr)
        start = argv.shift

        unless argv.empty?
          stderr.puts "okf pro #{verb} — takes one directory, and #{argv.size + 1} were given " \
                      "(#{([ start ] + argv).join(" ")}). Reading the first and ignoring the rest " \
                      "would be a wrong answer with a clean exit code."
          return REFUSED
        end

        if start.to_s.start_with?("@")
          stderr.puts "okf pro #{verb} — '#{start}' is a registry ref, and this verb takes a " \
                      "path. The registry answers where a bundle is; a brain is the repository " \
                      "around one, which a ref does not name. Give the directory."
          return REFUSED
        end

        start
      end

      def resolve_or_complain(start, verb, stderr)
        root = BundleRoot.resolve(start || Dir.pwd)
        if root.nil?
          stderr.puts "okf pro #{verb} — #{File.expand_path((start || Dir.pwd).to_s)} holds no OKF bundle."
        end
        root
      end

      # The one check that does not refuse. Its output is context, not a verdict,
      # and SessionStart has no blocking channel — so it says what it could not
      # do and lets the session start.
      def session_context(stdin, stdout: $stdout)
        event = Event.from_stdin(stdin)
        if event.parse_error?
          stdout.puts "Bundle state unavailable — #{event.parse_error}. " \
                      "The gates still run; only this banner is blind."
          return PASS
        end

        lines = Closing.session_context(event)
        stdout.puts lines if lines
        PASS
      end
    end
  end
end
