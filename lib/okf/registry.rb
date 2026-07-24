# frozen_string_literal: true

require "json"
require "pathname"

module OKF
  # A persistent, ordered registry of bundle references — the kernel behind the
  # multi-bundle server. It is a plain JSON file (no database): the global one
  # under $OKF_HOME (default ~/.okf), or a project-local .okf-registry.json
  # discovered by walking up from cwd (see .load / .discover), which replaces the
  # global one while you stand in its tree. Either way `okf registry set`/`del`
  # and a later bare `okf server` share one on-disk list. Part of the shell — it
  # reads and writes a file.
  #
  #   registry = OKF::Registry.load
  #   registry.add("docs")               # persists, returns the Entry
  #   registry.default = "docs"           # moves docs to the front
  #   registry.rename("docs", "handbook") # new slug, same path
  #   registry.default                    # => the first Entry
  #   registry.listing                    # => [{ slug:, title:, path:, default: }]
  #
  # **The first entry is the default** — the bundle a bare `okf server` opens at
  # `/`. That is position, not a stored slug: a slug would be a foreign key into
  # this same list, and every operation would owe it referential integrity —
  # carry it through a rename, re-point it after an add --as, clear it on a
  # remove, and survive it dangling. Order is state the registry already keeps,
  # so `default=` just moves the entry to the front and there is nothing left to
  # maintain or to dangle.
  #
  # On disk: { "bundles" => [ { "slug" => …, "path" => absolute dir,
  # "title" => label } ] }, the first row being the default. A bare array (the
  # original shape) still reads.
  class Registry
    # One registered bundle: a unique +slug+, the absolute +path+ on disk, and a
    # human-readable +title+ ("parent/dir").
    Entry = Struct.new(:slug, :path, :title)

    # A named set of bundle sources: a unique +slug+ and an ordered list of
    # +members+ (bundle *or* group slugs), stored normalized. A group has no path
    # — it resolves, recursively, to the bundles its members name. It shares the
    # slug namespace with Entry: a slug names one *or* the other, never both, so
    # `@backend` is unambiguous. Only `okf search`/`okf server` consume one — the
    # two verbs that already take several bundles.
    #
    # A plain class, not a Struct like Entry: the field we want is +members+, and
    # `Struct.new(:slug, :members)` would shadow Struct#members (the field-name
    # introspection) — the gotcha Lint/StructNewOverride flags. This keeps
    # `group.members` as the natural accessor without the override.
    class Group
      attr_accessor :slug, :members

      def initialize(slug, members)
        @slug = slug
        @members = members
      end
    end

    HOME_ENV = "OKF_HOME"
    DEFAULT_HOME = "~/.okf"

    # A project-local registry: the same JSON, discovered by walking up from the
    # working directory rather than read from $OKF_HOME. Its presence is the whole
    # state — no stored "local mode" flag — so a bare `okf server` inside a repo
    # serves that repo's bundles with no global setup.
    LOCAL_FILE = ".okf-registry.json"

    # The lever that forces the global registry even when a local one is on the
    # path up from cwd. Set it (inline) and discovery is skipped — the escape hatch
    # for a fixed-cwd caller (CI, a tool, the tests) that wants $OKF_HOME.
    NO_DISCOVERY_ENV = "OKF_NO_DISCOVERY"

    # Slugs the ref grammar has already spoken for. `@all` means every registered
    # bundle, so a bundle slugged "all" could never be named — reserve it here,
    # where both slug paths pass, rather than let one register and then be
    # unreachable.
    RESERVED_SLUGS = %w[all].freeze

    class << self
      # The registry file: $OKF_HOME/registry.json, $OKF_HOME defaulting to ~/.okf.
      # The env var is the only lever the CLI offers; +home+ overrides it for an
      # embedding app (and the tests), which should not have to mutate a
      # process-global to say which registry it means. An empty +home+ or env var
      # counts as unset — expand_path("") would silently plant the registry in
      # the current directory.
      def path(home: nil)
        env = ENV.fetch(HOME_ENV, nil)
        home = nil if home.nil? || home.to_s.empty?
        base = home || (env.nil? || env.empty? ? DEFAULT_HOME : env)
        File.join(expand(base), "registry.json")
      end

      # File.expand_path raises ArgumentError on a "~nosuchuser" (or bare "~"
      # with no HOME) — a bad *argument*, which the CLI must report as a usage
      # error rather than let escape as a backtrace and an exit code that means
      # "failing bundle".
      def expand(base)
        File.expand_path(base)
      rescue ArgumentError => e
        raise OKF::Error, "cannot expand #{base}: #{e.message}"
      end

      # The registry a run resolves to. Precedence, highest first: OKF_NO_DISCOVERY
      # forces the global one; else a `.okf-registry.json` discovered on the path
      # up from +cwd+ wins; else the global $OKF_HOME registry, exactly as before.
      # +cwd+ nil ⇒ no discovery, so an embedding app that calls `load` with no
      # arguments keeps the global-only behavior — only the CLI opts in by passing
      # `cwd: Dir.pwd`. $OKF_HOME names *where the global registry lives*; it does
      # not veto a nearer local one (it is commonly exported, so letting it would
      # silently defeat the feature for its own audience).
      def load(home: nil, cwd: nil)
        looking = cwd && ENV[NO_DISCOVERY_ENV].to_s.empty?
        local = looking ? discover(cwd) : nil
        # A local registry anchors its relative paths on its own directory; the
        # global one has no common anchor, so it stays absolute (relative_base nil).
        new(local || path(home: home), relative_base: local && File.dirname(local))
      end

      # Walk up from +start+ looking for a local registry; return its absolute path
      # or nil. Stops at the filesystem root (parent == self), so it never loops.
      def discover(start)
        dir = expand(start.to_s)
        loop do
          candidate = File.join(dir, LOCAL_FILE)
          return candidate if File.file?(candidate)

          parent = File.dirname(dir)
          break if parent == dir

          dir = parent
        end
        nil
      end

      # Normalize +base+ to a url-safe slug (lowercase, dashes) — "" when nothing
      # survives. This is the form a *lookup* wants: "@***" normalizes to nothing
      # and must stay nothing, so it fails as a bad ref instead of resolving to
      # whatever #slugify's placeholder happens to name.
      def normalize(base)
        base.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      end

      # +base+ normalized, with a placeholder when nothing survives — for
      # *minting* a slug from a directory basename, where some name must come
      # out. Shared with the server's ephemeral (unregistered) bundles so both
      # slug the same way.
      def slugify(base)
        slug = normalize(base)
        slug.empty? ? "bundle" : slug
      end

      # Does this argument name a location rather than a slug? A separator settles
      # it: #normalize maps one to a dash, so no slug can contain one. The reading
      # matters because #remove takes either — and a path that matched no entry
      # must not fall through to a *slug* lookup, where "./notes" strips to
      # "notes" and deletes an entry pointing somewhere else entirely, reporting
      # success. This is the line between the two readings.
      def path_shaped?(arg)
        arg.to_s.include?(File::SEPARATOR)
      end

      # +base+ slugified, then suffixed (-2, -3, …) until it avoids every slug in
      # +taken+. Reserving is the caller's business, not this helper's: the
      # ephemeral hub mints through here too, and it has no registry and no
      # @refs, so a name reserved for the ref grammar would suffix it to /b/all-2/
      # against a /b/all/ that does not exist. #unique_slug adds the reserved
      # names because the registry is where they mean something.
      def dedupe(base, taken)
        slug = slugify(base)
        return slug unless taken.include?(slug)

        n = 2
        n += 1 while taken.include?("#{slug}-#{n}")
        "#{slug}-#{n}"
      end
    end

    include Enumerable

    attr_reader :path

    # +relative_base+ is the directory a local registry's relative paths anchor on
    # (see .load). nil means an absolute-path registry — the global $OKF_HOME one,
    # and every library caller — so its behavior is exactly what it was before
    # relative storage existed.
    def initialize(path, relative_base: nil)
      @path = path
      @relative_base = relative_base
      @entries = []
      @groups = []
      read
    end

    def each(&block)
      @entries.each(&block)
    end

    def size
      @entries.size
    end

    def empty?
      @entries.empty?
    end

    def slugs
      @entries.map(&:slug)
    end

    def get(slug)
      @entries.find { |entry| entry.slug == slug }
    end

    # The group registered under +slug+ (already normalized, like #get), or nil.
    def group?(slug)
      @groups.find { |group| group.slug == slug }
    end

    # The default bundle a bare `okf server` selects: the first entry still on
    # disk. Position decides it, but a position the hub cannot serve decides
    # nothing — it drops a vanished directory rather than serving a hole, so the
    # default has to skip the same ones or `registry list` would star a bundle
    # `/` never opens. Falling back to the first entry when *every* one has
    # vanished keeps a bare `@` failing with "points to <path>, which is not a
    # directory" instead of the much worse "not a registered bundle". nil only
    # when nothing is registered.
    def default
      @entries.find { |entry| File.directory?(entry.path) } || @entries.first
    end

    # Choose which bundle `/` opens, by moving that entry to the front. Persists;
    # raises on an unknown slug. The ask is normalized the way registration
    # normalized it, so the name the user typed at --as is the name that resolves
    # here.
    #
    # A directory that is gone is refused, exactly as #add refuses to register
    # one: both are explicit asks, and #default skips a vanished entry, so
    # allowing the move would answer `default bundle → <some other slug>` to
    # someone who named this one.
    def default=(slug)
      normalized = self.class.normalize(slug)
      if group?(normalized)
        raise OKF::Error, "cannot default to a group: @#{normalized} names a set of bundles, and the default is one bundle"
      end

      entry = get(normalized)
      raise OKF::Error, "no such bundle: #{slug}" unless entry
      unless File.directory?(entry.path)
        raise OKF::Error, "cannot default to #{entry.slug}: #{entry.path} is not a directory " \
                          "(okf registry del #{entry.slug}, or restore it)"
      end

      @entries.delete(entry)
      @entries.unshift(entry)
      write
    end

    # Give the bundle at +old_slug+ a new slug (its mount path and switcher name).
    # The new name is slugified; a collision with another entry raises rather than
    # silently suffixing — a rename is explicit. Position is untouched, so a
    # renamed default stays the default with no bookkeeping.
    def rename(old_slug, new_slug)
      old = self.class.normalize(old_slug)
      entry = get(old) || group?(old)
      raise OKF::Error, "no such bundle or group: #{old_slug}" unless entry

      slug = explicit_slug(new_slug, entry)
      entry.slug = slug
      # A member list stores slugs, so a rename that stopped at the entry would
      # orphan every group that named it — cascade the new name across them.
      cascade_rename(old, slug)
      write
      entry
    end

    # One row per bundle for the CLI list: +dir+ is the on-disk directory, +mount+
    # the server path, +default+ true for the first row, +missing+ true when the
    # registered directory no longer exists on disk. +default+ stays in the row
    # even though it is now derivable from position — a consumer reading the JSON
    # should not have to know the rule to find the bundle `/` opens.
    def listing
      chosen = default
      @entries.map do |entry|
        { slug: entry.slug, title: entry.title, dir: entry.path, mount: "/b/#{entry.slug}/",
          default: entry.equal?(chosen), missing: !File.directory?(entry.path) }
      end
    end

    # Register +dir+ (must be a readable bundle directory). Re-registering the same
    # path refreshes its title in place (and its slug when +as+ is given). A
    # basename-derived slug is deduped with a suffix; an explicit +as+ raises on
    # collision instead — the same "explicit is explicit" rule as #rename.
    # +default: true+ moves it to the front. Persists, then returns the entry.
    def add(dir, as: nil, default: false)
      root = self.class.expand(dir.to_s)
      raise OKF::Error, "not a directory: #{dir}" unless File.directory?(root)

      # The label is path arithmetic; Folder.load would parse every markdown
      # file in the bundle to hand back its own basename.
      title = Bundle::Folder.label(root)
      entry = @entries.find { |candidate| candidate.path == root }
      if entry
        entry.title = title
        entry.slug = explicit_slug(as, entry) if as
      else
        slug = as ? explicit_slug(as, nil) : unique_slug(File.basename(root), nil)
        entry = Entry.new(slug, root, title)
        @entries << entry
      end
      if default
        @entries.delete(entry)
        @entries.unshift(entry)
      end
      write
      entry
    end

    # Remove the entry named by +slug+ (or whose path matches). Returns the removed
    # entry, or nil when nothing matched. Removing the default needs no cleanup —
    # the next entry is first, and so is the default. Persists on change.
    def remove(slug)
      # Slug-or-dir, so the normalized reading comes *last*: "./docs" must mean
      # the directory while one is registered under that path, and only fall
      # back to naming the "docs" slug when no path matches.
      target = get(slug) ||
               @entries.find { |entry| entry.path == self.class.expand(slug.to_s) } ||
               (self.class.path_shaped?(slug) ? nil : get(self.class.normalize(slug)))
      if target
        @entries.delete(target)
        cascade_remove(target.slug)
        write
        return target
      end

      # Not a bundle — a group answers to its slug only (having no path, it can
      # never match the path-shaped reading). Removing it, like removing a bundle,
      # drops the slug from every group that named it.
      group = self.class.path_shaped?(slug) ? nil : (group?(slug) || group?(self.class.normalize(slug)))
      return nil unless group

      @groups.delete(group)
      cascade_remove(group.slug)
      write
      group
    end

    # Create the group +slug+, or add +member_asks+ to an existing one (a union,
    # order-preserving). Members are bundle *or* group slugs, given bare or as
    # `@ref`; each must already name a bundle or a group, and the result must not
    # reach itself (a cycle is refused before the write). Persists, returns the
    # Group.
    def set_group(slug, member_asks)
      name = explicit_group_slug(slug)
      members = normalize_members(member_asks)
      raise OKF::Error, "a group needs at least one member (okf registry group #{name} <@bundle…>)" if members.empty?

      members.each do |member|
        next if get(member) || group?(member)

        raise OKF::Error, "no such bundle or group: @#{member} (okf registry list)"
      end

      group = group?(name)
      merged = group ? group.members.dup : []
      members.each { |member| merged << member unless merged.include?(member) }
      raise OKF::Error, "group cycle: @#{name} would contain itself" if reaches_self?(name, merged)

      if group
        group.members = merged
      else
        group = Group.new(name, merged)
        @groups << group
      end
      write
      group
    end

    # Drop +member_asks+ from the group +slug+. Removing the last member deletes
    # the group — an empty group resolves to nothing, so it is not worth keeping.
    # Returns [removed_members, emptied?]. Raises on an unknown group; a member
    # that was not there is simply not in the returned list.
    def unset_group_members(slug, member_asks)
      name = self.class.normalize(slug)
      group = group?(name)
      raise OKF::Error, "no such group: #{slug} (okf registry list)" unless group

      asks = normalize_members(member_asks)
      removed = group.members & asks
      group.members -= asks
      emptied = group.members.empty?
      @groups.delete(group) if emptied
      write
      [ removed, emptied ]
    end

    # Resolve +slug+ to its ordered, path-deduped bundle Entries — a group flattens
    # recursively, a bundle slug resolves to itself. Returns leaves even when their
    # directory has vanished; the caller (search/server) decides whether to skip
    # one, the way `@all` tolerates a gap. Raises OKF::Error on a cycle — a
    # defense-in-depth guard, since #set_group already blocks one at write time but
    # the file is hand-editable.
    def expand(slug)
      entries = []
      seen = []
      resolve_into(self.class.normalize(slug), entries, seen, [])
      entries
    end

    # Persist the current state to disk. The mutating verbs write as a side effect
    # of the change; `save` is the public seam for the one caller that creates a
    # registry with nothing to change yet — `okf registry init`, materializing an
    # empty local file so discovery has something to find.
    def save
      write
    end

    # One row per group for `registry list`: its members and how many bundles it
    # resolves to (+resolved+ is nil when a hand-edited cycle makes it unanswerable).
    def groups_listing
      @groups.map do |group|
        resolved = begin
          expand(group.slug).size
        rescue OKF::Error
          nil
        end
        { slug: group.slug, members: group.members.dup, resolved: resolved }
      end
    end

    private

    # A basename-derived slug: silently deduped with a numeric suffix, around the
    # reserved names as well as the taken ones — so a directory named all/
    # registers as "all-2". This is the minting path, where the gem invents a name
    # and a suffix is expected; #explicit_slug refuses instead, because there the
    # name is the user's.
    def unique_slug(base, skip)
      self.class.dedupe(base, taken_slugs(skip) + RESERVED_SLUGS)
    end

    # Every slug spoken for, bundle *and* group, except +skip+ (the entry or group
    # being re-slugged in place). The unified namespace: a slug names one thing, so
    # a collision check has to see both lists.
    def taken_slugs(skip)
      @entries.reject { |entry| entry.equal?(skip) }.map(&:slug) +
        @groups.reject { |group| group.equal?(skip) }.map(&:slug)
    end

    # An explicitly requested slug (--as, rename): normalized, and a collision
    # with another entry is an error, never a silent suffix. Nothing surviving
    # normalization is an error too — the same rule as a collision, since
    # answering `--as "***"` with the placeholder slug would substitute a name
    # the user did not choose.
    def explicit_slug(base, skip)
      slug = self.class.normalize(base)
      raise OKF::Error, "not a usable slug: #{base} (letters and digits, please)" if slug.empty?

      # Reserved names are refused, never suffixed: substituting "all-2" for the
      # "all" they asked for is exactly the name-they-did-not-choose the rule
      # below forbids.
      if RESERVED_SLUGS.include?(slug)
        raise OKF::Error, "not a usable slug: #{slug} is reserved (@#{slug} names every registered bundle)"
      end

      # Refusing is the "never substitute a name you chose" rule, but a refusal
      # with no way forward is a dead end: the slug is spoken for by another
      # entry or group, so say which move frees it.
      raise OKF::Error, "slug already taken: #{slug} (rename or remove that entry first)" if taken_slugs(skip).include?(slug)

      slug
    end

    # The group slug for #set_group: usable, not reserved, and not a bundle's. A
    # group re-using its own slug is the update path (so a group collision is not
    # checked here); a bundle's slug is a hard collision.
    def explicit_group_slug(base)
      slug = self.class.normalize(base)
      raise OKF::Error, "not a usable slug: #{base} (letters and digits, please)" if slug.empty?

      if RESERVED_SLUGS.include?(slug)
        raise OKF::Error, "not a usable slug: #{slug} is reserved (@#{slug} names every registered bundle)"
      end
      if get(slug)
        raise OKF::Error, "slug already taken: #{slug} names a bundle (rename or remove that entry first)"
      end

      slug
    end

    # Member asks (bare or `@ref`) normalized to bundle/group slugs, empties dropped.
    # #normalize maps a leading @ to nothing, so "@alpha" and "alpha" both arrive as
    # "alpha".
    def normalize_members(asks)
      asks.map { |ask| self.class.normalize(ask) }.reject(&:empty?)
    end

    # Would a group named +start+ with +members+ reach itself? Walks the member
    # graph (members that are groups expand), returning true on any path back to
    # +start+ — the direct self-reference and the indirect cycle both. Other groups
    # are already acyclic, so only edges out of +start+ can newly close a loop.
    def reaches_self?(start, members)
      stack = members.dup
      seen = []
      until stack.empty?
        member = stack.pop
        return true if member == start
        next if seen.include?(member)

        seen << member
        nested = group?(member)
        stack.concat(nested.members) if nested
      end
      false
    end

    # Depth-first expansion of +slug+ into bundle entries, deduped by path and
    # cycle-guarded by the +chain+ of groups already open above it.
    def resolve_into(slug, entries, seen_paths, chain)
      if chain.include?(slug)
        raise OKF::Error, "group cycle: #{(chain + [ slug ]).map { |name| "@#{name}" }.join(" → ")}"
      end

      group = group?(slug)
      if group
        group.members.each { |member| resolve_into(member, entries, seen_paths, chain + [ slug ]) }
        return
      end

      entry = get(slug)
      return unless entry # a dangling member (hand-edited) resolves to nothing
      return if seen_paths.include?(entry.path)

      seen_paths << entry.path
      entries << entry
    end

    # Drop +slug+ from every group's members, and any group thereby emptied — which
    # itself becomes a slug to drop, so a chain of one-member groups unwinds cleanly.
    def cascade_remove(slug)
      dropping = [ slug ]
      until dropping.empty?
        gone = dropping.shift
        @groups.each { |group| group.members.delete(gone) }
        @groups.select { |group| group.members.empty? }.each do |empty|
          @groups.delete(empty)
          dropping << empty.slug
        end
      end
    end

    # Rewrite +from+ to +to+ across every group's members, deduping when the new
    # name already sits beside the old one.
    def cascade_rename(from, to)
      @groups.each do |group|
        next unless group.members.include?(from)

        group.members = group.members.map { |member| member == from ? to : member }.uniq
      end
    end

    def read
      return unless File.exist?(@path)

      data = JSON.parse(File.read(@path, encoding: "UTF-8"))
      rows = data.is_a?(Hash) ? Array(data["bundles"]) : Array(data) # bare array: the original shape
      @entries = rows.map { |row| entry_from(row) }
      group_rows = data.is_a?(Hash) ? Array(data["groups"]) : [] # a groups-less file has none
      @groups = group_rows.map { |row| group_from(row) }.reject { |group| group.members.empty? }
      normalize_slugs
    rescue JSON::ParserError => e
      malformed("#{e.message} (fix or delete the file)")
    rescue SystemCallError => e
      malformed(e.message)
    end

    # One row to an Entry, with the shape checked. Valid JSON is not a valid
    # registry: the parse error above tells the user to fix the file by hand,
    # which invites a row with no "path" — that must fail here as a usage error,
    # not survive to crash a File.directory? call three frames away.
    def entry_from(row)
      unless row.is_a?(Hash) && row["slug"].is_a?(String) && row["path"].is_a?(String) && !row["path"].empty?
        malformed('every entry needs a "slug" and a "path" (fix or delete the file)')
      end
      path = resolve_stored(row["path"])
      Entry.new(row["slug"], path, row["title"] || File.basename(path))
    end

    # Resolve a stored path to an absolute one: a relative path is anchored on the
    # local registry's directory, an absolute one (and every path in the global
    # registry) is returned untouched. So entry.path is *always* absolute in
    # memory, and every consumer — File.directory?, the listing, the server mount —
    # goes on seeing the absolute paths it always did.
    def resolve_stored(raw)
      return raw if @relative_base.nil? || raw.start_with?("/")

      File.expand_path(raw, @relative_base)
    end

    # The on-disk form of an absolute path. In a local registry a bundle inside the
    # registry's own tree is stored *relative* to it, so the file travels with the
    # repo (a checkout elsewhere, a container mounting it) and still resolves; a
    # bundle outside the tree stays absolute, since a relative path that climbs out
    # cannot be re-anchored anywhere useful, and being honest about that beats a
    # `../../..` that breaks on the first move. The global registry (no base) always
    # stores absolute — its behavior is unchanged.
    def store_form(abs)
      return abs if @relative_base.nil?

      # Both are absolute — entry.path always is, and @relative_base is a dirname of
      # one — so relative_path_from cannot fail to relate them on a POSIX tree.
      rel = Pathname.new(abs).relative_path_from(Pathname.new(@relative_base)).to_s
      rel.start_with?("..") ? abs : rel
    end

    # One row to a Group, shape-checked like #entry_from. Members are normalized on
    # the way in, the same asymmetry-fix #normalize_slugs applies to slugs: a
    # hand-typed "@My Docs" member becomes "my-docs" so it can resolve.
    def group_from(row)
      unless row.is_a?(Hash) && row["slug"].is_a?(String) && row["members"].is_a?(Array)
        malformed('every group needs a "slug" and a "members" array (fix or delete the file)')
      end
      members = row["members"].map { |member| self.class.normalize(member.to_s) }.reject(&:empty?)
      Group.new(row["slug"], members)
    end

    # Slugs enter this list three ways — minted from a basename, asked for with
    # --as, and read from this file — and the first two normalize. The third did
    # not, and that asymmetry is the whole bug: the file could hold a name the
    # listing prints and nothing else can reach. `@my-docs` misses "My Docs", and
    # so do #rename and #default=, which look it up through the very
    # normalization the read skipped — so the two verbs that could fix the entry
    # are the two that cannot see it, leaving hand-editing JSON as the only way
    # out. Reserved names are the same story with a different cause, so they take
    # the same cure rather than a second one.
    #
    # A slug registration would have produced unchanged is left exactly as it is —
    # including one already carrying a suffix — so repairing a sick entry never
    # renames a healthy one. Everything else is minted around the names the other
    # entries hold, through the same call registration makes. The next write
    # persists it.
    def normalize_slugs
      @entries.each do |entry|
        next if usable_slug?(entry.slug)

        entry.slug = unique_slug(entry.slug, entry)
      end
      @groups.each do |group|
        next if usable_slug?(group.slug)

        group.slug = unique_slug(group.slug, group)
      end
    end

    # A stored slug that registration would have handed back untouched:
    # normalized, non-empty, and not a name the ref grammar has taken.
    def usable_slug?(slug)
      !slug.empty? && slug == self.class.normalize(slug) && !RESERVED_SLUGS.include?(slug)
    end

    def malformed(detail)
      raise OKF::Error, "malformed registry at #{@path}: #{detail}"
    end

    # Write-to-temp then rename, so a concurrent reader (another verb, a booting
    # server) never sees a torn file — the same promotion the bundle Writer uses.
    # Two racing writers stay last-writer-wins; the registry is a per-user file.
    def write
      FileUtils.mkdir_p(File.dirname(@path))
      rows = @entries.map { |entry| { "slug" => entry.slug, "path" => store_form(entry.path), "title" => entry.title } }
      groups = @groups.map { |group| { "slug" => group.slug, "members" => group.members } }
      payload = { "bundles" => rows, "groups" => groups }
      tmp = "#{@path}.tmp-#{Process.pid}"
      begin
        File.write(tmp, JSON.pretty_generate(payload) + "\n")
        File.rename(tmp, @path)
      rescue StandardError
        # A failed write must not leave its scratch file behind: the registry
        # lives in the user's $OKF_HOME, and litter there outlives the error.
        FileUtils.rm_f(tmp)
        raise
      end
    rescue SystemCallError => e
      # #read already turns an errno into an OKF::Error, and every registry verb
      # rescues exactly that — so letting one out of #write hands the user a
      # backtrace under exit 1, a code the CLI spends on "non-conformant bundle".
      # An unwritable $OKF_HOME is a usage error, and it says which file and why.
      raise OKF::Error, "cannot write registry at #{@path}: #{e.message}"
    end
  end
end
