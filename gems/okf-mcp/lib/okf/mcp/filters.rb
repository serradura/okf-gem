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
    # There are genuinely **two** rules here, and the distinction is not drift.
    # Only one of them still lives in this file:
    #
    #   concepts     are filtered by `Bundle::RowFilter`, the kernel's one
    #                catalog-row predicate — a dir names itself and everything
    #                beneath it, and `.` is a prefix of nothing, so the root
    #                selects only what lives directly in it (the CLI's `--dir`).
    #                This module's job there is #normalize_dir, the spelling
    #                fold the kernel deliberately does not do.
    #   #within?     scopes a *tree* of directory rows, where the root is the
    #                ancestor of every row (`dirs`/`index` walking down). The
    #                kernel has no view of a directory tree, so this one stays.
    module Filters
      module_function

      def fold(value)
        value.to_s.downcase
      end

      # A `dir` argument as the tools compare it: case-folded, trailing slashes
      # gone, and both spellings of the bundle root — "." and "/" — normalized
      # to ".".
      #
      # A *blank* argument never reaches here as a filter. Every concept filter
      # short-circuits on `OKF.blank?` first, because a client that fills each
      # declared optional property with "" is doing something routine and means
      # "no filter" by it — so "" and an omitted `dir` are the same ask, and
      # neither is a synonym for the root. In the tree scoping the two coincide
      # anyway: `.` is the ancestor of every row, so a blank normalizes to "."
      # and selects the whole tree.
      #
      # Deliberately **not** the CLI's `fold_dir`, which also folds the literal
      # name "root". Its whole rationale there is that a shell needs no quoting
      # for it; a JSON argument has no such problem, and no `dir` description on
      # this surface ever advertised the spelling. Importing it cost a bundle
      # with a real `root/` directory the ability to name it — `dir: "root"`
      # answered for the bundle root instead, and `scoped_rows` skips its
      # existence check for the root, so not even the refusal fired.
      def normalize_dir(value)
        folded = fold(value).sub(%r{/+\z}, "")
        folded.empty? || folded == "." ? "." : folded
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

      # Is +wanted+ a directory this set actually has? Folded, and blind to a
      # trailing slash, so it accepts the spelling the views print back.
      def known_dir?(dirs, wanted)
        base = normalize_dir(wanted)
        return true if base == "."

        dirs.any? { |dir| fold(dir) == base }
      end
    end
  end
end
