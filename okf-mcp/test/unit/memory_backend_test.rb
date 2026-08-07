# frozen_string_literal: true

require "test_helper"

class MemoryBackendTest < OKF::TestCase
  setup do
    @dir = Dir.mktmpdir("okf-mcp-memory")
    File.write(File.join(@dir, "note.md"), "---\ntype: Note\ntitle: One\n---\n\nThe first body.\n")
    @backend = OKF::MCP::MemoryBackend.new
  end

  teardown do
    FileUtils.rm_rf(@dir)
  end

  test "refresh warms the residency and returns nothing — the backend duck type" do
    assert_nil @backend.refresh(@dir)
  end

  test "the folder is resident until the fingerprint moves" do
    first = @backend.folder(@dir)
    assert_same first, @backend.folder(@dir), "unchanged files, same parsed folder"

    write_note("A different body.", mtime: Time.now + 2)
    second = @backend.folder(@dir)
    refute_same first, second
    assert_match(/A different body/, second.bundle.concepts.first.body)
  end

  # The warm-under-lock rule covers every memo a tool reads off the shared
  # bundle. `Bundle#directories` joined that set when the dir refusal moved to
  # it, and an unwarmed `||=` raced from the HTTP transport's threads.
  test "folder warms the directories memo with the id maps, under the lock" do
    folder = @backend.folder(@dir)
    refute_nil folder.bundle.instance_variable_get(:@directories),
      "check_dir! reads this memo from transport threads; build it under the residency lock"
  end

  test "the corpus is held across index queries and dropped when a member changes" do
    pairs = [ [ "scratch", @dir ] ]
    first = @backend.search_pairs(pairs, [ "body" ], engine: "index")
    assert_equal 1, first.length

    # Held: the same corpus answers again (observed via object identity of the
    # held folders — a rebuild would re-read the folder).
    resident = @backend.folder(@dir)
    @backend.search_pairs(pairs, [ "body" ], engine: "index")
    assert_same resident, @backend.folder(@dir)

    write_note("A rewritten body with zeppelins.", mtime: Time.now + 2)
    rows = @backend.search_pairs(pairs, [ "zeppelins" ], engine: "index")
    assert_equal 1, rows.length, "the held index outliving its set would have missed the edit"
  end

  test "the scan answers by default and fuzzy routes to the index" do
    pairs = [ [ "scratch", @dir ] ]
    scan = @backend.search_pairs(pairs, [ "first" ])
    assert_equal 1, scan.length

    # One substitution, inside the 0.2 × length edit budget (a transposition
    # like "frist" costs two edits and would miss).
    fuzzy = @backend.search_pairs(pairs, [ "furst" ], fuzzy: true)
    assert_equal 1, fuzzy.length
  end

  # The fingerprint's promise is that results reflect the current files. A
  # second write inside one filesystem timestamp tick (1 s on HFS+, NFS and
  # Docker bind mounts) leaves the file list and the newest mtime unmoved, so
  # the length of the content is the cheap signal that catches it. No utime
  # here on purpose — that workaround is what hid this from the suite.
  test "a same-timestamp edit that changes the content is seen" do
    first = @backend.folder(@dir)
    mtime = File.mtime(File.join(@dir, "note.md"))

    path = File.join(@dir, "note.md")
    File.write(path, "---\ntype: Note\ntitle: One\n---\n\nA rewritten body, of a different length entirely.\n")
    File.utime(mtime, mtime, path) # the coarse-granularity filesystem, simulated exactly

    refute_same first, @backend.folder(@dir)
    assert_match(/rewritten body/, @backend.folder(@dir).bundle.concepts.first.body)
  end

  # The kernel's Reader rescues SystemCallError per file so one vanished file
  # never breaks a read; the cache check must not reintroduce that failure.
  # Stubbing the glob is what makes the race deterministic — the real one (a
  # `git checkout` mid-call) cannot be timed from a test.
  test "a path that vanished between the glob and the stat does not raise" do
    ghost = File.join(@dir, "ghost.md")
    Dir.stub(:glob, [ File.join(@dir, "note.md"), ghost ]) do
      assert_kind_of Array, @backend.send(:fingerprint, @dir)
    end
  end

  test "the corpus cache is bounded rather than growing per bundle subset" do
    roots = Array.new(OKF::MCP::MemoryBackend::MAX_CORPORA + 2) do |i|
      dir = Dir.mktmpdir("okf-mcp-corpus-#{i}")
      File.write(File.join(dir, "note.md"), "---\ntype: Note\ntitle: N#{i}\n---\n\nBody #{i}.\n")
      dir
    end
    begin
      roots.each_with_index { |root, i| @backend.search_pairs([ [ "b#{i}", root ] ], [ "body" ], engine: "index") }
      held = @backend.instance_variable_get(:@corpora).size
      assert_operator held, :<=, OKF::MCP::MemoryBackend::MAX_CORPORA
    ensure
      roots.each { |root| FileUtils.rm_rf(root) }
    end
  end

  # The corpus cache above has been bounded since it was written. This one was
  # bounded only by the served set being fixed at boot — which the registry
  # re-read ended: every root the registry has *ever* pointed at stayed keyed
  # here, each holding a parsed bundle with its id maps memoized. A long-lived
  # --http process whose operator repoints entries per branch grows until the
  # box swaps, taking every connected host down at once.
  test "roots the registry no longer serves are dropped from the residency" do
    gone = Dir.mktmpdir("okf-mcp-gone")
    File.write(File.join(gone, "note.md"), "---\ntype: Note\ntitle: Gone\n---\n\nA body.\n")
    begin
      @backend.folder(@dir)
      @backend.folder(gone)
      assert_equal 2, cached_roots.length

      @backend.retain([ @dir ])

      assert_equal [ @dir ], cached_roots, "a parsed bundle outlived the registry entry that named it"
    ensure
      FileUtils.rm_rf(gone)
    end
  end

  # The corpus cache pins the same parsed bundles the residency does — plus a
  # prepared index over each — so the prune has to reach both. With @cache
  # pruned and @corpora not, up to MAX_CORPORA corpora over dropped roots
  # stayed resident until other *index* queries happened to evict them, which
  # a scan-only workload never sends: the memory retain claims to release was
  # still held after every repoint.
  test "retain drops every corpus touching a root no longer served" do
    gone = Dir.mktmpdir("okf-mcp-gone")
    File.write(File.join(gone, "note.md"), "---\ntype: Note\ntitle: Gone\n---\n\nA body.\n")
    begin
      @backend.search_pairs([ [ "a", @dir ], [ "b", gone ] ], [ "body" ], engine: "index")
      @backend.search_pairs([ [ "a", @dir ] ], [ "body" ], engine: "index")
      assert_equal 2, @backend.instance_variable_get(:@corpora).size

      @backend.retain([ @dir ])

      keys = @backend.instance_variable_get(:@corpora).keys
      assert_equal [ [ @dir ] ], keys, "a corpus outlived a root the registry no longer names"
    ensure
      FileUtils.rm_rf(gone)
    end
  end

  test "retain keeps every served root, however many there are" do
    @backend.folder(@dir)
    @backend.retain([ @dir ])
    assert_equal [ @dir ], cached_roots, "a served bundle was evicted, so the next call re-parses it"
  end

  # The fingerprint is a freshness check *between* requests. Recomputing it on
  # every ask made one request walk the tree two or three times — a glob plus a
  # stat per markdown file, all of it inside the global lock — because a tool
  # asks the engine for the catalog and then reads the unparseable count off
  # the same folder.
  test "one request walks the tree once per root, however often it asks" do
    walks = 0
    counter = Module.new do
      define_method(:fingerprint) { |root| walks += 1; super(root) }
    end
    @backend.singleton_class.prepend(counter)

    @backend.during_request do
      3.times { @backend.folder(@dir) }
    end
    assert_equal 1, walks

    # …and the next request checks again, or the residency would go stale.
    @backend.during_request { @backend.folder(@dir) }
    assert_equal 2, walks
  end

  test "a reordered bundle list reuses the held corpus rather than rebuilding" do
    other = Dir.mktmpdir("okf-mcp-other")
    File.write(File.join(other, "note.md"), "---\ntype: Note\ntitle: Other\n---\n\nAnother body.\n")
    begin
      forward = [ [ "a", @dir ], [ "b", other ] ]
      backward = [ [ "b", other ], [ "a", @dir ] ]
      @backend.search_pairs(forward, [ "body" ], engine: "index")
      @backend.search_pairs(backward, [ "body" ], engine: "index")

      assert_equal 1, @backend.instance_variable_get(:@corpora).size
    ensure
      FileUtils.rm_rf(other)
    end
  end

  test "catalog filters by type, tag, dir prefix and status" do
    FileUtils.mkdir_p(File.join(@dir, "deep"))
    File.write(File.join(@dir, "deep", "two.md"),
      "---\ntype: Guide\ntitle: Two\ntags: [x]\nstatus: draft\n---\n\nBody.\n")

    assert_equal [ "deep/two" ], @backend.catalog(@dir, type: "Guide").map { |row| row[:id] }
    assert_equal [ "deep/two" ], @backend.catalog(@dir, tag: "x").map { |row| row[:id] }
    assert_equal [ "deep/two" ], @backend.catalog(@dir, dir: "deep").map { |row| row[:id] }
    assert_equal [ "note" ], @backend.catalog(@dir, dir: ".").map { |row| row[:id] }
    assert_equal [ "deep/two" ], @backend.catalog(@dir, status: "draft").map { |row| row[:id] }
  end

  private

  # An edit the fingerprint must see: same file list, newer mtime. The explicit
  # utime matters — two writes inside one clock tick would otherwise fingerprint
  # identically and the test would pass or fail by filesystem timestamp
  # granularity.
  def write_note(body, mtime:)
    path = File.join(@dir, "note.md")
    File.write(path, "---\ntype: Note\ntitle: One\n---\n\n#{body}\n")
    File.utime(mtime, mtime, path)
  end

  def cached_roots
    @backend.instance_variable_get(:@cache).keys
  end
end
