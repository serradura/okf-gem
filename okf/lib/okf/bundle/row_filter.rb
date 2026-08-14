# frozen_string_literal: true

module OKF
  class Bundle
    # The one catalog-row predicate every narrowing surface shares — the CLI's
    # filter flags, the MCP shell's catalog filters, and its search narrowing
    # select rows by these rules and no other copy of them. The seam earned the
    # module: the predicate was hand-spelled in three shells with only the leaf
    # folds shared, and the copies diverged three recorded times (a raw status
    # compare answering the opposite of `--status stable`, "" meaning no-filter
    # on one tool and match-nothing on the next, the root's spellings).
    #
    # Callers hand it *normalized* wants — nil means "no filter", and `dir`
    # arrives as a folded base path ("." for the bundle root) — because
    # argument spelling is each shell's own: the CLI folds the `root` alias
    # against the bundle's real directories, the MCP shell maps ""/"/" onto
    # ".", and neither belongs here. Pure, like everything beside it.
    module RowFilter
      module_function

      def matches?(row, type: nil, dir: nil, tag: nil, status: nil, trust: nil)
        (type.nil? || fold(row[:type]) == fold(type)) &&
          (dir.nil? || under_dir?(row[:dir], dir)) &&
          (tag.nil? || Array(row[:tags]).any? { |value| fold(value) == fold(tag) }) &&
          (status.nil? || Concept.effective_status(row[:status]) == Concept.fold_status(status)) &&
          (trust.nil? || fold(row[:trust]) == Concept.fold_tier(trust))
      end

      # The one rule `--dir` is built on: a dir names itself and everything
      # beneath it; "." is a prefix of nothing, so the root selects only what
      # lives directly in it.
      def under_dir?(entry_dir, base)
        entry = fold(entry_dir)
        path = fold(base)
        entry == path || entry.start_with?("#{path}/")
      end

      def fold(value)
        value.to_s.downcase
      end
    end
  end
end
