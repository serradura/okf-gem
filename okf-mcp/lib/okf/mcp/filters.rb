# frozen_string_literal: true

module OKF
  module MCP
    # The `dir` vocabulary, in one place.
    #
    # It lived in two — one copy in the server, one in the memory backend, each
    # commented "the CLI's one rule kept verbatim" — and they drifted: only one
    # of them mapped `""` and `"/"` onto the root, so `catalog(dir: "/")`
    # reported an empty bundle root while `search` and `dirs` answered for it.
    # Two copies of a rule is two answers waiting to disagree, so there is one.
    #
    # There are genuinely **two** rules here, and the distinction is not drift:
    #
    #   #under_dir?  filters *concepts*. A dir names itself and everything
    #                beneath it; `.` is a prefix of nothing, so the root
    #                selects only what lives directly in it (the CLI's `--dir`).
    #   #within?     scopes a *tree* of directory rows, where the root is the
    #                ancestor of every row (`dirs`/`index` walking down).
    module Filters
      module_function

      def fold(value)
        value.to_s.downcase
      end

      # A `dir` argument as the tools compare it: case-folded, trailing
      # slashes gone, and every spelling of the bundle root — "", ".", "/",
      # "root" — normalized to ".".
      def normalize_dir(value)
        folded = fold(value).sub(%r{/+\z}, "")
        folded.empty? || folded == "." || folded == "root" ? "." : folded
      end

      # Concept filtering: `dir` names itself and everything beneath it.
      def under_dir?(entry_dir, wanted)
        entry = fold(entry_dir)
        path = normalize_dir(wanted)
        entry == path || entry.start_with?("#{path}/")
      end

      # Tree scoping: the root is the ancestor of every row, so `.` selects
      # the whole tree rather than only what sits directly in it.
      def within?(entry_dir, base)
        return true if base == "."

        entry = fold(entry_dir)
        entry == base || entry.start_with?("#{base}/")
      end

      def dir_depth(dir)
        dir == "." ? 0 : dir.split("/").length
      end
    end
  end
end
