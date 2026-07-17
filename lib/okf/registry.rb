# frozen_string_literal: true

require "json"

module OKF
  # A persistent, ordered registry of bundle references — the kernel behind the
  # multi-bundle server. It is a plain JSON file (no database) under $OKF_HOME
  # (default ~/.okf), so `okf registry set`/`del` and a later bare `okf server`
  # share one on-disk list. Part of the shell — it reads and writes a file.
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

    HOME_ENV = "OKF_HOME"
    DEFAULT_HOME = "~/.okf"

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

      def load(home: nil)
        new(path(home: home))
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

    def initialize(path)
      @path = path
      @entries = []
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
      entry = get(self.class.normalize(slug))
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
      entry = get(self.class.normalize(old_slug))
      raise OKF::Error, "no such bundle: #{old_slug}" unless entry

      slug = explicit_slug(new_slug, entry)
      entry.slug = slug
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
      return nil unless target

      @entries.delete(target)
      write
      target
    end

    private

    # A basename-derived slug: silently deduped with a numeric suffix, around the
    # reserved names as well as the taken ones — so a directory named all/
    # registers as "all-2". This is the minting path, where the gem invents a name
    # and a suffix is expected; #explicit_slug refuses instead, because there the
    # name is the user's.
    def unique_slug(base, skip)
      taken = @entries.reject { |entry| entry.equal?(skip) }.map(&:slug)
      self.class.dedupe(base, taken + RESERVED_SLUGS)
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

      taken = @entries.reject { |entry| entry.equal?(skip) }.map(&:slug)
      # Refusing is the "never substitute a name you chose" rule, but a refusal
      # with no way forward is a dead end: the slug is spoken for by another
      # entry, so say which move frees it.
      raise OKF::Error, "slug already taken: #{slug} (rename or remove that entry first)" if taken.include?(slug)

      slug
    end

    def read
      return unless File.exist?(@path)

      data = JSON.parse(File.read(@path, encoding: "UTF-8"))
      rows = data.is_a?(Hash) ? Array(data["bundles"]) : Array(data) # bare array: the original shape
      @entries = rows.map { |row| entry_from(row) }
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
      Entry.new(row["slug"], row["path"], row["title"] || File.basename(row["path"]))
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
      rows = @entries.map { |entry| { "slug" => entry.slug, "path" => entry.path, "title" => entry.title } }
      payload = { "bundles" => rows }
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
