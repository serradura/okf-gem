# frozen_string_literal: true

require "okf"
require "okf/registry"

module OKF::TUI
  # Every bundle the session can see, which one is active, and which ones a
  # search covers.
  #
  # Two ways in, mirroring what `okf server` accepts: named directories are
  # ad-hoc and never touch the registry, and with no directories the registry
  # itself is the workspace. Registering stays an explicit act — an ad-hoc look
  # at two bundles should not enrol them in the user's durable list.
  class Workspace
    # One bundle in the workspace. `model` is nil when the directory is missing
    # or unreadable, and `error` says which — so a row explains itself instead of
    # silently vanishing from the list.
    class Entry
      attr_reader :slug, :dir, :link
      attr_accessor :model, :error

      def initialize(slug:, dir:, default:, registered:, link: nil)
        @slug = slug
        @dir = dir
        @default = default
        @registered = registered
        @link = link
      end

      # Did this bundle arrive through an okf registry link? Browsing one is
      # browsing a bundle, so it reads like any other — but the registry that
      # owns it is another file, and okf refuses every config write against it.
      def linked?
        !@link.nil?
      end

      def default?
        @default
      end

      def registered?
        @registered
      end

      def loaded?
        !model.nil?
      end

      def concepts
        loaded? ? model.concept_count : 0
      end
    end

    # One registry group (okf 1.12): a slug naming a list of members — bundle or
    # group slugs, so they nest — which resolves recursively, path-deduped, to
    # bundle leaves.
    #
    # `members` is what the registry file says, verbatim, and `bundles` is what
    # okf resolved it to. Both are shown, because they answer different questions:
    # the members are what an edit would change, the leaves are what a search
    # would cover, and for a nested group those are not the same list.
    class Group
      attr_reader :slug, :members, :bundles, :link

      def initialize(slug:, members:, bundles:, cyclic:, link: nil)
        @slug = slug
        @members = members
        @bundles = bundles
        @cyclic = cyclic
        @link = link
      end

      # A group an okf registry link brought in — the link's own set, or one the
      # linked file curates. Scopable and searchable like any other; writable by
      # nobody here, since okf persists only the groups this registry owns.
      def linked?
        !@link.nil?
      end

      # A hand-edited registry can name a cycle, which okf reports by declining to
      # resolve rather than by looping. Nothing here can repair it, so the row says
      # so and refuses to be scoped — the alternative is a group that silently
      # covers no bundles.
      def cyclic?
        @cyclic
      end

      def size
        bundles.length
      end
    end

    attr_reader :entries, :registry, :home, :active_slug

    # +cwd+ is what opts this workspace into registry discovery, and it is
    # deliberately not defaulted to Dir.pwd: okf draws the same line, where only
    # its CLI passes a cwd and a library caller stays on the global registry. A
    # default here would make the registry an embedding app reads depend on the
    # directory its process happens to be in, and would let the suite discover a
    # `.okf-registry.json` from wherever `rake` was run.
    #
    # +ref_slugs+ maps a resolved directory to the slug the @ref named it by, so a
    # session built from refs keeps the names the user typed. See Refs#slugs.
    def initialize(dirs: [], ref_slugs: {}, home: nil, cwd: nil)
      @home = home
      @cwd = cwd
      @dirs = Array(dirs)
      @ref_slugs = ref_slugs || {}
      load_entries
    end

    # A registry-backed workspace is the one that can be configured; a workspace
    # of named directories has no registry to write to.
    def registry_backed?
      @dirs.empty?
    end

    # The registry file this session is on — the discovered project-local one when
    # there is one, else the global $OKF_HOME one. Asked of the registry rather
    # than recomputed from `home`, because Registry.path only ever names the global
    # file and would report the wrong one out of a project directory: the header
    # would print a path the session is not reading.
    def registry_path
      (registry || open_registry).path
    end

    # The registry file a link points at — what a refusal has to name, since
    # "edit it there" is useless without saying where there is. nil when nothing
    # is linked under that name.
    def link_target(name)
      return nil unless registry_backed?

      registry.links_listing.find { |row| row[:slug] == name }&.fetch(:registry)
    end

    def empty?
      entries.empty?
    end

    def entry(slug)
      entries.find { |candidate| candidate.slug == slug }
    end

    # The registry's groups. Empty for an ad-hoc workspace, which has no registry
    # to have groups in.
    #
    # Read from okf rather than derived: `groups_listing` is what `okf registry
    # list` prints and `expand` is what `okf search @group` resolves, so a group
    # means the same set here as it does at the command line.
    def groups
      @groups ||= registry_backed? ? registry_groups : []
    end

    def group(slug)
      groups.find { |candidate| candidate.slug == slug }
    end

    def active
      entry(@active_slug)
    end

    # The active bundle's Model, or nil when nothing is loadable. Every
    # single-bundle view reads through this.
    def model
      active&.model
    end

    def switch(slug)
      return false unless entry(slug)&.loaded?

      @active_slug = slug
      true
    end

    # ── scope: which bundles a search covers ────────────────────────────────

    # Kept in workspace order and filtered to slugs that still exist, so a
    # reload after a remove cannot leave a stale slug in the scope.
    def scope
      entries.map(&:slug).select { |slug| @scope.include?(slug) }
    end

    def scoped?(slug)
      @scope.include?(slug)
    end

    def toggle_scope(slug)
      @scope.include?(slug) ? @scope.delete(slug) : @scope << slug
    end

    def scope_all
      @scope = entries.map(&:slug)
    end

    def scope_none
      @scope = []
    end

    def scope_only(slug)
      @scope = [ slug ]
    end

    # Scope the search to a group — the reason a group is worth showing here at
    # all. `okf search @mkt` merges exactly these bundles into one ranking; this is
    # the same set, named the same way, reached with one key instead of retyping
    # the members.
    #
    # Returns a message for the status line, like the config writes do, because
    # each of the three ways this can decline to do anything needs saying: a
    # scope that silently did not change reads as a broken key.
    def scope_group(slug)
      group = group(slug)
      return "no such group: @#{slug}" if group.nil?
      return "@#{slug} names a cycle in #{registry.path} — okf cannot resolve it" if group.cyclic?
      return "@#{slug} resolves to no bundle here" if group.bundles.empty?

      # A copy: `toggle_scope` mutates the scope in place, and the group is a
      # description of the registry, not a scratch list.
      @scope = group.bundles.dup
      "search scope: @#{slug} — #{group.size} #{group.size == 1 ? "bundle" : "bundles"}"
    end

    # Ranked search across every scoped bundle, merged into one ordered list.
    # They share one index on purpose: BM25 weighs a term by how rare it is in
    # the corpus, so per-bundle indexes would score the same match differently
    # depending on which bundle it came from. One index makes one corpus — the
    # same thing `okf search @all` does.
    #
    # The mode is what chooses okf's engine, by declaring the capability the query
    # needs rather than by naming an engine:
    #
    #   :fuzzy   `fuzzy: true`  → the full-text index. Ranked BM25, typo-tolerant.
    #   :text    nothing        → the scan, okf's own default. Raw substring.
    #   :regexp  `regexp: true` → the scan, as a pattern.
    #
    # All three are reachable because the index and the scan disagree *by design*,
    # and each is wrong for what the other is right for. okf documents the index's
    # limits precisely: its tokenizer splits on punctuation, so `7.2.0` indexes as
    # `7`, `2`, `0`, and a backtick is not punctuation, so a word inside a code span
    # indexes as `` `minifts` `` and the query `minifts` does not match it. Measured
    # on okf's own bundle, the index finds three of the five concepts that say
    # minifts, and returns fourteen for OKF_HOME where the scan returns five.
    # Offering only the index left the terms glued to symbols — a constant, an env
    # var, a version — unfindable, with nothing on screen saying so.
    def search(query, mode: :fuzzy)
      @search_error = nil
      terms = query.to_s.split(/\s+/).reject(&:empty?)
      return [] if terms.empty?

      corpus = search_corpus
      return [] if corpus.nil?

      run_search(corpus, terms, mode)
    rescue RegexpError => e
      # A bad pattern is the user's typo, not a broken install, and it must not
      # land in the blanket rescue below — "no matches" for an unparseable regexp
      # is the silent-wrong-answer shape this view keeps having to avoid.
      @search_error = "bad pattern: #{e.message}"
      []
    rescue OKF::Bundle::Search::UnsupportedQuery => e
      @search_error = e.message
      []
    rescue StandardError
      []
    end

    # Set when a query could not be answered *and the reason is worth showing*.
    # nil after any search that ran, so it never outlives the query it describes.
    attr_reader :search_error

    # ── config: every registry write lands here ─────────────────────────────
    #
    # Each returns a message for the status line and reloads, so what the screen
    # shows next is what the file now says rather than what the in-memory list
    # was talked into believing.

    def add(dir)
      return not_registry_backed unless registry_backed?

      added = registry.add(File.expand_path(dir.to_s.strip))
      reload
      "registered @#{added.slug} → #{added.path}"
    rescue OKF::Error => e
      "could not add: #{e.message}"
    end

    def remove(slug)
      return not_registry_backed unless registry_backed?

      registry.remove(slug)
      reload
      "removed @#{slug} from the registry (the bundle itself is untouched)"
    rescue OKF::Error => e
      "could not remove: #{e.message}"
    end

    def make_default(slug)
      return not_registry_backed unless registry_backed?

      registry.default = slug
      reload
      "@#{slug} is now the default"
    rescue OKF::Error => e
      "could not set default: #{e.message}"
    end

    def rename(old_slug, new_slug)
      return not_registry_backed unless registry_backed?

      new_slug = new_slug.to_s.strip
      return "rename cancelled: no name given" if new_slug.empty?

      renamed = registry.rename(old_slug, new_slug)
      reload
      "@#{old_slug} is now @#{renamed.slug}"
    rescue OKF::Error => e
      "could not rename: #{e.message}"
    end

    # ── groups: the writes okf's `registry group` / `ungroup` make ──────────
    #
    # A group is registry configuration in exactly the sense a slug rename is, so
    # it belongs on the same side of the line as the writes above — see
    # [registry-write-boundary]. Members come from the *scope* rather than from a
    # typed list: `◉` already means "these bundles" in this view, so the gesture is
    # toggle what you want, then name it.
    #
    # okf owns the cascades. `set_group` creates-or-adds and refuses a cycle,
    # `unset_group_members` deletes a group it empties, and `rename`/`remove` span
    # a group slug and cascade through every member list — none of which is
    # reimplemented here.

    def create_group(slug, members)
      return not_registry_backed unless registry_backed?

      slug = slug.to_s.strip
      return "group cancelled: no name given" if slug.empty?
      return "group cancelled: no bundles in scope to name" if members.empty?

      group = registry.set_group(slug, refs(members))
      reload
      "@#{group.slug} names #{count(members.length)}"
    rescue OKF::Error => e
      "could not create the group: #{e.message}"
    end

    def add_to_group(slug, members)
      return not_registry_backed unless registry_backed?
      return "nothing in scope to add" if members.empty?

      registry.set_group(slug, refs(members))
      reload
      # One member named, several counted: `+` adds the row under a cursor and the
      # line has to say *which* row landed, while `c` adds a whole scope and naming
      # every slug would be a list, not a message.
      total = count(group(slug)&.size.to_i)
      members.length == 1 ? "@#{members.first} joined @#{slug} — #{total}" : "@#{slug} now names #{total}"
    rescue OKF::Error => e
      "could not add to @#{slug}: #{e.message}"
    end

    def remove_from_group(slug, members)
      return not_registry_backed unless registry_backed?
      return "nothing in scope to remove" if members.empty?

      registry.unset_group_members(slug, refs(members))
      reload
      # okf deletes a group its last member left, so say so rather than leave the
      # user looking for a row that is gone.
      return "@#{slug} had nothing left, so it is gone" if group(slug).nil?

      total = count(group(slug).size)
      members.length == 1 ? "@#{members.first} left @#{slug} — #{total}" : "@#{slug} now names #{total}"
    rescue OKF::Error => e
      "could not remove from @#{slug}: #{e.message}"
    end

    # Re-read from disk, keeping the active bundle and the scope wherever they
    # still resolve.
    def reload
      previous_active = @active_slug
      previous_scope = @scope

      load_entries

      @active_slug = previous_active if entry(previous_active)&.loaded?
      @active_slug ||= first_loaded_slug
      kept = previous_scope.select { |slug| entry(slug) }
      @scope = kept.empty? ? entries.map(&:slug) : kept
    end

    private

    def not_registry_backed
      "these bundles were named on the command line — there is no registry to change"
    end

    # Slugs as okf's group verbs take them. `@` is the ref grammar's own marker,
    # and passing it keeps these calls readable as the CLI commands they mirror.
    def refs(slugs)
      slugs.map { |slug| "@#{slug}" }
    end

    def count(total)
      "#{total} #{total == 1 ? "bundle" : "bundles"}"
    end

    # Explicit branches rather than a splatted options hash: three named calls read
    # as the three engines they select, and the floor is Ruby 2.4.
    def run_search(corpus, terms, mode)
      case mode
      when :regexp then OKF::Bundle::Search.with(corpus, terms, regexp: true)
      when :text then OKF::Bundle::Search.with(corpus, terms)
      else OKF::Bundle::Search.with(corpus, terms, fuzzy: true)
      end
    end

    def scoped_pairs
      entries.select { |entry| entry.loaded? && scoped?(entry.slug) }
             .map { |entry| [ entry.slug, entry.model.bundle ] }
    end

    # The corpus behind the search view, held across queries.
    #
    # `Search.across` rebuilds everything per call — the documents *and* the
    # full-text index — which is the right trade for the CLI it was measured for:
    # one question, then the process exits. A TUI is the other case, the one okf
    # 1.11.0 added `prepare`/`with` for and `okf server` already uses. Measured
    # over five registered bundles, 129 concepts between them: **392 ms** for the
    # first query, which builds the corpus, then **12–16 ms** for every one after.
    # Rebuilding, every query cost the 392 ms.
    #
    # Built on first use rather than at load: with a whole registry open, a session
    # that never searches should not pay to index every bundle nobody looked at —
    # the same reason Model memoizes its analysis instead of computing it eagerly.
    # No `engine:` for the same reason; that argument only moves the index build
    # earlier, and there is no boot here to move it into.
    #
    # Keyed on the scoped slugs, and dropped outright by #load_entries. Both
    # matter, and for different reasons: the key catches a scope the user changed,
    # while the drop catches a reload, after which the models are freshly read
    # objects and a corpus built from the old ones describes a bundle that may no
    # longer be on disk. okf takes the same care in its hub, and for the stated
    # reason — a held index outliving the set it was built from is a wrong answer
    # rather than a slow one.
    def search_corpus
      pairs = scoped_pairs
      return nil if pairs.empty?

      key = pairs.map { |slug, _bundle| slug }
      return @corpus if @corpus && @corpus_key == key

      # Assigned only on success, so a failed build is retried rather than
      # memoized as an empty result — #search rescues into "no matches", which is
      # the wrong lasting answer for a corpus that could not be built.
      corpus = OKF::Bundle::Search.prepare(pairs)
      @corpus_key = key
      @corpus = corpus
    end

    # Discovery runs once, on the first load; every reload after a write goes
    # through Registry#reopen instead. That is okf's own instruction, and the
    # reason is the relative paths a local registry stores: `Registry.new(path)`
    # drops the +relative_base+ a discovered file carries, and then every in-tree
    # bundle reads as "folder is gone". Re-discovering would find the same file,
    # but reopening says what is meant — re-read this registry, anchored as it was.
    def open_registry
      OKF::Registry.load(home: home, cwd: @cwd)
    end

    def load_entries
      @registry = (registry ? registry.reopen : open_registry) if registry_backed?
      @entries = registry_backed? ? registry_entries : ad_hoc_entries
      # See #search_corpus: the entries about to be built are freshly read, so a
      # corpus held over from the previous ones is describing bundles this session
      # no longer has. The groups come off the same re-read registry, so a write
      # that cascaded through a member list shows its result rather than the list
      # memory remembers.
      @corpus = nil
      @corpus_key = nil
      @groups = nil
      @scope = @entries.map(&:slug)
      @active_slug = first_loaded_slug
    end

    def first_loaded_slug
      @entries.find(&:loaded?)&.slug
    end

    def registry_entries
      registry.listing.map do |row|
        build_entry(slug: row[:slug], dir: row[:dir], default: row[:default],
          registered: true, missing: row[:missing], link: row[:link])
      end
    end

    # okf reports an unresolvable group by putting nil in `resolved` — that is its
    # signal for a hand-edited cycle, which it declines to walk rather than loop
    # on. Asking `expand` again for the leaf slugs is guarded the same way, since
    # `groups_listing` swallowed the error to compute the count.
    def registry_groups
      registry.groups_listing.map do |row|
        bundles = begin
          row[:resolved] && registry.expand(row[:slug]).map(&:slug)
        rescue OKF::Error
          nil
        end

        Group.new(slug: row[:slug], members: row[:members], bundles: bundles || [],
          cyclic: bundles.nil?, link: row[:link])
      end
    end

    # Ad-hoc directories are slugged the way the server slugs its own ephemeral
    # mounts, and deduped, so two directories sharing a basename stay distinct.
    #
    # A directory that arrived as an @ref keeps the slug it is registered under.
    # Deriving it from the basename instead would name it `.okf` — the conventional
    # container, and therefore the basename of nearly every registered bundle — so
    # `okf-tui @okf-site @okf-mkt` would list @okf and @okf-2, having discarded both
    # names that were typed. okf hit exactly this in its hub and fixed it the same
    # way. Still deduped: a slug is unique in a registry, but a ref-named bundle and
    # a plain directory in the same argv can still collide.
    def ad_hoc_entries
      taken = []
      @dirs.each_with_index.map do |dir, index|
        expanded = File.expand_path(dir)
        registered = @ref_slugs[expanded]
        slug = OKF::Registry.dedupe(registered || File.basename(expanded), taken) # dedupe slugifies
        taken << slug
        build_entry(slug: slug, dir: expanded, default: index.zero?,
          registered: !registered.nil?, missing: !File.directory?(expanded))
      end
    end

    def build_entry(slug:, dir:, default:, registered:, missing:, link: nil)
      entry = Entry.new(slug: slug, dir: dir, default: default, registered: registered, link: link)

      if missing
        entry.error = "directory is gone"
      else
        begin
          entry.model = Model.new(dir, slug: slug)
        rescue StandardError => e
          entry.error = e.message
        end
      end

      entry
    end
  end
end
