# frozen_string_literal: true

require "json"

module OKF
  # A persistent, ordered registry of bundle references — the kernel behind the
  # multi-bundle server. It is a plain JSON file (no database) under $OKF_HOME
  # (default ~/.okf), so `okf registry set`/`del` and a later bare `okf server`
  # share one on-disk list. Insertion order is preserved; the server opens the
  # explicitly chosen default (falling back to the first entry). Part of the
  # shell — it reads and writes a file.
  #
  #   registry = OKF::Registry.load
  #   registry.add("docs")               # persists, returns the Entry
  #   registry.default = "docs"           # which bundle a bare `okf server` opens
  #   registry.rename("docs", "handbook") # new slug, same path; the default follows
  #   registry.default                    # => the chosen Entry (first when unset)
  #   registry.listing                    # => [{ slug:, title:, path:, default: }]
  #
  # On disk: { "default" => slug (optional), "bundles" => [ { "slug" => …,
  # "path" => absolute dir, "title" => label } ] }. A bare array (the original
  # shape) still reads — it simply carries no default.
  class Registry
    # One registered bundle: a unique +slug+, the absolute +path+ on disk, and a
    # human-readable +title+ ("parent/dir").
    Entry = Struct.new(:slug, :path, :title)

    HOME_ENV = "OKF_HOME"
    DEFAULT_HOME = "~/.okf"

    class << self
      # The registry file: $OKF_HOME/registry.json, $OKF_HOME defaulting to ~/.okf.
      # +home+ overrides the base directory (the CLI's --home flag). An empty
      # +home+ or env var counts as unset — expand_path("") would silently plant
      # the registry in the current directory.
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

      # +base+ slugified, then suffixed (-2, -3, …) until it avoids every slug in
      # +taken+.
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
      @default_slug = nil
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

    # The default bundle a bare `okf server` selects — the explicitly chosen one
    # (default=), falling back to the first registered when unset or when the
    # chosen slug no longer exists.
    def default
      get(@default_slug) || @entries.first
    end

    # Choose which bundle `/` opens. Persists; raises on an unknown slug. The
    # ask is normalized the way registration normalized it, so the name the user
    # typed at --as is the name that resolves here.
    def default=(slug)
      entry = get(self.class.normalize(slug))
      raise OKF::Error, "no such bundle: #{slug}" unless entry

      @default_slug = entry.slug
      write
    end

    # Give the bundle at +old_slug+ a new slug (its mount path and switcher name).
    # The new name is slugified; a collision with another entry raises rather than
    # silently suffixing — a rename is explicit. The default follows the rename.
    def rename(old_slug, new_slug)
      entry = get(self.class.normalize(old_slug))
      raise OKF::Error, "no such bundle: #{old_slug}" unless entry

      slug = explicit_slug(new_slug, entry)
      @default_slug = slug if @default_slug == entry.slug
      entry.slug = slug
      write
      entry
    end

    # One row per bundle for the CLI list: +dir+ is the on-disk directory, +mount+
    # the server path, +default+ the *effective* default (first when none is set),
    # +missing+ true when the registered directory no longer exists on disk.
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
    # +default: true+ also makes it the default. Persists, then returns the entry.
    def add(dir, as: nil, default: false)
      root = self.class.expand(dir.to_s)
      raise OKF::Error, "not a directory: #{dir}" unless File.directory?(root)

      # The label is path arithmetic; Folder.load would parse every markdown
      # file in the bundle to hand back its own basename.
      title = Bundle::Folder.label(root)
      entry = @entries.find { |candidate| candidate.path == root }
      if entry
        was = entry.slug
        entry.title = title
        if as
          entry.slug = explicit_slug(as, entry)
          @default_slug = entry.slug if @default_slug == was
        end
      else
        slug = as ? explicit_slug(as, nil) : unique_slug(File.basename(root), nil)
        entry = Entry.new(slug, root, title)
        @entries << entry
      end
      @default_slug = entry.slug if default
      write
      entry
    end

    # Remove the entry named by +slug+ (or whose path matches). Returns the removed
    # entry, or nil when nothing matched. Removing the default clears the choice —
    # the first remaining bundle takes over. Persists on change.
    def remove(slug)
      # Slug-or-dir, so the normalized reading comes *last*: "./docs" must mean
      # the directory while one is registered under that path, and only fall
      # back to naming the "docs" slug when no path matches.
      target = get(slug) ||
               @entries.find { |entry| entry.path == self.class.expand(slug.to_s) } ||
               get(self.class.normalize(slug))
      return nil unless target

      @entries.delete(target)
      @default_slug = nil if @default_slug == target.slug
      write
      target
    end

    private

    # A basename-derived slug: silently deduped with a numeric suffix.
    def unique_slug(base, skip)
      taken = @entries.reject { |entry| entry.equal?(skip) }.map(&:slug)
      self.class.dedupe(base, taken)
    end

    # An explicitly requested slug (--as, rename): normalized, and a collision
    # with another entry is an error, never a silent suffix. Nothing surviving
    # normalization is an error too — the same rule as a collision, since
    # answering `--as "***"` with the placeholder slug would substitute a name
    # the user did not choose.
    def explicit_slug(base, skip)
      slug = self.class.normalize(base)
      raise OKF::Error, "not a usable slug: #{base} (letters and digits, please)" if slug.empty?

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
      @default_slug = data["default"] if data.is_a?(Hash) && data["default"].is_a?(String)
      @entries = rows.map { |row| entry_from(row) }
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

    def malformed(detail)
      raise OKF::Error, "malformed registry at #{@path}: #{detail}"
    end

    # Write-to-temp then rename, so a concurrent reader (another verb, a booting
    # server) never sees a torn file — the same promotion the bundle Writer uses.
    # Two racing writers stay last-writer-wins; the registry is a per-user file.
    def write
      FileUtils.mkdir_p(File.dirname(@path))
      rows = @entries.map { |entry| { "slug" => entry.slug, "path" => entry.path, "title" => entry.title } }
      payload = {}
      payload["default"] = @default_slug if @default_slug
      payload["bundles"] = rows
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
    end
  end
end
