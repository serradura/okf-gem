# frozen_string_literal: true

require_relative "path"

module OKF
  # Shell-side containment for reads. `Path.under?` is the pure decision; the
  # `File.realpath` that feeds it is disk I/O, so it lives here, out of the pure
  # core. Every byte a bundle serves is read through this one primitive — the
  # Reader's bulk load, `Concept::File`, the live `log.md` re-read, the MCP
  # shell's concept and index reads — so a symlink whose name sits inside the
  # root but whose target does not is refused in exactly one place. A read that
  # rolled its own check could quietly drift and reopen the escape; there is
  # nothing to drift from here.
  module SafeRead
    module_function

    # The file's real, symlink-resolved location, or Path::Error if it escapes
    # +root+. Pass +real_root+ when resolving many paths under one root (the
    # Reader's loop) so the root is resolved once, not per file.
    def contained_path!(root, path, real_root: nil)
      real = ::File.realpath(path)
      real_root ||= ::File.realpath(root)
      raise Path::Error, "symlink target escapes bundle root" unless Path.under?(real_root, real)

      real
    end

    # +path+'s bytes, read from its *resolved* location so the containment check
    # and the open cannot disagree across a swap, and refused if it escapes.
    def read!(root, path, real_root: nil, encoding: "UTF-8")
      ::File.read(contained_path!(root, path, real_root: real_root), encoding: encoding)
    end
  end
end
