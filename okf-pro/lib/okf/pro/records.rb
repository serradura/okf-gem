# frozen_string_literal: true

module OKF
  module Pro
    # The append-only record, checked against git rather than against a tool
    # event.
    #
    # `Guards.journal_guard` refuses an edit to a past day at the agent's
    # tool boundary, which is the right place to catch it and the wrong place
    # to rely on: it reads a PreToolUse event, so it sees Edit and Write and
    # nothing else. A shell redirect, an editor, a patch — none of them
    # produce the event, and the record they rewrite is exactly the artefact
    # nobody can reconstruct afterwards.
    #
    # This asks the same question of the index, where the answer does not
    # depend on which tool made the change: does this commit modify or delete
    # a journal day that already exists in HEAD, and is that day in the past?
    # Only additions and today's entry survive. It runs at the commit door,
    # which every path to history goes through.
    module Records
      JOURNAL_ENTRY = %r{journal/(\d{4}-\d{2}-\d{2})\.md\z}.freeze

      module_function

      # Findings, or []. `root` is the repository — this reads the index, not
      # a materialised tree, because the question is about a change rather
      # than a state.
      def staged_violations(root, today: Date.today)
        status = staged_status(root)
        return status[:findings] unless status[:findings].empty?

        status[:entries].map do |mode, path|
          match = path.match(JOURNAL_ENTRY)
          next unless match

          day = match[1]
          next unless day < today.to_s

          verb = VERBS.fetch(mode[0, 1], "modifies")
          "  records  this commit #{verb} #{path}, a past day that already exists in HEAD. " \
            "Records are append-only; corrections go in today's entry, pointing back."
        end.compact
      end

      # What the status letter did to the day, in the words a refusal needs. A
      # typechange is its own verb because it is its own act: the day's content
      # is not edited, it is replaced wholesale by a link somewhere else.
      VERBS = { "D" => "deletes", "T" => "replaces" }.freeze

      # Modified, deleted, renamed and TYPECHANGED paths in the index, against
      # HEAD. Additions are absent by construction — a day being written for
      # the first time is the reconstruction the journal guard already routes
      # to the owner, and this door does not second-guess an approval it cannot
      # see.
      #
      # `T` was absent and is the worst omission of the four: replacing a
      # committed past day with a symlink stages as a typechange, never as `M`
      # or `D`, so the gate reported "append-only" and the commit destroyed the
      # one artefact this module exists to protect. The filter is a whitelist,
      # so every letter it does not name fails OPEN — which is why it is named
      # here with its reason rather than left to be re-derived.
      def staged_status(root)
        out = IO.popen(
          [ "git", "-C", root, "diff", "--cached", "--name-status", "--diff-filter=MDRT" ],
          err: File::NULL, &:read
        )
        # A git that could not answer is not an empty answer. The commit door
        # refuses what it cannot check, exactly as dirty_markdown? does.
        unless $?.success?
          return { findings: [ "  records  git could not report the staged changes, so the " \
                               "append-only record could not be checked. The commit is refused " \
                               "rather than waved through." ], entries: [] }
        end

        entries = out.to_s.each_line.map do |line|
          mode, *paths = line.strip.split("\t")
          next if mode.nil? || paths.empty?

          # A rename reports source and destination; the source is the one
          # leaving its place.
          [ mode, paths.first ]
        end.compact
        { findings: [], entries: entries }
      rescue Errno::ENOENT
        { findings: [ "  records  git is not available, so the append-only record could not be " \
                      "checked. The commit is refused rather than waved through." ], entries: [] }
      end
    end
  end
end
