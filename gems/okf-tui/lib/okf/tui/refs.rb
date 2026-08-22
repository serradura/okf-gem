# frozen_string_literal: true

require "okf/cli"

module OKF
  module TUI
    # argv → bundle directories, through okf's ref grammar rather than a second
    # copy of it.
    #
    # `okf-tui @okf @mkt ./docs` has to mean exactly what `okf server @okf @mkt
    # ./docs` means: bare `@` is the registry default, `@slug` is a registered
    # bundle, `@group` fans out to its members, a member whose directory has
    # vanished is skipped with a note, `@all` is refused by name, and anything
    # else is a directory on disk. That grammar is okf's — its precedence, its
    # messages, its exit codes — and this class exists so there is one copy of it
    # rather than a faithful-until-it-drifts imitation.
    #
    # It subclasses Command for the resolver, not to be a verb. Nothing registers
    # it, so it can never answer to one; `.id` is defined only because Command
    # declares it abstract. The helpers it leans on are private, which is
    # Command's way of saying "not a verb" ("#call is the entire public surface,
    # so a helper added below can never become a verb by accident") rather than
    # "not for subclasses" — but they are still okf's internals, so
    # test/integration/refs_test.rb pins the seam by name. If okf renames it, that
    # test says so, instead of every `@slug` quietly going back to reading as
    # "not a directory".
    #
    # Resolution is also what opts the TUI into registry discovery: Command's
    # `open_registry` is `OKF::Registry.load(cwd: Dir.pwd)`, so a `@slug` here
    # means the same bundle it means to every other okf verb run from the same
    # directory — the project-local `.okf.json` when there is one on the
    # path up, the global `$OKF_HOME` registry otherwise.
    class Refs < OKF::CLI::Command
      def self.id
        :"tui-refs"
      end

      # The resolved directories in argv order, groups fanned out — or nil, after
      # okf has already reported why on the error stream, so the caller returns
      # its usage-error status exactly as `okf server` does.
      #
      # An empty argv resolves to an empty list rather than nil: naming no bundle
      # is not a failed ref, it is the registry-backed session.
      def resolve(argv)
        dirs = Array(argv).flat_map { |arg| resolve_ref_expanding(arg) }
        dirs.include?(nil) ? nil : dirs
      end

      # Which registered slug each resolved directory came from, keyed by
      # directory — empty for plain directory arguments.
      #
      # Without this a ref-built session names bundles after their folders, and
      # the folder is `.okf` for every bundle that follows the convention: `okf-tui
      # @okf-site @okf-mkt` would list `@okf` and `@okf-2`, having thrown away the
      # two names the user actually typed. okf hit this in the hub and fixed it the
      # same way — "so a hub built from refs mounts each bundle under its
      # registered slug, not its dir basename".
      def slugs
        ref_slugs
      end
    end
  end
end
