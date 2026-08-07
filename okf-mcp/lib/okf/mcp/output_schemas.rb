# frozen_string_literal: true

module OKF
  module MCP
    # The shape each tool answers with, declared so a host consumes a result
    # instead of parsing a blob and guessing. Every tool emits both: the JSON
    # text in `content` (what a pre-2025-06-18 client reads) and the same
    # object in `structuredContent`.
    #
    # They live in one table rather than beside each tool because the useful
    # question is comparative — *every* list view carries `total`, and reading
    # them together is what keeps that true. `define_tool` looks the name up;
    # a tool with no entry declares no schema, which is `read_concept`, whose
    # answer is markdown and has no object shape to describe.
    #
    # Two rules hold them honest. `required` is the **intersection** across a
    # tool's variants, never one variant's keys — `lint` answers two shapes and
    # `graph` three, so only `bundle` (and `view`) survive. And the row arrays
    # are typed as arrays of objects but their *items* are left open, because
    # `fields` projects a row down to what the caller asked for; naming the row
    # properties here would make a projection a schema violation.
    #
    # `test/integration/output_schema_test.rb` runs every variant with the
    # SDK's result validation switched on, so drift fails there rather than in
    # somebody's host.
    module OutputSchemas
      ROWS = { type: "array", items: { type: "object" } }.freeze
      COUNT = { type: "integer" }.freeze
      SLUG = { type: "string" }.freeze

      # `unparseable` rides along on any bundle-scoped view whose reader hit a
      # file it could not parse, so it is optional everywhere and required
      # nowhere.
      UNPARSEABLE = { type: "integer" }.freeze

      SCHEMAS = {
        "list_bundles" => {
          properties: {
            backend: { type: "object" },
            registry_source: { type: %w[string null] },
            default: SLUG,
            groups: { type: "array" },
            total: COUNT,
            bundles: ROWS
          },
          required: %w[backend total bundles]
        },
        "dirs" => {
          properties: { bundle: SLUG, total: COUNT, dirs: ROWS, unparseable: UNPARSEABLE },
          required: %w[bundle total dirs]
        },
        "index" => {
          properties: { bundle: SLUG, total: COUNT, dirs: ROWS, unparseable: UNPARSEABLE },
          required: %w[bundle total dirs]
        },
        "search" => {
          properties: {
            query: { type: "array", items: { type: "string" } },
            # Resolved, not echoed — `fuzzy` picks the index without being
            # asked — so it is always present and belongs in `required`.
            engine: { type: "string", enum: %w[scan index] },
            bundles: ROWS,
            total: COUNT,
            results: ROWS,
            unparseable: UNPARSEABLE
          },
          required: %w[query engine bundles total results]
        },
        "catalog" => {
          properties: { bundle: SLUG, total: COUNT, concepts: ROWS, unparseable: UNPARSEABLE },
          required: %w[bundle total concepts]
        },
        # `total` is entries across every log file and `files` how many files
        # they came from — two different counts, both named, because one
        # standing for the other is what let an unbounded 119 KB answer read
        # as bounded.
        "log" => {
          properties: { bundle: SLUG, total: COUNT, files: COUNT, logs: ROWS },
          required: %w[bundle total files logs]
        },
        "validate" => {
          properties: {
            bundle: SLUG,
            conformant: { type: "boolean" },
            errors: ROWS,
            warnings: ROWS,
            counts: { type: "object" }
          },
          required: %w[bundle conformant errors warnings counts]
        },
        # Two shapes: the findings report, and `group: "folder"`'s file
        # listing. Only what both carry is required.
        "lint" => {
          properties: {
            bundle: SLUG,
            total: COUNT,
            healthy: { type: "boolean" },
            stats: { type: "object" },
            findings: ROWS,
            group: { type: "string" },
            files: ROWS,
            unparseable: UNPARSEABLE
          },
          required: %w[bundle total]
        },
        # Three shapes — minimal, hubs, traffic — sharing only their identity.
        "graph" => {
          properties: {
            bundle: SLUG,
            view: { type: "string" },
            total_nodes: COUNT,
            total_edges: COUNT,
            nodes: ROWS,
            edges: ROWS,
            types: { type: "object" },
            tags: { type: "object" },
            total: COUNT,
            hubs: ROWS,
            cut: COUNT,
            total_arcs: COUNT,
            dirs: ROWS,
            arcs: ROWS,
            unparseable: UNPARSEABLE
          },
          required: %w[bundle view]
        }
      }.freeze

      def self.[](name)
        SCHEMAS[name.to_s]
      end
    end
  end
end
