# frozen_string_literal: true

module OKF
  module Pro
    # The CI door: the same invariants the hooks enforce, minus the ones that
    # need a tool event.
    #
    # It exists because hooks fire only at the agent's tool boundary — an edit
    # made in a text editor reaches the repo unchecked. The snapshot check asks
    # whether the *newest* day in the log carries one, not today's: CI runs on a
    # push, which can land on a day nobody worked, and a gate that fails on the
    # calendar teaches people to ignore it.
    module Audit
      module_function

      # Takes a repository root or a bundle root; both resolve. CI runs it as
      # `okf pro audit .` from the top of the checkout, which is neither
      # more nor less correct than naming `.okf` — the caller should not have
      # to know the layout to ask whether the bundle is sound.
      def call(start)
        root = BundleRoot.resolve(start)
        if root.nil?
          return [ "#{File.expand_path(start.to_s)} holds no OKF bundle — no index.md, and none in .okf/." ]
        end

        bundle = ::OKF::Bundle::Reader.read(root)
        findings = ambiguous_layout(start, root).map { |m| "  layout    #{m}" } +
                   structure(root).map { |m| "  structure #{m}" } +
                   conformance(bundle) + curation(bundle) + snapshot(root)
        # Budget and pairing read the board; with the board gone the structure
        # finding is the whole story, and a crash would bury it. The board is
        # read once and the bundle parsed once, here — Rule 3 goes through
        # Budget.check_text (the same code the cap-check hook runs, so the
        # doors cannot drift apart), and pairing reuses both reads.
        board_path = File.join(root, "board.md")
        if File.exist?(board_path)
          board = Pro.read_text(board_path)
          findings += Budget.check_text(board).map { |m| "  budget    #{m}" }
          findings += Board.grammar(board).map { |m| "  board     #{m}" }
          findings += pairing(root, board: board, concepts: bundle.concepts)
        end
        findings
      end

      # Two bundles in one directory — a flat root that also parents an
      # `.okf` root. The doors disagree there by construction: the trust
      # guards govern a file outside `.okf` by the flat root (a root that
      # does not contain the file is no root of it), while this audit and
      # the stop gate govern `.okf`. Neither choice is wrong; the LAYOUT
      # is, and a disagreement nobody is told about is the silent failure
      # the contract forbids. Mid-migration is the honest case, and the
      # answer is the same: finish the move.
      def ambiguous_layout(start, root)
        base = File.expand_path(start.to_s)
        return [] unless root == File.join(base, BundleRoot::DIR)
        return [] if BundleRoot.root_kind(base).nil?

        [ "#{base} is a bundle AND holds a bundle at #{BundleRoot::DIR}/ — two roots, one " \
          "directory. Files outside #{BundleRoot::DIR}/ are guarded against the outer one and " \
          "audited against the inner: the doors disagree until one of the two is retired." ]
      end

      # The closed core. `okf validate` knows nothing of these — they are the
      # method's skeleton, not the format's — and a bundle missing one is not a
      # leaner bundle, it is a broken one: without them the gates disengage in
      # silence, which is the one failure the contract forbids. roadmap.md is
      # deliberately absent from this list — it is the one file the design lets
      # an adopter delete, by its own standing accusation.
      CORE = [
        [ "board.md",        "the one page of state" ],
        [ "log.md",          "delta memory, where the snapshot lands" ],
        [ "journal/",        "the backward record" ],
        [ "areas/corpus.md", "the standard this corpus is kept at" ]
      ].freeze

      def structure(root)
        CORE.map do |rel, why|
          path = File.join(root, rel)
          present = rel.end_with?("/") ? File.directory?(path) : File.file?(path)
          next if present

          "#{rel} is missing — #{why}. The core is closed; only roadmap.md is deletable."
        end.compact
      end

      # Errors AND warnings. Returning early on `valid?` dropped every soft
      # finding the validator made — and `Conformance`, the hook door, reports
      # them (`warn_lines`) for a reason it states at length: a scalar
      # `verified: human:rod` is conformant, so the attestation guard asks, the
      # owner approves, and the reader then drops the malformed value while the
      # trust tier stays `unverified` forever. Caught at the agent's tool
      # boundary and waved through here, which is the door an edit made in an
      # editor takes, and the door `pre-commit` runs.
      #
      # A warning is a finding at this door, the same as a linter warning
      # already is: `curation` below reads `.warnings` and this verb exits 1 on
      # them. The two channels answering differently about the same bundle was
      # the inconsistency, not the severity.
      def conformance(bundle)
        result = ::OKF::Bundle::Validator.call(bundle)
        result.errors.map { |e| "  validate  #{e[:path]}: #{e[:message]}" } +
          result.warnings.map { |w| "  validate  #{w[:path]}: #{w[:message]} (#{w[:check]})" }
      end

      # The linter, run the way `Conformance` runs it, and for the same reason
      # stated there at length: a bare `Linter.call(bundle)` cannot run
      # `expired` (no clock) or `stale` (no cutoff), and reports `healthy?`
      # anyway. Measured on this door before this line existed:
      # `skipped_checks: [:expired, :stale]`, and `okf pro audit — clean.` The
      # hook door supplied the clock and excluded `stale` in source; this one
      # did neither, so one clause was kept at one door and broken at the other.
      #
      # Separate from `curation` so the residue can be asserted directly rather
      # than inferred from the findings — the check that this check ran.
      def linted(bundle)
        ::OKF::Bundle::Linter.call(bundle, today: Date.today, except: [ :stale ])
      end

      def curation(bundle)
        report = linted(bundle)
        report.warnings.map { |w| "  lint      #{w[:path]}: #{w[:message]} (#{w[:check]})" } +
          confession(report)
      end

      # The guard on the guard. `stale` is excluded in source with its reason,
      # so this is empty in normal operation — and stays a live guard for the
      # day okf adds a third clock-gated check, which would otherwise go
      # unchecked here in silence.
      def confession(report)
        skipped = Array(report.stats[:skipped_checks])
        return [] if skipped.empty?

        [ "  lint      okf lint could not run #{skipped.join(", ")} on this bundle, so those are " \
          "unchecked rather than clean." ]
      end

      def snapshot(root)
        path = File.join(root, "log.md")
        return [] unless File.exist?(path)

        text = Pro.read_text(path)
        # A heading the calendar rejects is a day no check will ever look
        # under — said here, because days() skipping it in silence is how a
        # one-digit typo would orphan an entry forever.
        findings = Log.malformed_days(text).map do |day|
          "  snapshot  log.md heading '## #{day}' is not a calendar date — nothing will ever check under it."
        end
        newest = Log.newest_day(text)
        unless newest.nil? || Log.snapshot_under?(text, newest)
          findings << "  snapshot  log.md's newest day (#{newest}) carries no Snapshot line."
        end
        findings
      end

      def pairing(root, board:, concepts:)
        Pairing.failures(root, board: board, concepts: concepts)
               .map { |m| "  pairing #{m.sub(/\A— pairing:/, "")}" }
      end
    end
  end
end
