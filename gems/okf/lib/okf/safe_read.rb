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
  #
  # Scope. This closes the escape a *symlink* opens — the one a bundle can carry
  # through a git clone, a copy or a tarball, which is the portable, adversarial
  # case (a shared bundle whose author points a link at your secrets). It does
  # not close a *hardlink*: File.realpath cannot resolve one (a hardlink shares
  # its target's inode and keeps its own in-root path), and the obvious guard —
  # rejecting st_nlink > 1 — would break a bundle on a deduplicating filesystem
  # (a Nix store, some CI caches) where ordinary files legitimately share links.
  # A hardlink to an outside file requires local write access to the served
  # directory on the target's own filesystem, and cannot survive being copied,
  # so it is a narrower, non-portable threat left deliberately out of scope.
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

    # +path+'s bytes, read from its *resolved* location — so a symlink swapped in
    # anywhere but the final component is caught, since the resolved path has no
    # links left to follow — and refused if it escapes. The microscopic window
    # between resolving and opening the leaf is not closed here (that needs an
    # open-by-descriptor the 2.4 stdlib does not lend itself to); reading the
    # resolved path is strictly better than reading the caller's raw name, which
    # re-followed every link on every read.
    def read!(root, path, real_root: nil, encoding: "UTF-8")
      ::File.read(contained_path!(root, path, real_root: real_root), encoding: encoding)
    end
  end
end
