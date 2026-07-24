# frozen_string_literal: true

module OKF
  class Bundle
    # An in-memory knowledge graph of a bundle: concepts become nodes and
    # bundle-relative markdown links become directed edges. Pure — built from an
    # OKF::Bundle (already in memory), does no I/O, and carries no presentation
    # concerns (sizing/colour belong to a renderer).
    #
    # Node fidelity is a build option, so the graph can ship only what a consumer
    # needs and let a server serve the rest on demand:
    #   * default (minimal: false, body: true) — full: id, type, title, description,
    #     tags, body.
    #   * body: false — everything but the body.
    #   * minimal: true — just id and title (the leanest payload to draw the graph).
    # Regardless of node fidelity, #type_index and #tag_index expose compact inverted
    # indexes ({ value => [id, …] }) computed from every concept, so a minimal client
    # can still colour by type and filter by tag.
    class Graph
      attr_reader :nodes, :edges, :type_index, :tag_index

      def self.build(bundle, minimal: false, body: true)
        # Best-effort (§9): a malformed concept never reaches here — the reader keeps
        # it in bundle.unparseable — so the rest of the bundle still renders. Inspect
        # bundle.unparseable to detect skips.
        concepts = bundle.concepts
        id_by_path = concepts.map { |concept| [ concept.path, concept.id ] }.to_h
        new(
          nodes: concepts.map { |concept| node_for(concept, minimal: minimal, body: body) },
          edges: edges_for(concepts, id_by_path, bundle.root),
          type_index: type_index_for(concepts),
          tag_index: tag_index_for(concepts)
        )
      end

      def self.node_for(concept, minimal: false, body: true)
        title = default(concept.title, File.basename(concept.id))
        return { id: concept.id, title: title } if minimal

        node = {
          id: concept.id,
          type: default(concept.type, "Untyped"),
          title: title,
          description: concept.description.to_s,
          tags: tags_of(concept)
        }
        node[:body] = concept.body.to_s.strip if body
        node
      end

      # Edges resolve by *path* — a markdown link is a file path — then map that path
      # to the concept living there and use its id, so a frontmatter `id` that differs
      # from the path still lands the edge on the right node.
      def self.edges_for(concepts, id_by_path, root)
        seen = Set.new
        concepts.each_with_object([]) do |concept, edges|
          Markdown::Links.extract(concept.body).each do |raw|
            resolved = Markdown::Links.resolve(raw, from: concept.path, bundle: root)
            next if resolved.nil?

            target_id = id_by_path[resolved]
            next if target_id.nil?
            next if target_id == concept.id
            next unless seen.add?([ concept.id, target_id ])

            edges << { source: concept.id, target: target_id }
          end
        end
      end

      # { type => [id, …] } over every concept (one type each, "Untyped" if blank).
      def self.type_index_for(concepts)
        concepts.each_with_object({}) do |concept, index|
          (index[default(concept.type, "Untyped")] ||= []) << concept.id
        end
      end

      # { tag => [id, …] } over every concept (a concept contributes 0..n tags).
      def self.tag_index_for(concepts)
        concepts.each_with_object({}) do |concept, index|
          tags_of(concept).each { |tag| (index[tag.to_s] ||= []) << concept.id }
        end
      end

      def self.tags_of(concept)
        concept.tags.is_a?(Array) ? concept.tags : []
      end

      # Blank, not just nil: §9.2 makes a whitespace-only `type` as non-conformant
      # as a missing one (the validator says so with the same OKF.blank?), so the
      # index must not sort them into different buckets. Otherwise `type: "  "`
      # earns its own row, labelled with spaces, next to Untyped.
      def self.default(value, fallback)
        OKF.blank?(value) ? fallback : value.to_s
      end

      def initialize(nodes:, edges:, type_index: {}, tag_index: {})
        @nodes = nodes
        @edges = edges
        @type_index = type_index
        @tag_index = tag_index
      end

      def to_h
        { nodes: nodes, edges: edges }
      end

      # Ids of nodes with graph degree 0 — no cross-links in *or* out. These are the
      # "loose" files: they float in a rendered graph, reachable (if at all) only via
      # an index.md listing, which is not an edge. Distinct from an orphan, a
      # *reachability* notion that an index listing satisfies — a concept can be
      # indexed (not an orphan) yet still be unlinked here. Preserves node order.
      def unlinked_ids
        @unlinked_ids ||= begin
          linked = Set.new
          edges.each { |edge| linked << edge[:source] << edge[:target] }
          nodes.map { |node| node[:id] }.reject { |id| linked.include?(id) }
        end
      end
    end
  end
end
