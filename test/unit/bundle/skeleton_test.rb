# frozen_string_literal: true

require "test_helper"
require "okf"

class OKF::Bundle::SkeletonTest < OKF::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("okf-skeleton-test")
  end

  teardown do
    FileUtils.rm_rf(@tmpdir)
  end

  # ── the directories ──

  test "dirs carry direct counts, at-or-below subtree counts, and the parent link" do
    write("flows/a.md", note("A"))
    write("flows/deep/b.md", note("B"))
    write("flows/deep/c.md", note("C"))
    write("top.md", note("Top"))

    rows = skeleton.dirs

    assert_equal [ ".", "flows", "flows/deep" ], rows.map { |row| row[:dir] }
    assert_equal({ "." => 1, "flows" => 1, "flows/deep" => 2 }, counts(rows, :count))
    assert_equal({ "." => 4, "flows" => 3, "flows/deep" => 2 }, counts(rows, :subtree))
    assert_equal [ nil, ".", "flows" ], rows.map { |row| row[:parent] }
  end

  test "an intermediate directory holding nothing directly still appears, so the tree connects" do
    write("a/b/c/leaf.md", note("Leaf"))

    rows = skeleton.dirs

    assert_equal [ ".", "a", "a/b", "a/b/c" ], rows.map { |row| row[:dir] }
    assert_equal({ "." => 0, "a" => 0, "a/b" => 0, "a/b/c" => 1 }, counts(rows, :count))
    assert_equal({ "." => 1, "a" => 1, "a/b" => 1, "a/b/c" => 1 }, counts(rows, :subtree))
  end

  # ── the arcs ──

  test "cross-directory links aggregate into one weighted arc per ordered pair" do
    write("flows/a.md", note("A", "[x](../refs/x.md) [y](../refs/y.md)"))
    write("flows/b.md", note("B", "[x](../refs/x.md)"))
    write("refs/x.md", note("X"))
    write("refs/y.md", note("Y"))

    assert_equal [ { source: "flows", target: "refs", weight: 3 } ], skeleton.arcs
  end

  test "a directory's own links stay off the arcs and land on its row as internal" do
    write("flows/a.md", note("A", "[b](b.md)"))
    write("flows/b.md", note("B", "[a](a.md)"))

    assert_equal [], skeleton.arcs
    assert_equal 2, skeleton.dirs.find { |row| row[:dir] == "flows" }[:internal]
  end

  test "arcs sort by weight descending, then by source and target" do
    write("a/one.md", note("One", "[t](../t/t.md)"))
    write("b/one.md", note("One", "[t](../t/t.md)"))
    write("b/two.md", note("Two", "[t](../t/t.md)"))
    write("t/t.md", note("T"))

    assert_equal [ %w[b t], %w[a t] ], skeleton.arcs.map { |arc| [ arc[:source], arc[:target] ] }
  end

  test "arcs_above cuts by weight" do
    arcs = [ { weight: 5 }, { weight: 3 }, { weight: 1 } ]

    assert_equal [ 5, 3 ], OKF::Bundle::Skeleton.arcs_above(arcs, 3).map { |arc| arc[:weight] }
    assert_equal [], OKF::Bundle::Skeleton.arcs_above(arcs, 9)
  end

  # ── the suggested cut ──

  test "the suggested cut targets 1.5 arcs per directory, not a fixed weight" do
    # 12 arcs over 4 dirs. The target is max(ceil(4 * 1.5), 8) = 8, so the cut is
    # the 8th arc's weight and everything at or above it survives.
    arcs = (1..12).map { |n| { weight: 13 - n } } # weights 12 down to 1

    assert_equal 5, OKF::Bundle::Skeleton.suggested_cut(arcs, 4)
    assert_equal 8, OKF::Bundle::Skeleton.arcs_above(arcs, 5).size
  end

  test "the cut scales with the directory count, which is what keeps density constant" do
    arcs = (1..200).map { |n| { weight: 201 - n } }

    wide = OKF::Bundle::Skeleton.suggested_cut(arcs, 40)  # target 60
    narrow = OKF::Bundle::Skeleton.suggested_cut(arcs, 8) # target 12

    assert_operator wide, :<, narrow, "more directories earns a looser cut, not a tighter one"
    assert_equal 60, OKF::Bundle::Skeleton.arcs_above(arcs, wide).size
    assert_equal 12, OKF::Bundle::Skeleton.arcs_above(arcs, narrow).size
  end

  test "the floor keeps a small bundle from being cut down to nothing" do
    arcs = (1..10).map { |n| { weight: 11 - n } }

    # 2 dirs would target 3 arcs; the floor of 8 overrides it.
    assert_equal 8, OKF::Bundle::Skeleton.arcs_above(arcs, OKF::Bundle::Skeleton.suggested_cut(arcs, 2)).size
  end

  test "a cut keeps ties rather than breaking one arbitrarily" do
    arcs = [ { weight: 9 } ] + Array.new(11) { { weight: 4 } } # target 8 lands mid-tie

    cut = OKF::Bundle::Skeleton.suggested_cut(arcs, 2)

    assert_equal 4, cut
    assert_equal 12, OKF::Bundle::Skeleton.arcs_above(arcs, cut).size, "every tied arc survives together"
  end

  test "fewer arcs than the target needs no cut at all" do
    assert_equal 1, OKF::Bundle::Skeleton.suggested_cut([ { weight: 5 } ], 3)
    assert_equal 1, OKF::Bundle::Skeleton.suggested_cut([], 3)
  end

  test "a built skeleton carries its own suggested cut" do
    write("flows/a.md", note("A", "[x](../refs/x.md)"))
    write("refs/x.md", note("X"))

    assert_equal 1, skeleton.suggested_cut, "two dirs and one arc is under the floor"
  end

  # ── the edges ──

  test "keep_at 0 means a node's strongest link, which no cut can take away" do
    write("hub.md", note("Hub", "[a](a.md) [b](b.md) [c](c.md)"))
    write("a.md", note("A", "[b](b.md)"))
    write("b.md", note("B"))
    write("c.md", note("C"))

    kept = OKF::Bundle::Skeleton.edges_within(skeleton.edges, 0)

    assert_includes kept.map { |edge| [ edge[:source], edge[:target] ] }, %w[hub a]
    refute_empty kept
  end

  test "a full cut keeps every edge, and cuts compose monotonically" do
    build_wide

    sizes = [ 0, 25, 50, 75, 100 ].map { |cut| OKF::Bundle::Skeleton.edges_within(skeleton.edges, cut).size }

    assert_equal skeleton.edges.size, sizes.last
    assert_equal sizes.sort, sizes, "a wider cut can only keep more"
  end

  # The closed form in .keep_at is an algebraic rearrangement of the sparsifier's
  # definition — keep a node's top ceil(degree ** cut/100) neighbours — and the
  # rearrangement is exactly the kind that is right for every case a hand-picked
  # example covers and wrong at one boundary (cut/100 landing on an integer power).
  # So the definition is re-run here, brute force, over every cut, and the two are
  # asserted equal edge for edge.
  test "keep_at agrees with the sparsifier it is derived from, at every cut" do
    build_wide
    edges = skeleton.edges

    (0..100).each do |cut|
      assert_equal brute_force(cut).sort, pairs(OKF::Bundle::Skeleton.edges_within(edges, cut)).sort,
        "cut #{cut} disagrees with the definition"
    end
  end

  test "to_h carries what the drawn views read, and leaves the per-edge cuts out" do
    write("a.md", note("A", "[b](b.md)"))
    write("b.md", note("B"))

    hash = skeleton.to_h

    assert_equal %i[dirs arcs suggested_cut].sort, hash.keys.sort
    refute hash.key?(:edges), "the per-edge cuts ride inline with the graph, not in this payload"
    assert_nothing_raised { JSON.generate(hash) }
  end

  test "cuts_for lines the per-edge cuts up with a graph's own edge list" do
    build_wide
    graph_edges = document.graph(minimal: true).edges

    cuts = skeleton.cuts_for(graph_edges)

    assert_equal graph_edges.size, cuts.size
    assert cuts.all?(Integer)
    # Matched on the pair, not the index — so a reordered list still lines up.
    shuffled = graph_edges.reverse
    assert_equal skeleton.cuts_for(graph_edges).reverse, skeleton.cuts_for(shuffled)
  end

  test "the boot set — every edge at cut 0 — touches every linked concept" do
    # This is what makes it usable as a layout's first pass: it is not a sample,
    # it is each node's strongest link, so no linked concept is left unplaced.
    build_wide
    boot = OKF::Bundle::Skeleton.edges_within(skeleton.edges, 0)

    linked = skeleton.edges.flat_map { |edge| [ edge[:source], edge[:target] ] }.uniq.sort
    spanned = boot.flat_map { |edge| [ edge[:source], edge[:target] ] }.uniq.sort

    assert_equal linked, spanned
    assert_operator boot.size, :<, skeleton.edges.size, "and it is a real reduction"
  end

  private

  # A bundle wide enough for the cut to have somewhere to bite: degrees from 1 to
  # 6, so ceil(degree ** cut/100) actually changes as the cut moves.
  def build_wide
    write("hub.md", note("Hub", "[a](a.md) [b](b.md) [c](c.md) [d](d.md) [e](e.md) [f](f.md)"))
    write("a.md", note("A", "[b](b.md) [c](c.md) [d](d.md)"))
    write("b.md", note("B", "[c](c.md)"))
    write("c.md", note("C", "[d](d.md)"))
    write("d.md", note("D"))
    write("e.md", note("E", "[f](f.md)"))
    write("f.md", note("F"))
  end

  # The sparsifier, spelled as its definition rather than as its solution.
  def brute_force(cut)
    graph = document.graph(minimal: true)
    ids = graph.nodes.map { |node| node[:id] }
    edges = graph.edges.map { |edge| [ edge[:source], edge[:target] ] }
    neighbours = OKF::Bundle::Skeleton.neighbours_for(ids, edges)

    keep = ids.each_with_object({}) do |id, out|
      budget = (neighbours[id].size**(cut / 100.0)).ceil
      neighbours[id].sort_by { |other| [ -neighbours[other].size, other ] }
                    .first(budget).each { |other| out[[ id, other ].sort] = true }
    end
    edges.select { |source, target| keep[[ source, target ].sort] }
  end

  def pairs(edges)
    edges.map { |edge| [ edge[:source], edge[:target] ] }
  end

  def counts(rows, key)
    rows.map { |row| [ row[:dir], row[key] ] }.to_h
  end

  def skeleton
    OKF::Bundle::Skeleton.build(document)
  end

  def document
    OKF::Bundle::Reader.read(@tmpdir)
  end

  def note(title, body = "no links")
    "---\ntype: Note\ntitle: #{title}\n---\n\n#{body}\n"
  end

  def write(path, content)
    target = File.join(@tmpdir, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
end
