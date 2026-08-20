# frozen_string_literal: true

module OKF
  class Bundle
    # The graph reduced to what a reader can hold in their head. Pure — built from
    # an OKF::Bundle::Graph's nodes and edges, does no I/O, and decides nothing
    # about how any of it is drawn.
    #
    # A dense bundle is not dense in the way a hub-and-spoke picture is. Measured
    # on a 47-concept bundle with 227 links: the top hub takes 13 inbound and the
    # median takes 4, so there is no 80/20 to exploit — dropping two thirds of the
    # concepts still leaves 53 edges. The density lives *between directories*:
    # 173 of those 227 links (76%) cross a directory boundary, and they collapse
    # into 50 directory-to-directory arcs of which the top ten carry half the mass.
    # That is the reduction worth drawing, and it is why #arcs exists at all.
    #
    # ── the two things it produces, and who reads them ──
    #
    #   dirs + arcs   the reduction, as counts: one row per directory, one
    #                 weighted arc per ordered pair. Printed by
    #                 `okf graph --traffic`, with cohesion derived from them.
    #   edges         every link with the cut it survives (`keep_at`). Nothing
    #                 prints these — they are what lets the graph page lay a
    #                 large bundle out on its strongest links first.
    #
    # Both are emitted *unthresholded*, and #suggested_cut names where to cut
    # rather than cutting, so a caller narrows the picture without this class
    # having to know what a picture is.
    #
    # Directories come off the concept *id* (OKF.dir_of), not the file path, so
    # this agrees with #catalog, #hubs and the `--dir` filter. Bundle#directory_index
    # groups by path instead — deliberately, since an index.md is a physical
    # listing — so the two disagree for a concept whose frontmatter `id` moves it.
    # This side follows the id because the edges do.
    class Skeleton
      attr_reader :dirs, :arcs, :edges

      def self.build(bundle)
        graph = bundle.graph(minimal: true)
        ids = graph.nodes.map { |node| node[:id] }
        pairs = graph.edges.map { |edge| [ edge[:source], edge[:target] ] }
        dir_by_id = ids.map { |id| [ id, OKF.dir_of(id) ] }.to_h

        new(
          dirs: dirs_for(dir_by_id, pairs),
          arcs: arcs_for(dir_by_id, pairs),
          edges: edges_for(pairs, neighbours_for(ids, pairs))
        )
      end

      # ── the cuts (see above) ──

      def self.arcs_above(arcs, weight)
        arcs.select { |arc| arc[:weight] >= weight }
      end

      def self.edges_within(edges, keep_at)
        edges.select { |edge| edge[:keep_at] <= keep_at }
      end

      # ── the directories ──

      # One row per directory that holds a concept, plus every ancestor up to the
      # root, so the tree stays connected through a directory that holds nothing
      # directly. `count` is direct and `subtree` is at-or-below — the same pair
      # `okf dirs` prints, and for the same reason: a direct count alone cannot
      # say where the mass is once the listing is cut off at a depth.
      def self.dirs_for(dir_by_id, pairs)
        direct = Hash.new(0)
        dir_by_id.each_value { |dir| direct[dir] += 1 }
        internal = Hash.new(0)
        pairs.each do |source, target|
          from = dir_by_id[source]
          internal[from] += 1 if from == dir_by_id[target]
        end

        every_dir(direct.keys).map do |dir|
          { dir: dir, parent: parent_of(dir), count: direct[dir],
            subtree: direct.reduce(0) { |sum, (other, n)| under?(other, dir) ? sum + n : sum },
            internal: internal[dir] }
        end
      end

      # The cross-directory link mass, aggregated. Directed and never a self-arc:
      # a directory's internal links are carried on its own row (`internal`),
      # because an arc from a box to itself is a loop the eye has to untangle to
      # learn a number the box could simply have carried.
      def self.arcs_for(dir_by_id, pairs)
        weights = Hash.new(0)
        pairs.each do |source, target|
          from = dir_by_id[source]
          to = dir_by_id[target]
          weights[[ from, to ]] += 1 unless from == to
        end

        weights.map { |(from, to), weight| { source: from, target: to, weight: weight } }
               .sort_by { |arc| [ -arc[:weight], arc[:source], arc[:target] ] }
      end

      # ── where to cut ──

      # The arc cut that leaves a readable picture, chosen from the *shape* of
      # the bundle rather than fixed. A fixed cut cannot work: measured at
      # weight 3 across ten bundles it left 2 arcs on one and 136 on another —
      # too tight to be a picture at one end, no reduction at all at the other.
      #
      # What stays constant when a bundle grows is not the arc count but the
      # arcs *per box*: a node-link diagram reads at roughly one to two edges
      # per node regardless of size. So the target is 1.5 arcs per directory,
      # and the cut is whatever weight delivers it — 22 arcs over 13 directories
      # on one bundle, 191 over 95 on another, both about the same density.
      #
      # The floor of 8 is for the small end, where 1.5-per-box would cut a
      # ten-arc bundle down to something that no longer shows how it is joined
      # up. Ties are kept rather than broken, so the result is *at least* the
      # target — the alternative is dropping one of two arcs that weigh the
      # same, which is an arbitrary choice presented as a threshold.
      def self.suggested_cut(arcs, dir_count)
        target = [ (dir_count * 1.5).ceil, 8 ].max
        return 1 if arcs.empty? || arcs.size <= target

        arcs[target - 1][:weight]
      end

      # ── the edges, each with the cut it survives ──

      # The local-degree sparsifier (Lindner et al.): every concept keeps its own
      # most-connected neighbours, and an edge survives if *either* end kept it.
      # The union is the point — it is what stops a sparsifier from stranding the
      # quiet half of the bundle, which a global "drop the weakest edges" rule
      # does immediately.
      #
      # Not the disparity filter, the usual name in this territory: that one reads
      # an edge's weight against its endpoint's total, and every link here weighs
      # exactly 1, which makes every proportion identical and the filter a coin
      # toss. Weighted-graph tools do not transfer to an unweighted graph just
      # because both are graphs.
      #
      # `keep_at` is the smallest cut (0–100) at which the edge appears, so the
      # consumer's whole job is `keep_at <= n`. An edge to a node's single most
      # connected neighbour keeps at 0 and is therefore never cut away: the
      # skeleton always spans every linked concept.
      def self.edges_for(pairs, neighbours)
        order = ordered_neighbours(neighbours)
        pairs.map do |source, target|
          { source: source, target: target,
            keep_at: [ keep_at(order, neighbours, source, target),
                       keep_at(order, neighbours, target, source) ].min }
        end
      end

      # Where `other` sits in `id`'s neighbours (1 = most connected), turned into
      # the smallest cut that reaches it. Position 1 needs no budget at all; past
      # that, a cut of n keeps ceil(degree ** n/100) neighbours, so the answer is
      # the least n satisfying that — solved directly rather than searched, and
      # pinned against the definition it came from in the unit test.
      def self.keep_at(order, neighbours, id, other)
        position = order[id].index(other) + 1
        return 0 if position == 1

        degree = neighbours[id].size
        (100 * Math.log(position - 1) / Math.log(degree)).floor + 1
      end

      def self.ordered_neighbours(neighbours)
        neighbours.each_with_object({}) do |(id, set), out|
          out[id] = set.sort_by { |other| [ -neighbours[other].size, other ] }
        end
      end

      # Undirected neighbour sets. A link is structure regardless of which end
      # authored it, and a concept every page cites but that cites nothing back
      # is as central as one that does the citing.
      def self.neighbours_for(ids, pairs)
        sets = ids.map { |id| [ id, Set.new ] }.to_h
        pairs.each do |source, target|
          sets[source] << target if sets.key?(source) && sets.key?(target)
          sets[target] << source if sets.key?(source) && sets.key?(target)
        end
        sets
      end

      # ── path arithmetic (pure; the bundle root is ".") ──

      def self.every_dir(dirs)
        seen = {}
        dirs.each do |dir|
          current = dir
          loop do
            seen[current] = true
            break if current == "."

            current = parent_of(current)
          end
        end
        seen.keys.sort_by { |dir| dir == "." ? "" : dir }
      end

      def self.parent_of(dir)
        return nil if dir == "."

        File.dirname(dir)
      end

      # At or below — the same rule `--dir` is answered against, so a row's
      # `subtree` and what `--dir <that row>` returns can never disagree.
      def self.under?(dir, ancestor)
        return true if ancestor == "."

        dir == ancestor || dir.start_with?("#{ancestor}/")
      end

      def initialize(dirs:, arcs:, edges:)
        @dirs = dirs
        @arcs = arcs
        @edges = edges
      end

      def suggested_cut
        @suggested_cut ||= self.class.suggested_cut(arcs, dirs.size)
      end

      # The `keep_at` of each edge in +edges+, in *its* order — so a caller
      # holding an OKF::Bundle::Graph can line the two up. Matched on the pair
      # rather than by index: both lists derive from the same graph and so are
      # already parallel today, and an index-aligned read would go wrong in
      # silence on the day one of them stops being built that way.
      def cuts_for(graph_edges)
        by_pair = edges.each_with_object({}) { |edge, out| out[[ edge[:source], edge[:target] ]] = edge[:keep_at] }
        graph_edges.map { |edge| by_pair[[ edge[:source], edge[:target] ]] || 0 }
      end

      # What the drawn views read. `edges` stays out: it is per-link data whose
      # only consumer needs it at boot, before any fetch could answer — so it
      # rides inline with the graph instead (see OKF::Render::Graph#edge_cuts_json).
      def to_h
        { dirs: dirs, arcs: arcs, suggested_cut: suggested_cut }
      end
    end
  end
end
