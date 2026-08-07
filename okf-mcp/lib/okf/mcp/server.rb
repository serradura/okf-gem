# frozen_string_literal: true

require "date"
require "json"
require "mcp"

require_relative "../mcp"
require_relative "output_schemas"
require_relative "resources"

module OKF
  module MCP
    # Builds the MCP::Server definition shared by every transport: ten
    # read-only tools mapped straight onto the kernel's library API, plus the
    # two consuming prompts. The surface is deliberately minimal —
    # agents do better with few, well-described tools, and dirs + index +
    # search compose to most retrieval — so adding a tool here is a design
    # decision, not a convenience.
    #
    # Every list output is bounded with a visible `total`; no silent
    # truncation, ever. `total` means one thing on every tool: **how many rows
    # the request matched**, before any `limit` cut them. dirs and index used to
    # report the whole bundle's directory count instead, so a narrowing stayed
    # visible — defensible alone, wrong as a set, and against the promise above
    # it read as rows withheld by a tool that takes no limit at all.
    #
    # The descriptions carry the skill's doctrine, because they are the only
    # playbook a Desktop host ever sees.
    module Server
      # Cap on the distinct type/tag values list_bundles rolls up per bundle;
      # the remainder is reported as an `other_types`/`other_tags` count so a
      # huge bundle cannot flood a context window with a long-tail histogram.
      ROLLUP_LIMIT = 25

      SEARCH_LIMIT = 20
      CATALOG_LIMIT = 200

      # Date-grouped entries returned per log.md. A log is the one file in a
      # bundle that only ever grows and never gets curated, so its size tracks
      # the project's age rather than the question asked — this repo's own
      # answered "what changed recently" with 119,863 bytes across fourteen
      # dates, and `total` counting *files* made that read as bounded. Three is
      # what "recently" means when the entries are date-grouped; `limit` asks
      # for more.
      LOG_LIMIT = 3

      # A §7 log is "a flat list of date-grouped entries, newest first", so a
      # `## ` heading at column 0 is the entry boundary. Split kept here rather
      # than pushed into the kernel because bounding for a context window is
      # this surface's problem alone: the graph page's Log panel wants the
      # whole file and scrolls it. If a second consumer ever needs the entries
      # — an `okf log` verb is the obvious one — the split moves to the kernel
      # and both read it from there.
      LOG_ENTRY = /^(?=## )/.freeze

      # Characters returned per `limit` for a log the split above cannot divide
      # (see #unstructured_log). Sized off the structured path rather than
      # guessed: this repo's own three-entry answer is 13,491 bytes, so one
      # indivisible "entry" is budgeted at roughly what one date group costs.
      UNSTRUCTURED_LOG = 4_500

      # The catalog row, the projection vocabulary `fields` selects from.
      CATALOG_FIELDS = %w[id title type description tags timestamp status backlog_ref dir top_dir links_out links_in].freeze

      GRAPH_VIEWS = %w[minimal hubs traffic].freeze
      LINT_GROUPS = %w[check folder].freeze

      # Declared explicitly, because the SDK's default announces every
      # capability it knows how to route — and this server used to inherit a
      # `resources` declaration while `resources/list` answered `[]`, plus a
      # `logging` one nothing ever emits through. That is the same class of
      # dishonesty the `readOnlyHint` annotations are careful to avoid, so the
      # hash below names exactly what is served and nothing else.
      #
      # No `listChanged` on any of them and no `subscribe`: nothing here sends
      # a notification, and claiming otherwise would invite a host to wait for
      # one. The tool and prompt lists are genuinely fixed for a process's
      # life; the *resource* list is not — it tracks the registry (see
      # Definition), so a host that re-lists sees the current set, and one that
      # caches the boot listing is stale until it asks again. Declaring
      # `listChanged` is what would fix that, and it stays undeclared until
      # something actually notifies.
      CAPABILITIES = { tools: {}, prompts: {}, resources: {}, completions: {} }.freeze

      INSTRUCTIONS = <<~TEXT
        Tools take a `bundle` argument: a slug from list_bundles — the same
        name `@slug` resolves at the okf CLI. The retrieval discipline: orient
        with dirs (the shape), descend with index (a directory's map), answer
        pointed questions with search (omit `bundle` to search every bundle),
        and read only the winning concepts with read_concept — never slurp a
        bundle whole. Check log for recent history. validate and lint report a
        bundle's health: you may flag what they find, but fixing it belongs to
        the okf skill and CLI — the tools here never write. Bodies are read
        live from disk, so results always reflect the current files.
      TEXT

      # Holds what every tool closes over: the bundle allowlist, the engine
      # that answers search/catalog (memory, or okf-sqlite3 when installed),
      # and the always-present memory folder cache behind read_concept, dirs,
      # index, log and graph.
      Context = Struct.new(:registry, :engine, :memory) do
        def root!(bundle)
          registry.root!(bundle)
        end

        def folder(bundle)
          memory.folder(root!(bundle))
        end
      end

      # The SDK takes `resources:` as a fixed array at construction, and that is
      # the wrong lifetime for this one: the registry re-reads itself whenever
      # the file moves underneath it (Registry#entries), so a boot snapshot
      # drifts out of step with the served set. A bundle registered afterwards
      # was never advertised, and a removed one stayed advertised until a read
      # of the very URI we published came back "unknown bundle" — and with no
      # `listChanged` declared, a host had no way to be told either.
      #
      # `resources/list` is the only place the cost is owed, so it is the only
      # place that recomputes: one `stat` per bundle, no bundle read, the same
      # price Resources.list always paid. The public `resources=` setter is what
      # does the mutation, so the SDK's URI index is rebuilt with it.
      class Definition < ::MCP::Server
        def initialize(registry:, context:, **options)
          @registry = registry
          @context = context
          super(**options)
        end

        # One request is one unit of work. Both public entry points are wrapped
        # and `handle_request` deliberately is not: the JSON-RPC layer treats
        # the handler block as a *lookup* — `method = method_finder.call(name)`
        # then `method.call(params)` — so `handle_request` has already returned
        # by the time the tool body runs, and a wrapper there encloses nothing.
        #
        # Two things are owed per request rather than per tool:
        #
        # The **fingerprint memo**, because a tool asks the engine for the
        # catalog and then reads the unparseable count off the same folder, and
        # each ask re-walked the tree — a glob plus a stat per markdown file,
        # inside the residency lock. Freshness is a question *between* requests;
        # asking it three times within one buys nothing and costs three walks.
        #
        # The **residency prune**, because the served set is that cache's only
        # honest bound and the registry re-read made the set movable. Anything
        # the registry no longer names is dropped here, so a repointed entry
        # stops retaining the bundle its slug used to mean.
        def handle(request, session: nil)
          in_request { super }
        end

        def handle_json(request, session: nil)
          in_request { super }
        end

        private

        def list_resources(request)
          self.resources = Resources.list(@registry)
          super
        end

        def in_request
          @context.memory.during_request do
            @context.memory.retain(@registry.entries.map(&:root))
            yield
          end
        end
      end

      class << self
        # `configuration:` is the seam the output-schema suite needs: it turns
        # on the SDK's result validation so a schema that has drifted from its
        # payload fails a test. Left nil in production deliberately — a schema
        # bug should not turn a working tool into a runtime error.
        def build(registry, engine: Backend.detect, configuration: nil)
          memory = engine.is_a?(MemoryBackend) ? engine : MemoryBackend.new
          context = Context.new(registry, engine, memory)
          server = Definition.new(
            registry: registry,
            context: context,
            name: "okf",
            title: "OKF knowledge bundles",
            version: VERSION,
            instructions: INSTRUCTIONS,
            capabilities: CAPABILITIES,
            configuration: configuration,
            tools: tools_for(context),
            prompts: prompts,
            resources: [],
            resource_templates: Resources.templates
          )
          # Replaces the SDK's URI matching wholesale, because an OKF id below
          # the root carries slashes and the template matcher binds a variable
          # to `[^/]+`. Resources owns the parsing; the template is signage.
          server.resources_read_handler { |params| Resources.read(context, params[:uri]) }
          server.completion_handler { |params| { completion: { values: Resources.complete(context, params) } } }
          server
        end

        def tools_for(context)
          [
            list_bundles_tool(context),
            dirs_tool(context),
            index_tool(context),
            search_tool(context),
            read_concept_tool(context),
            catalog_tool(context),
            log_tool(context),
            validate_tool(context),
            lint_tool(context),
            graph_tool(context)
          ]
        end

        # The consuming prompts, and only those — this gem's own text, written
        # against the tools above rather than the CLI. The skill's playbooks
        # were served here verbatim once, all eight, on the argument that a
        # prompt is instructions rather than a capability; what that argument
        # missed is *whose* instructions they were. Every playbook speaks in
        # `okf …` invocations and half dead-end a CLI-less host at "install the
        # CLI first", so to the host this surface exists for they taught a
        # vocabulary it cannot use and a mission (authoring) its tools refuse.
        # This server makes a client an expert consumer of bundles; producing,
        # migrating, maintaining, refining and curating stay with the skill,
        # which is installed where a filesystem and the CLI actually are.
        #
        # Owning the text is the cost: these two restate the skill's retrieval
        # doctrine in tool vocabulary, so a doctrine change there must be
        # carried here by hand. The pair keeps SKILL.md's Commands-table order
        # (search before consume).
        PROMPTS = {
          "okf-search" => [ "search", "find the concepts that answer a pointed question, without paying for the whole bundle" ],
          "okf-consume" => [ "consume", "answer questions from an OKF bundle without reading it whole" ]
        }.freeze

        def prompts
          PROMPTS.map do |name, (file, description)|
            # `**` absorbs the server_context: the SDK's template passes.
            ::MCP::Prompt.define(name: name, description: description) do |_args, **|
              ::MCP::Prompt::Result.new(
                description: description,
                messages: [ ::MCP::Prompt::Message.new(role: "user", content: ::MCP::Content::Text.new(Server.prompt_text(file))) ]
              )
            end
          end
        end

        # This gem's own prompts/ tree, read at get-time so booting never pays
        # for it. No missing-file rescue like the tools carry: the old path
        # read from the *installed kernel's* skill tree, where version skew
        # could orphan a name, but a file shipped in this gem beside this file
        # can only be absent when the package itself is broken.
        def prompt_text(name)
          ::File.read(::File.join(__dir__, "prompts", "#{name}.md"), encoding: "UTF-8")
        end

        private

        def list_bundles_tool(context)
          define_tool(
            name: "list_bundles",
            description: "What exists: every OKF bundle this server knows — slug, title, root, concept " \
                         "count, type/tag rollups (top #{ROLLUP_LIMIT} each, with other_types/other_tags remainder " \
                         "counts), which is the default, and whether its directory is missing — plus the " \
                         "registered group slugs, which backend answers search, and which registry file " \
                         "the slugs came from. Bundle slugs are the `bundle` argument every other tool takes.",
            input_schema: { properties: {}, required: [] }
          ) do
            bundles = context.registry.entries.map { |entry| bundle_row(context, entry) }
            payload = {
              backend: context.engine.capabilities,
              registry_source: context.registry.source,
              default: context.registry.default_slug,
              total: bundles.length,
              bundles: bundles
            }
            groups = context.registry.groups
            payload[:groups] = groups unless groups.empty?
            respond_json(payload)
          end
        end

        def dirs_tool(context)
          define_tool(
            name: "dirs",
            description: "The first move: a bundle's shape as one row per directory — `count` is the " \
                         "concepts living directly there, `subtree` the weight at or below it, `subdirs` " \
                         "its children. Orient here before anything else; it scales with the tree, not " \
                         "the concept count. `dir` narrows to one branch, `depth` bounds how far below " \
                         "the starting point rows go.",
            input_schema: {
              properties: {
                bundle: { type: "string", description: "A bundle slug from list_bundles." },
                dir: { type: "string", description: "Only this directory and the ones below it (\".\" is the root)." },
                depth: { type: "integer", minimum: 0, description: "Rows at most this many levels below the starting point." }
              },
              required: [ "bundle" ]
            }
          ) do |bundle:, dir: nil, depth: nil|
            folder = context.folder(bundle)
            entries = folder.directory_index
            subtree = subtree_counts(entries)
            rows = scoped_rows(entries, dir, depth, bundle).map do |entry|
              { dir: entry[:dir], count: entry[:count], subtree: subtree[entry[:dir]], subdirs: entry[:subdirs] }
            end
            respond_json(with_unparseable(folder, bundle: slug_of(context, bundle), total: rows.length, dirs: rows))
          end
        end

        def index_tool(context)
          define_tool(
            name: "index",
            description: "The bundle's index map, one directory at a time: the authored index.md body " \
                         "(or `synthesized: true` where none exists), type/tag rollups, subdirectories, " \
                         "and the concept listing an index there would enumerate — the view that surfaces " \
                         "enumeration drift. Bounded by default: `depth` defaults to 1 (the starting " \
                         "directory and its children). Cost warning: `bodies` over a whole deep bundle " \
                         "dominates the payload — descend with `dir` instead of raising `depth`.",
            input_schema: {
              properties: {
                bundle: { type: "string", description: "A bundle slug from list_bundles." },
                dir: { type: "string", description: "Start at this directory (default \".\", the root)." },
                depth: { type: "integer", minimum: 0, description: "Directories at most this many levels below the start (default 1)." },
                bodies: { type: "boolean", description: "Include each directory's index body (default true)." },
                listing: { type: "boolean", description: "Include each directory's concept listing (default true)." }
              },
              required: [ "bundle" ]
            }
          ) do |bundle:, dir: nil, depth: 1, bodies: true, listing: true|
            folder = context.folder(bundle)
            entries = folder.directory_index
            rows = scoped_rows(entries, dir, depth, bundle).map do |entry|
              row = entry.dup
              row.delete(:body) unless bodies
              row.delete(:listing) unless listing
              row
            end
            respond_json(with_unparseable(folder, bundle: slug_of(context, bundle), total: rows.length, dirs: rows))
          end
        end

        def search_tool(context)
          define_tool(
            name: "search",
            description: "Find concepts: every term must match (AND) across title, id, tags, type, " \
                         "description, and body. Returns scored rows — each carrying its `bundle` and the " \
                         "fields it `matched`, so results stay citable — with ids for read_concept. Omit " \
                         "`bundle` (or pass \"*\") to search every bundle at once through one shared " \
                         "index, so scores stay comparable; a group slug fans out to its members. Terms " \
                         "match raw text by default (exact, no tokenizer); `engine: \"index\"` ranks by " \
                         "BM25+ and matches whole tokens or prefixes — the same ranking as the okf server " \
                         "page. `fuzzy` tolerates typos and implies the index, carrying its tokenizer " \
                         "with it; `regexp` reads terms as Ruby patterns and stays on the raw-text scan.",
            input_schema: {
              properties: {
                terms: {
                  type: "array", items: { type: "string" }, minItems: 1,
                  description: "One or more search terms; a concept must match all of them."
                },
                # Singular, like every other tool's, though this is the one
                # that accepts a set: the type says it takes an array, and a
                # name that differed only in its plural bought a signal
                # nobody saw until the SDK had already refused the call.
                bundle: {
                  type: %w[string array], items: { type: "string" }, minItems: 1,
                  description: "A bundle slug, an array of slugs, a group slug, or \"*\" for every bundle (the default)."
                },
                engine: { type: "string", enum: %w[scan index], description: "Match with this engine (default scan: raw text, exact)." },
                fuzzy: { type: "boolean", description: "Tolerate typos (edit distance; implies the index engine)." },
                regexp: { type: "boolean", description: "Read each term as a case-insensitive Ruby regexp (scan engine)." },
                in: { type: "array", items: { type: "string" }, description: "Search only these fields (#{Bundle::Search::FIELDS.join(", ")})." },
                type: { type: "string", description: "Only concepts of this type." },
                dir: { type: "string", description: "Only concepts in this directory or below it (\".\" for the bundle root)." },
                tag: { type: "string", description: "Only concepts carrying this tag." },
                limit: { type: "integer", minimum: 1, description: "Maximum rows to return (default #{SEARCH_LIMIT}); `total` is the count before the cut." }
              },
              required: [ "terms" ]
            }
          ) do |terms:, **options|
            search_call(context, terms, options)
          end
        end

        def read_concept_tool(context)
          define_tool(
            name: "read_concept",
            description: "Read one concept's full markdown (frontmatter and body), live from disk — the " \
                         "canonical copy. Ids are exact: take them from search, index, or catalog results.",
            input_schema: {
              properties: {
                bundle: { type: "string", description: "A bundle slug from list_bundles." },
                id: { type: "string", description: "The concept id, e.g. runbooks/billing-restart." }
              },
              required: %w[bundle id]
            }
          ) do |bundle:, id:|
            handle = context.folder(bundle).concept(id)
            if handle
              # The file's own bytes, not concept.to_markdown: a re-serialized
              # frontmatter is canonical-ish, and "-ish" is drift. The id was
              # resolved through the bundle's own map and absolute_path guards
              # the root, so no request path ever reaches the filesystem.
              text = ::File.read(handle.absolute_path, encoding: "UTF-8")
              ::MCP::Tool::Response.new([ { type: "text", text: text } ])
            else
              respond_error("no concept #{id.inspect} in bundle #{bundle.inspect} — ids are exact; find them with search or index")
            end
          end
        end

        def catalog_tool(context)
          define_tool(
            name: "catalog",
            description: "Per-concept metadata for a whole bundle — #{CATALOG_FIELDS.join(", ")} — " \
                         "filterable by type, dir (prefix: a dir names itself and everything beneath " \
                         "it), tag, and status. Use it for inventories and rollups; use search when you " \
                         "have terms. Returns `limit` rows (default #{CATALOG_LIMIT}) from `offset`; `total` is the " \
                         "full count before slicing. `fields` projects each row down to the named keys.",
            input_schema: {
              properties: {
                bundle: { type: "string", description: "A bundle slug from list_bundles." },
                type: { type: "string", description: "Only concepts of this type." },
                dir: { type: "string", description: "Only concepts in this directory or below it (\".\" for the bundle root)." },
                tag: { type: "string", description: "Only concepts carrying this tag." },
                status: { type: "string", description: "Only concepts with this frontmatter status." },
                fields: { type: "array", items: { type: "string" }, description: "Emit only these row keys (#{CATALOG_FIELDS.join(", ")})." },
                limit: { type: "integer", minimum: 1, description: "Maximum concepts to return (default #{CATALOG_LIMIT})." },
                offset: { type: "integer", minimum: 0, description: "Skip this many concepts first (default 0)." }
              },
              required: [ "bundle" ]
            }
          ) do |bundle:, type: nil, dir: nil, tag: nil, status: nil, fields: nil, limit: CATALOG_LIMIT, offset: 0|
            root = context.root!(bundle)
            projection = check_fields(fields)
            # One folder, held: the `dir` check and the unparseable count both
            # want it, and asking the residency layer twice walks the tree twice.
            folder = context.memory.folder(root)
            check_dir!(context, [ [ slug_of(context, bundle), root ] ], dir)
            rows = context.engine.catalog(root, { type: type, dir: dir, tag: tag, status: status })
            sliced = rows[offset, limit] || []
            sliced = sliced.map { |row| row.select { |key, _| projection.include?(key.to_s) } } if projection
            respond_json(with_unparseable(folder,
              bundle: slug_of(context, bundle), total: rows.length, concepts: sliced))
          end
        end

        def log_tool(context)
          define_tool(
            name: "log",
            description: "Read a bundle's append-only history — every log.md, root scope first, content " \
                         "live from disk. Returns the newest #{LOG_LIMIT} date-grouped entries per file; " \
                         "each file's `total` is how many it holds and `returned` how many came back, so " \
                         "`limit` can ask for more. A log whose groups are not `## ` headings cannot be " \
                         "split, so it counts as one entry and is cut by size with `truncated: true` " \
                         "saying so. Check it to see what changed recently before " \
                         "trusting or adding knowledge.",
            input_schema: {
              properties: {
                bundle: { type: "string", description: "A bundle slug from list_bundles." },
                limit: { type: "integer", minimum: 1,
                         description: "Entries to return per log file (default #{LOG_LIMIT}); each file's `total` is the count before the cut." }
              },
              required: [ "bundle" ]
            }
          ) do |bundle:, limit: LOG_LIMIT|
            logs = context.folder(bundle).log_entries.map { |entry| bounded_log(entry, limit) }
            respond_json(bundle: slug_of(context, bundle), total: logs.sum { |row| row[:total] },
              files: logs.length, logs: logs)
          end
        end

        def validate_tool(context)
          define_tool(
            name: "validate",
            description: "The spec §9 conformance verdict: `conformant` (hard errors empty), every error " \
                         "and soft warning with its file and why — unopenable files included. Read-only: " \
                         "you may flag what it finds; fixing it belongs to the okf skill and CLI. " \
                         "Curation quality is lint's question, kept deliberately separate.",
            input_schema: {
              properties: {
                bundle: { type: "string", description: "A bundle slug from list_bundles." }
              },
              required: [ "bundle" ]
            }
          ) do |bundle:|
            result = context.folder(bundle).validate
            respond_json(
              bundle: slug_of(context, bundle),
              conformant: result.valid?,
              errors: result.errors,
              warnings: result.warnings,
              counts: result.counts
            )
          end
        end

        def lint_tool(context)
          define_tool(
            name: "lint",
            description: "The curation-quality report — reachability, backlog, completeness, freshness, " \
                         "provenance, hygiene — as warnings and infos that never reject (conformance is " \
                         "validate's question). `only`/`except` select by check id " \
                         "(#{Bundle::Linter::CHECKS.join(", ")}). `stale_after` turns on freshness: a " \
                         "duration like 90d or 12w, or an ISO date. `group: \"folder\"` answers \"which " \
                         "files float in the graph?\" instead — the unlinked concepts grouped by folder. " \
                         "Noticing rot is yours; fixing it belongs to the okf skill and CLI.",
            input_schema: {
              properties: {
                bundle: { type: "string", description: "A bundle slug from list_bundles." },
                min_body: { type: "integer",
                            description: "Bodies shorter than this many characters are flagged as stubs (default #{Bundle::Linter::DEFAULT_MIN_BODY})." },
                stale_after: { type: "string", description: "Flag concepts older than this: 90d, 12w, or an ISO date like 2026-01-01." },
                only: { type: "array", items: { type: "string" }, description: "Run only these checks (by check id)." },
                except: { type: "array", items: { type: "string" }, description: "Run every check but these (by check id)." },
                group: { type: "string", enum: LINT_GROUPS, description: "\"check\" (default) or \"folder\" — the unlinked files grouped by folder." }
              },
              required: [ "bundle" ]
            }
          ) do |bundle:, min_body: nil, stale_after: nil, only: nil, except: nil, group: "check"|
            lint_call(context, bundle, min_body, stale_after, only, except, group)
          end
        end

        def graph_tool(context)
          define_tool(
            name: "graph",
            description: "The knowledge graph, in three bounded views — never with concept bodies. " \
                         "\"minimal\" (default): id/title nodes, edges, and the type/tag indexes — the " \
                         "shape for planning a traversal. \"hubs\": concepts ranked by inbound links with " \
                         "the top-level dirs those links come from — the origin test for \"is this hub " \
                         "well-homed?\". \"traffic\": directories with the weighted arcs between them and " \
                         "each one's cohesion — where the bundle's mass and coupling live.",
            input_schema: {
              properties: {
                bundle: { type: "string", description: "A bundle slug from list_bundles." },
                view: { type: "string", enum: GRAPH_VIEWS, description: "One of #{GRAPH_VIEWS.join(", ")} (default minimal)." }
              },
              required: [ "bundle" ]
            }
          ) do |bundle:, view: "minimal"|
            graph_call(context, bundle, view)
          end
        end

        # ── the handlers the longer tools call ──

        def search_call(context, terms, options)
          fields = check_fields(options[:in], searchable: true)
          fuzzy = options[:fuzzy] ? true : false
          regexp = options[:regexp] ? true : false
          engine = options[:engine]
          check_engine_asks(engine, fuzzy: fuzzy, regexp: regexp)

          pairs, skipped = context.registry.resolve_search(options[:bundle])
          # A `dir` refusal is a fact about the searched *set*, not about each
          # bundle in turn: `services` living in one of three bundles is the
          # ordinary cross-bundle ask and must answer, while a `dir` no bundle
          # has is a mistake the caller can fix. Refusing per bundle would break
          # the first; answering `total: 0` for the second is the silent empty
          # this tool set refuses.
          check_dir!(context, pairs, options[:dir])
          rows = engine_rows(context, pairs, terms, fields, regexp, fuzzy, engine)
          rows = filter_rows(rows, options)
          limit = options[:limit] || SEARCH_LIMIT

          payload = {
            query: Array(terms),
            # Which engine answered, resolved rather than echoed: `fuzzy`
            # switches engines on its own, so the asked-for value is not the
            # answer. A caller cannot infer it — the scan's integer count and
            # the index's BM25 float both round to a number — and the
            # difference decides whether a miss means "absent" or "the
            # tokenizer shattered the identifier".
            engine: fuzzy || engine.to_s == "index" ? "index" : "scan",
            # §9 best-effort, surfaced per bundle: a corpus built from a folder
            # that skipped unusable files must say so, or a term living only in
            # an unreadable file reads back as "this bundle does not mention it".
            bundles: pairs.map { |slug, root| bundle_head_row(context, slug, root) },
            total: rows.length,
            results: rows.first(limit).map { |row| search_row(row, pairs) }
          }
          payload[:skipped] = skipped unless skipped.empty?
          respond_json(payload)
        rescue RegexpError => e
          respond_error("invalid pattern: #{e.message}")
        end

        # "No concept matched" and "the directory you filtered by is not there"
        # are different answers, and only one of them is the caller's to fix.
        # `dirs` and `index` have always told them apart (see #scoped_rows);
        # catalog and search answered `total: 0` to both, which is worst for the
        # spelling the CLI and the skill teach — an agent asks for `root`, is
        # told zero, and reports that the bundle root holds nothing.
        #
        # Blank is not a filter (see Filters), so it is not a mistake either.
        def check_dir!(context, pairs, dir)
          return if OKF.blank?(dir)

          known = pairs.flat_map { |_, root| Filters.dirs_of(context.memory.folder(root).bundle.paths) }
          return if Filters.known_dir?(known, dir)

          named = pairs.length == 1 ? " in bundle #{pairs.first.first.inspect}" : ""
          raise Error, "no directory #{dir.to_s.inspect}#{named} — orient with dirs"
        end

        # The two incompatible pairs, refused with the fix named rather than
        # left to the kernel's flag-free vocabulary.
        def check_engine_asks(engine, fuzzy:, regexp:)
          if regexp && fuzzy
            raise Error, "regexp and fuzzy are mutually exclusive (a pattern is matched literally, not by edit distance)"
          end
          if engine.to_s == "index" && regexp
            raise Error, "engine \"index\" cannot answer regexp — patterns match raw text: drop `engine` (the scan answers regexp) or drop `regexp`"
          end
          return unless engine.to_s == "scan" && fuzzy

          raise Error, "engine \"scan\" cannot answer fuzzy — edit distance needs the index: drop `engine` (fuzzy implies the index) or drop `fuzzy`"
        end

        # Memory answers through the kernel facade (one corpus, comparable
        # scores). A foreign engine (okf-sqlite3) answers per bundle through
        # its duck type and the rows merge by score — and it is refused the
        # kernel-facade knobs rather than allowed to drop them in silence.
        def engine_rows(context, pairs, terms, fields, regexp, fuzzy, engine)
          if context.engine.is_a?(MemoryBackend)
            context.engine.search_pairs(pairs, terms, fields: fields, regexp: regexp, fuzzy: fuzzy, engine: engine)
          else
            if fields || regexp || fuzzy || !OKF.blank?(engine)
              raise Error, "the #{context.engine.capabilities[:name]} backend does not support engine, fuzzy, regexp or in"
            end

            pairs.flat_map do |slug, root|
              context.engine.search(root, terms, {}).map { |row| row.merge(slug: slug) }
            end.sort_by { |row| [ -(row[:score] || 0), row[:slug].to_s, row[:id].to_s ] }
          end
        end

        # `OKF.blank?`, not `.nil?`: an empty string is truthy in Ruby, so an
        # MCP client that fills every declared optional property with an empty
        # default (routine model behaviour) was handing `search` a filter that
        # matched nothing — while `catalog`, one tool over, read the same ""
        # as "no filter" and answered for the whole bundle.
        def filter_rows(rows, options)
          rows.select do |row|
            (OKF.blank?(options[:type]) || Filters.fold(row[:type]) == Filters.fold(options[:type])) &&
              (OKF.blank?(options[:dir]) || Filters.under_dir?(row[:dir], options[:dir])) &&
              (OKF.blank?(options[:tag]) || Array(row[:tags]).any? { |tag| Filters.fold(tag) == Filters.fold(options[:tag]) })
          end
        end

        # The protocol row: `bundle` leads (identity first), the head already
        # mapped slug → dir once, and per-row paths stay off the wire.
        def search_row(row, pairs)
          slug = row[:slug] || (pairs.length == 1 ? pairs.first.first : nil)
          {
            bundle: slug,
            id: row[:id],
            title: row[:title],
            type: row[:type],
            tags: row[:tags],
            matched: row[:matched],
            score: row[:score],
            snippet: row[:snippet]
          }
        end

        def lint_call(context, bundle, min_body, stale_after, only, except, group)
          folder = context.folder(bundle)
          if group == "folder"
            # The folder lens *is* the unlinked check, so the check-selection
            # and threshold options have nothing to act on. Returning here
            # while silently dropping them let a caller read the full listing
            # as though its filter had been applied — and skipped the check-id
            # vocabulary check, so a typo'd id passed here and errored there.
            offered = { only: only, except: except, min_body: min_body, stale_after: stale_after }
            given = offered.reject { |_, value| OKF.blank?(value) }.keys
            unless given.empty?
              raise Error, "group \"folder\" is the unlinked lens and takes no #{given.join("/")} — " \
                           "drop #{given.length == 1 ? "it" : "them"}, or drop `group` to run the checks"
            end

            return respond_json(with_unparseable(folder, loose_payload(context, bundle, folder)))
          end

          checks = { only: only, except: except }.each_with_object({}) do |(key, list), out|
            next if OKF.blank?(list)

            out[key] = Array(list).map(&:to_sym)
          end
          unknown = checks.values.flatten - Bundle::Linter::CHECKS
          raise Error, "unknown check(s): #{unknown.uniq.join(", ")} (checks: #{Bundle::Linter::CHECKS.join(", ")})" unless unknown.empty?

          opts = checks
          opts[:min_body] = min_body unless min_body.nil?
          opts[:stale_before] = parse_stale(stale_after) unless OKF.blank?(stale_after)
          report = folder.lint(**opts)
          respond_json(
            bundle: slug_of(context, bundle),
            healthy: report.healthy?,
            stats: report.stats,
            total: report.findings.length,
            findings: report.findings
          )
        end

        # The `loose` lens: unlinked concepts (graph degree 0) grouped by
        # folder — lint's `unlinked` check answered the way the question is
        # usually asked.
        def loose_payload(context, bundle, folder)
          graph = folder.graph(minimal: true)
          titles = graph.nodes.to_h { |node| [ node[:id], node[:title] ] }
          files = graph.unlinked_ids
                       .map { |id| { id: id, title: titles[id], dir: OKF.dir_of(id) } }
                       .sort_by { |file| file[:id] }
          { bundle: slug_of(context, bundle), group: "folder", total: files.length, files: files }
        end

        # One searched bundle in the payload head: slug → dir once, plus the
        # count of files the reader could not parse when there are any.
        def bundle_head_row(context, slug, root)
          row = { slug: slug, dir: root }
          with_unparseable(context.memory.folder(root), row)
        end

        def graph_call(context, bundle, view)
          folder = context.folder(bundle)
          payload = with_unparseable(folder, bundle: slug_of(context, bundle), view: view)
          case view
          when "minimal"
            graph = folder.graph(minimal: true)
            payload.merge!(total_nodes: graph.nodes.length, total_edges: graph.edges.length,
              nodes: graph.nodes, edges: graph.edges, types: graph.type_index, tags: graph.tag_index)
          when "hubs"
            hubs = folder.hubs
            payload.merge!(total: hubs.length, hubs: hubs)
          when "traffic"
            payload.merge!(traffic_payload(folder.skeleton))
          end
          respond_json(payload)
        end

        # Directories with their internal/in/out traffic and cohesion, plus the
        # arcs above the fitted cut — the CLI's `graph --traffic`, as data. The
        # cohesion is measured over every arc; the cut only decides which arcs
        # are worth returning.
        def traffic_payload(skeleton)
          cut = skeleton.suggested_cut
          out = Hash.new(0)
          into = Hash.new(0)
          skeleton.arcs.each do |arc|
            out[arc[:source]] += arc[:weight]
            into[arc[:target]] += arc[:weight]
          end
          dirs = skeleton.dirs.map do |row|
            total = row[:internal] + out[row[:dir]] + into[row[:dir]]
            row.merge(out: out[row[:dir]], in: into[row[:dir]],
              cohesion: total.zero? ? nil : (100.0 * row[:internal] / total).round)
          end
          { cut: cut, total_arcs: skeleton.arcs.length, dirs: dirs, arcs: Bundle::Skeleton.arcs_above(skeleton.arcs, cut) }
        end

        # ── shared plumbing ──

        # Every tool is a read-only lens over the registry's bundles; the
        # rescue turns domain failures into tool errors an agent can act on
        # instead of opaque JSON-RPC internal errors — carrying the kernel's
        # own sentences, never re-judged here.
        def define_tool(name:, description:, input_schema:, &body)
          ::MCP::Tool.define(
            name: name,
            description: description,
            # Looked up rather than passed, so a tool cannot ship without its
            # shape being a deliberate omission — read_concept is the one
            # entry OutputSchemas does not carry, because markdown has no
            # object shape to declare.
            output_schema: OutputSchemas[name],
            # `additionalProperties: false` is the first line of the same
            # defence as the rescue below. Without it an unrecognized argument
            # reached `body.call(**arguments)` and raised ArgumentError, which
            # escaped as a bare JSON-RPC -32603 the model could not read or
            # act on — and `search`, which takes **options, silently *absorbed*
            # a near-miss like the singular `bundle:` and widened its answer to
            # every bundle. The SDK validates the full 2020-12 vocabulary, so
            # the unknown key is now named back to the caller.
            input_schema: input_schema.merge(additionalProperties: false),
            annotations: { read_only_hint: true, destructive_hint: false, open_world_hint: false }
          ) do |**arguments|
            arguments.delete(:server_context)
            begin
              body.call(**arguments)
            rescue Error, OKF::Error, SystemCallError => e
              Server.send(:respond_error, e.message)
            rescue ArgumentError => e
              # Belt to the schema's braces: a host that disables argument
              # validation still gets an actionable tool error, never -32603.
              Server.send(:respond_error, "#{e.message} (tool #{name})")
            end
          end
        end

        # Both channels, always: the JSON text a client on an older protocol
        # version reads, and the same object as structuredContent for one that
        # can take it. Never one or the other — a host should not have to
        # negotiate which of the two this server happens to use.
        def respond_json(payload)
          ::MCP::Tool::Response.new(
            [ { type: "text", text: JSON.generate(payload) } ],
            structured_content: payload
          )
        end

        def respond_error(message)
          ::MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
        end

        def bundle_row(context, entry)
          row = { slug: entry.slug, title: entry.title, root: entry.root }
          unless File.directory?(entry.root)
            return row.merge(missing: true)
          end

          rows = context.engine.catalog(entry.root, {})
          types, other_types = capped_rollup(rows.map { |item| OKF.blank?(item[:type]) ? "Untyped" : item[:type].to_s })
          tags, other_tags = capped_rollup(rows.flat_map { |item| Array(item[:tags]).map(&:to_s) })
          row.merge!(concepts: rows.length, types: types, tags: tags)
          row[:other_types] = other_types if other_types.positive?
          row[:other_tags] = other_tags if other_tags.positive?
          unparseable = context.memory.folder(entry.root).bundle.unparseable.length
          row[:unparseable] = unparseable if unparseable.positive?
          row
        end

        # The served slug behind whatever spelling the ask used, for payload
        # identity keys.
        def slug_of(context, bundle)
          slug = OKF::Registry.normalize(bundle)
          context.registry.slugs.include?(slug) ? slug : bundle.to_s
        end

        # One log file, cut to its newest +limit+ entries. The file's own
        # heading — everything above the first `## ` — always survives, because
        # it is what names the scope ("# Runbooks Log") and costs a line.
        #
        # A log with no `## ` headings at all is not §7-shaped, and there is
        # nothing to count or cut: it comes back whole with total 0, which
        # reads as "unstructured" rather than as an empty file. Truncating it
        # on some other boundary would be inventing a format.
        def bounded_log(entry, limit)
          content = entry[:content].to_s
          return { path: entry[:path], dir: entry[:dir], total: 0, returned: 0, content: "" } if OKF.blank?(content)

          parts = content.split(LOG_ENTRY)
          preamble = parts.first.to_s.start_with?("## ") ? "" : parts.shift.to_s
          return unstructured_log(entry, preamble, limit) if parts.empty?

          { path: entry[:path], dir: entry[:dir], total: parts.length,
            returned: [ parts.length, limit ].min, content: preamble + parts.first(limit).join }
        end

        # A log the split cannot divide — §7 fixes no heading level, so `###`
        # date groups are conformant and `LOG_ENTRY` cannot see them. It used to
        # come back *whole* under `total: 0, returned: 0`: the one unbounded read
        # on this surface, surviving the fix meant to close it and reporting
        # itself as empty, which is the same false comfort as a `total` that
        # counted files. `limit` could not reach it either.
        #
        # It is one entry, because that is what content with no boundary is, and
        # it is cut by size because the format offers nothing else to cut on.
        # That cut is announced rather than quietly applied — inventing a
        # boundary would be inventing a format, but declaring a bound is only
        # honest — and `limit` scales the budget, so a caller can still ask for
        # the rest.
        def unstructured_log(entry, content, limit)
          budget = UNSTRUCTURED_LOG * [ limit, 1 ].max
          row = { path: entry[:path], dir: entry[:dir], total: 1, returned: 1,
                  content: content.length > budget ? content[0, budget] : content }
          row[:truncated] = true if content.length > budget
          row
        end

        # §9 best-effort, surfaced: a payload built from a folder that skipped
        # unusable files says so, and validate names each file and why.
        def with_unparseable(folder, payload)
          count = folder.bundle.unparseable.length
          payload[:unparseable] = count if count.positive?
          payload
        end

        # The directory rows at most +depth+ levels below +dir+ (nil, "", "."
        # or "/": the bundle root, which is the ancestor of everything).
        # Comparison folds case, because every other dir filter in this file
        # does — `dirs(dir: "Services")` used to answer "no such directory" for
        # a name `catalog` resolved without complaint.
        def scoped_rows(entries, dir, depth, bundle)
          base = Filters.normalize_dir(dir)
          unless base == "."
            known = entries.any? { |entry| Filters.fold(entry[:dir]) == base }
            raise Error, "no directory #{dir.inspect} in bundle #{bundle.inspect}" unless known
          end
          base_depth = Filters.dir_depth(base)
          entries.select do |entry|
            next false unless Filters.within?(entry[:dir], base)

            depth.nil? || (Filters.dir_depth(Filters.fold(entry[:dir])) - base_depth) <= depth
          end
        end

        # Per dir, the concepts at or below it — defined as exactly what
        # narrowing to that row selects here (see #scoped_rows), so the number
        # and the `dir` argument can never disagree. The root's subtree is the
        # whole bundle for the same reason: `dir: "."` scopes the whole tree.
        def subtree_counts(entries)
          entries.to_h do |entry|
            [ entry[:dir], entries.reduce(0) do |sum, other|
              same = other[:dir] == entry[:dir] || other[:dir].start_with?("#{entry[:dir]}/")
              same || entry[:dir] == "." ? sum + other[:count] : sum
            end ]
          end
        end

        # A fields ask validated against the vocabulary it selects from; nil
        # passes through (no projection).
        def check_fields(fields, searchable: false)
          return nil if OKF.blank?(fields)

          asked = Array(fields).map { |field| field.to_s.downcase }
          allowed = searchable ? Bundle::Search::FIELDS : CATALOG_FIELDS
          unknown = asked - allowed
          raise Error, "unknown field(s): #{unknown.join(", ")} (#{searchable ? "searchable" : "row keys"}: #{allowed.join(", ")})" unless unknown.empty?

          asked
        end

        # A stale_after ask (90d, 12w, or an ISO date) into the absolute Time
        # the pure Linter compares against — the CLI's resolution, kept here in
        # the shell so the linter never reads the clock.
        def parse_stale(value)
          if (match = value.to_s.match(/\A(\d+)([dw])\z/))
            days = match[1].to_i * (match[2] == "w" ? 7 : 1)
            Time.now - (days * 86_400)
          else
            Date.iso8601(value.to_s).to_time
          end
        rescue ArgumentError
          raise Error, "invalid stale_after #{value.inspect} — use 90d, 12w, or an ISO date like 2026-01-01"
        end

        def rollup(values)
          counts = values.tally
          counts.sort_by { |value, count| [ -count, value ] }.to_h
        end

        # The rollup capped at ROLLUP_LIMIT distinct values (already
        # count-sorted), paired with the number of distinct values omitted so
        # the caller can surface an `other_*` remainder.
        def capped_rollup(values)
          counts = rollup(values)
          kept = counts.first(ROLLUP_LIMIT).to_h
          [ kept, counts.length - kept.length ]
        end
      end
    end
  end
end
