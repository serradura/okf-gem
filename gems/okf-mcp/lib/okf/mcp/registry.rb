# frozen_string_literal: true

require "okf/registry"

module OKF
  module MCP
    # The allowlist of bundles the server may touch, and the one place bundle
    # identity is decided. Every tool takes a `bundle` argument that is a
    # registry slug — the same identity `@slug` resolves at the CLI and
    # `/b/<slug>/` mounts on the hub — and that slug is only ever a key into
    # this map: no tool opens an arbitrary path from a request.
    #
    # Two boots. Argv roots are the allowlist: `okf-mcp <dir> [<dir>…]` serves
    # exactly those, slugged by the kernel's own normalization (a leading `@`
    # names a registered bundle or group, whose slug is reserved before any
    # plain-dir basename is deduped — the server verb's rule). No argv means
    # the active kernel registry, resolved exactly as the CLI resolves it:
    # a project-local .okf.json discovered from cwd, else
    # $OKF_HOME/registry.json, OKF_NO_DISCOVERY=1 forcing global.
    class Registry
      # One served bundle: the +slug+ tools name it by, its absolute +root+ on
      # disk, and the human +title+ ("parent/dir").
      Entry = Struct.new(:slug, :root, :title)

      class << self
        # Boot from explicit argv roots — directories and @refs, mixed. Raises
        # Error on anything unresolvable; vanished group members are skipped
        # with a note in #boot_notes (asking for a set tolerates gaps, naming
        # one bundle demands it).
        def from_argv(args)
          notes = []
          kernel = nil
          ref_slugs = {}
          roots = []
          Array(args).each do |arg|
            kernel ||= kernel_registry if arg.start_with?("@")
            resolve_arg(arg, kernel, ref_slugs, notes).each do |root|
              roots << root unless roots.include?(root)
            end
          end
          raise Error, "no bundle roots given" if roots.empty?

          # The kernel registry is deliberately **not** carried into the
          # instance. It answered the @refs above, at boot, where the operator
          # asked for them — keeping it would leave a request-time door into
          # every bundle argv did not name: a group slug passed to `search`
          # expanded through it and returned content from bundles outside the
          # allowlist. Argv names the served set; groups are a registry-mode
          # identity, and in argv mode they already fanned out to their leaves.
          new(mint_entries(roots, ref_slugs), source: kernel&.path, notes: notes)
        end

        # Boot from the active kernel registry — the no-argv default.
        def from_kernel
          kernel = kernel_registry
          if kernel.empty?
            raise Error, "no bundle roots given and no bundles registered — run `okf registry set <dir>` (registry: #{kernel.path})"
          end

          entries = kernel.map { |entry| Entry.new(entry.slug, entry.path, entry.title) }
          new(entries, kernel: kernel, source: kernel.path, notes: [])
        end

        private

        # The registry the CLI would resolve: discovery on, from the process cwd.
        def kernel_registry
          OKF::Registry.load(cwd: Dir.pwd)
        end

        # One argv item to its absolute roots. A plain directory must exist; a
        # ref resolves through the kernel registry — a group fans out to its
        # member bundles here at boot, each keeping its registered slug.
        def resolve_arg(arg, kernel, ref_slugs, notes)
          return [ expand_dir(arg) ] unless arg.start_with?("@")

          asked = arg[1..]
          slug = OKF::Registry.normalize(asked)
          return group_roots(kernel, slug, ref_slugs, notes) if !slug.empty? && kernel.group?(slug)

          entry = ref_entry(kernel, asked, slug)
          raise Error, "#{entry.path} (registered as #{entry.slug}) is not a directory (okf registry list)" unless File.directory?(entry.path)

          ref_slugs[entry.path] = entry.slug
          [ entry.path ]
        end

        def expand_dir(arg)
          raise Error, "no such directory: #{arg}" unless File.directory?(arg)

          File.expand_path(arg)
        end

        # "@" is the registry's default; "@slug" is a lookup that fails hard —
        # an explicit ask is never a silent skip.
        def ref_entry(kernel, asked, slug)
          entry = if asked.empty?
                    kernel.default or raise Error, "no default bundle: the registry is empty (okf registry set <dir>)"
                  elsif slug.empty?
                    nil
                  else
                    kernel.get(slug)
                  end
          entry or raise Error, "unknown ref @#{asked} (okf registry list; registry: #{kernel.path})"
        end

        # A group's member bundles, recursively and path-deduped by the kernel;
        # a vanished member is skipped with a note, an empty result is an error.
        def group_roots(kernel, slug, ref_slugs, notes)
          roots = []
          kernel.expand(slug).each do |entry|
            if File.directory?(entry.path)
              ref_slugs[entry.path] = entry.slug
              roots << entry.path
            else
              notes << "skipped #{entry.slug}: #{entry.path} is gone (okf registry list)"
            end
          end
          raise Error, "@#{slug} resolves to no readable bundle (okf registry list)" if roots.empty?

          roots
        end

        # A registered slug owns its name outright: every ref's slug is
        # reserved before any basename is deduped, so argv order cannot push a
        # registered bundle off its own slug (the server verb's rule).
        def mint_entries(roots, ref_slugs)
          taken = roots.map { |root| ref_slugs[root] }.compact
          roots.map do |root|
            slug = ref_slugs[root]
            unless slug
              slug = OKF::Registry.dedupe(File.basename(root), taken)
              taken << slug
            end
            Entry.new(slug, root, Bundle::Folder.label(root))
          end
        end
      end

      # +kernel+ stays only for what an allowlist cannot answer alone — group
      # membership — and +source+ names the registry file the boot line reports.
      def initialize(entries, kernel: nil, source: nil, notes: [])
        @entries = entries
        @kernel = kernel
        @source = source
        @notes = notes
        @mutex = Mutex.new
        # Deliberately *not* stamped here. A stamp is a claim about a file this
        # instance has already read, and the boot read happened before this
        # constructor ran — so a stat taken now would record a write that
        # landed in between as already-seen: entries from before it, fingerprint
        # from after, and #refresh! with nothing to do until some further write
        # moves the fingerprint again. Resolving the path to stat it ahead of
        # the read would mean reimplementing the kernel's discovery precedence
        # here, so the first #refresh! re-reads instead — one parse, once per
        # process, in exchange for never holding a fingerprint the entries do
        # not match. #refresh! itself already stats before it reopens.
        @stamp = nil
      end

      attr_reader :source

      # The served set, re-read when the registry file moves underneath it.
      #
      # This is the same rule the residency layer applies to bundle *contents*,
      # applied to the identity map — one `stat`, and a parse only when the
      # fingerprint has changed. It was a boot snapshot, which the kernel's own
      # hub also is for what it mounts; three of the four ways that went stale
      # were loud (an unknown slug names what it knows), but the fourth was
      # not: an entry repointed at a new directory kept answering from the old
      # one under the current slug, which is a silent wrong answer.
      #
      # Argv mode is untouched, and not by a flag: it never carried the kernel
      # registry into the instance, so there is nothing here to re-read and no
      # way for the served set to widen. Containment stays a property of the
      # shape.
      def entries
        refresh!
        @entries
      end

      # Every reader goes through #entries or #refresh! so a caller cannot
      # accidentally answer from the stale copy; the `stat` is a couple of
      # microseconds, so no request-scoped memo earns its complexity here.

      # Boot-time skips (a group member whose directory is gone) for the CLI to
      # print; tools never see them.
      def boot_notes
        @notes
      end

      def slugs
        entries.map(&:slug)
      end

      # The kernel's rule: the first entry still on disk, else the first.
      def default_slug
        rows = entries
        chosen = rows.find { |entry| File.directory?(entry.root) } || rows.first
        chosen&.slug
      end

      # The registered groups, for list_bundles — [] when the allowlist came
      # from argv, where groups fanned out to their leaves at boot.
      def groups
        refresh!
        @kernel.nil? ? [] : @kernel.groups_listing
      end

      def group?(slug)
        refresh!
        return false if @kernel.nil?

        !@kernel.group?(slug).nil?
      end

      # The root behind one named slug — the resolution every single-bundle tool
      # goes through. Naming demands: an unknown slug, a group, and a vanished
      # directory are each a hard, actionable error.
      def root!(bundle)
        slug = OKF::Registry.normalize(bundle)
        entry = entries.find { |candidate| candidate.slug == slug }
        if entry.nil?
          raise group_error(slug) if group?(slug)

          raise Error, "unknown bundle #{bundle.inspect} — known: #{slugs.join(", ")}"
        end
        raise Error, "bundle #{slug} is registered at #{entry.root}, which is not a directory (okf registry list)" unless File.directory?(entry.root)

        entry.root
      end

      # What `search` should read: nil or "*" is every served bundle, a slug is
      # that bundle, a group slug (registry mode) is its bundle leaves, an array
      # mixes them — deduped by root. Returns [ pairs, skipped ]: pairs as
      # [ slug, root ], skipped naming the bundles "*"/a group forgave (their
      # directory is gone); a *named* slug whose directory is gone raises.
      def resolve_search(asked)
        # An *empty list* is an argument mistake, not a fact about the disk. It
        # used to fall through to the "missing on disk" branch below, sending
        # the reader off diagnosing a broken installation.
        raise Error, "bundle: [] names no bundle — omit it (or pass \"*\") to search every bundle" if asked.is_a?(Array) && asked.empty?

        names = Array(OKF.blank?(asked) ? "*" : asked)
        pairs = []
        skipped = []
        names.each do |name|
          resolve_search_name(name.to_s, pairs, skipped)
        end
        raise Error, "every requested bundle is missing on disk (okf registry list)" if pairs.empty?

        [ pairs, skipped.uniq ]
      end

      private

      # Re-read the identity map when — and only when — the registry file's
      # fingerprint has moved. A no-op in argv mode, where @kernel is nil by
      # construction.
      #
      # Two failures are survived rather than propagated, because a server that
      # already has a working set must not be taken down by a file it does not
      # own: an unreadable file (deleted, or caught mid-write) and an
      # unparseable one both keep the last good entries. Neither advances the
      # stamp, so the next call retries and a fixed file is picked up on its
      # own — latching the bad stamp instead would make a transient truncation
      # permanent until restart.
      #
      # The three fields move together or not at all: `--http` serves on
      # WEBrick's per-request threads, so without the lock a reader could see
      # entries from the new parse against the kernel from the old one. The
      # fast path takes the stat outside it — the whole point of the
      # fingerprint is that the common call touches nothing shared.
      #
      # Note the order inside: stat, *then* reopen. A write landing between the
      # two is read but stamped with the older fingerprint, so the next call
      # re-reads — the safe direction. The reverse is the boot bug #initialize
      # documents.
      def refresh!
        return if @kernel.nil?

        stamp = registry_stamp
        return if stamp.nil? || stamp == @stamp

        @mutex.synchronize do
          return if stamp == @stamp

          kernel = @kernel.reopen
          @entries = kernel.map { |entry| Entry.new(entry.slug, entry.path, entry.title) }
          @kernel = kernel
          @stamp = stamp
        end
      rescue OKF::Error, SystemCallError
        nil
      end

      # mtime *and* size, the pair the residency layer already uses: a second
      # write inside one filesystem timestamp tick moves the size when it does
      # not move the clock.
      #
      # Every file the registry reads, not just its own. A link puts bundles in a
      # second file, and watching only the first meant a `registry set` over there
      # was never seen: this server would keep answering about the set it booted
      # with, which is the one failure a stamp exists to prevent. The link list
      # itself comes from the kernel, so adding or dropping a link moves the first
      # entry and the next pass watches the new set.
      # The two files are watched under different rules, and the asymmetry is the
      # point. This server's *own* registry going unreadable answers nil, which
      # holds the last good set — a file caught mid-write must not empty what is
      # being served. A *linked* file is only a pointer's target, and the kernel
      # already treats a missing one as "resolves to nothing, reported", so its
      # absence is a state change to follow rather than an error to ride out.
      def registry_stamp
        return nil if @kernel.nil?

        own = file_stamp(@kernel.path)
        return nil if own.nil?

        [ own ] + @kernel.links_listing.map { |row| file_stamp(row[:registry]) }
      rescue OKF::Error, SystemCallError
        nil
      end

      # nil for a file that is not there — a state in its own right for a link, so
      # a target appearing or vanishing moves the stamp exactly as an edit does.
      def file_stamp(path)
        stat = ::File.stat(path)
        [ stat.mtime.to_f, stat.size ]
      rescue SystemCallError
        nil
      end

      def resolve_search_name(name, pairs, skipped)
        return all_pairs(pairs, skipped) if name == "*"

        slug = OKF::Registry.normalize(name)
        entry = entries.find { |candidate| candidate.slug == slug }
        return add_pair(pairs, entry.slug, root!(slug)) if entry

        return group_pairs(slug, pairs, skipped) if group?(slug)

        raise Error, "unknown bundle #{name.inspect} — known: #{slugs.join(", ")}#{" (\"*\" is every bundle)" unless slugs.empty?}"
      end

      def all_pairs(pairs, skipped)
        entries.each do |entry|
          if File.directory?(entry.root)
            add_pair(pairs, entry.slug, entry.root)
          else
            skipped << entry.slug
          end
        end
      end

      # A group named in a search fans out to its leaves through the kernel —
      # tolerant like "*": asking for a set forgives a vanished member.
      def group_pairs(slug, pairs, skipped)
        @kernel.expand(slug).each do |entry|
          if File.directory?(entry.path)
            add_pair(pairs, entry.slug, entry.path)
          else
            skipped << entry.slug
          end
        end
      end

      def add_pair(pairs, slug, root)
        pairs << [ slug, root ] unless pairs.any? { |_, seen| seen == root }
      end

      def group_error(slug)
        members = @kernel.group?(slug).members.size
        Error.new("@#{slug} names a group of #{members} #{members == 1 ? "member" : "members"}; only `search` takes a group")
      end
    end
  end
end
