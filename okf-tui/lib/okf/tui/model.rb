# frozen_string_literal: true

require "okf"
require "okf/registry"

module OKF::TUI
  # One bundle, and everything the views ask about it.
  #
  # The split the gem enforces between its pure core and its shell is what makes
  # this cheap: Bundle::Reader is the only thing here that touches disk, and
  # every answer below is a pure call on the in-memory Bundle. The TUI is just
  # another shell over the same core the CLI and the server use — it invents no
  # analysis of its own.
  #
  # Analysis is memoized rather than computed at load: with a whole registry open
  # at once, switching bundles should not pay for a validate and a lint of every
  # bundle nobody has looked at yet.
  class Model
    attr_reader :dir, :bundle, :slug

    def initialize(dir, slug: nil)
      @dir = File.expand_path(dir)
      @slug = slug
      @bundle = OKF::Bundle::Reader.read(@dir)
    end

    def name
      slug || File.basename(dir)
    end

    def catalog
      @catalog ||= bundle.catalog
    end

    def graph
      @graph ||= bundle.graph(minimal: true)
    end

    def validation
      @validation ||= bundle.validate
    end

    def lint
      @lint ||= bundle.lint
    end

    # The spec version the bundle declares (§12), or nil where it declares none
    # — which §12 permits, so nil is an answer and the view says "conformant"
    # rather than guessing a number. Asked of okf rather than assumed: this
    # screen told every reader "legal OKF v0.1" for a release, including about a
    # bundle that had migrated.
    def okf_version
      bundle.okf_version
    end

    # The checks lint did not run, because it was handed no clock. §5.5's
    # freshness pair is clock-gated, and the pure library confesses the omission
    # here rather than reporting a verdict it did not earn — so the view says so
    # too. Reporting "lint clean" over a check that never ran is the one way a
    # health screen can be worse than no health screen.
    def skipped_checks
      Array(lint.stats[:skipped_checks])
    end

    # The bundle's trust and status posture — the two distributions okf's own
    # lint prints on its summary line. Hashes, so `stats_block` (which keeps
    # scalars) drops them; they are named here because the standing pane is
    # exactly where they belong, being short by construction and carrying no path.
    def trust_posture
      lint.stats[:trust] || {}
    end

    def status_posture
      lint.stats[:status] || {}
    end

    # §5.3's display half, asked of okf. Whether a *tier* is one this screen
    # should claim is not the same question as what the tier is: a concept that
    # declared no §5 family derives `unverified` and has claimed nothing, which
    # is every concept of every v0.1 bundle. okf owns the rule — its server, its
    # graph page and this all read one predicate — and the reason it is shared is
    # that a gate disagreeing with the counts beside it reads "unverified 3" over
    # two chipped rows.
    def self.shows_trust?(row)
      OKF::Bundle::RowFilter.shows_trust?(row)
    end

    # The catalog rows plus the one thing the catalog does not carry: the file
    # path each concept came from. Everything else the browse list needs — the
    # area, the in/out link degree — the catalog already computed.
    def rows
      @rows ||= begin
        paths = bundle.paths_by_id
        catalog.map { |entry| entry.merge(path: paths[entry[:id]].to_s) }
      end
    end

    # Every directory the bundle has — okf's own answer, not one derived here.
    # Counting the catalog's directories instead gives a smaller set: the catalog
    # knows only directories that hold concepts, so an intermediate that holds
    # nothing but sub-directories, or one whose only file is a log, drops out.
    # That is the disagreement okf 1.13.0 fixed by putting the question on the
    # bundle, and asking it there is how the TUI cannot reintroduce it.
    #
    # Not memoized: Bundle#directories already is, and a second cache over an
    # immutable model is a second thing to invalidate for no gain.
    def dirs
      bundle.directories
    end

    def concept_count
      bundle.concepts.length
    end

    def edge_count
      graph.edges.length
    end

    def orphan_ids
      @orphan_ids ||= graph.unlinked_ids
    end

    # Concepts ranked by inbound link degree, each carrying where those links come
    # from — okf's `graph --hubs`, unchanged.
    #
    # The graph view already ranks by inbound degree, so what this adds is the
    # `by_top_dir` breakdown, which is the whole point: it is the evidence for
    # "is this hub well homed?". A hub whose inbound majority is foreign to its own
    # top-level dir is a move candidate, and one with a single dominant foreign dir
    # has already named its better home. That judgement is okf's, and this is the
    # method that makes it.
    def hubs
      @hubs ||= bundle.hubs
    end

    # The link graph one grain coarser: each directory with its internal, outbound
    # and inbound traffic, and the internal share of that total as a cohesion —
    # okf's `graph --traffic`.
    #
    # `Bundle::Skeleton` is okf's pure model here; the arithmetic below is the
    # aggregation its CLI view does, and only that. Cohesion is internal over
    # total, and nil rather than 0% for a directory with no traffic at all, because
    # a directory with nothing to weigh has not earned a number.
    #
    # Counted over *every* arc, never a narrowed set: okf makes a point of this —
    # the cut it suggests narrows the drawn picture and must never move the
    # evidence. Sorted by cohesion ascending, so the directories with a case to
    # answer come first rather than sitting under the ones nobody needed to read.
    def dir_traffic
      @dir_traffic ||= begin
        skeleton = bundle.skeleton
        out = Hash.new(0)
        into = Hash.new(0)
        skeleton.arcs.each do |arc|
          out[arc[:source]] += arc[:weight]
          into[arc[:target]] += arc[:weight]
        end

        rows = skeleton.dirs.map do |row|
          total = row[:internal] + out[row[:dir]] + into[row[:dir]]
          row.merge(out: out[row[:dir]], in: into[row[:dir]],
            cohesion: total.zero? ? nil : (100.0 * row[:internal] / total).round)
        end

        rows.sort_by { |row| [ row[:cohesion] || 999, row[:dir] ] }
      end
    end

    # The cross-directory link mass, as weighted arcs, narrowed to the cut okf
    # suggests for this bundle.
    #
    # The cut is *fitted*, not fixed — okf measured ten bundles at weight 3 and got
    # anywhere from 2 arcs to 136 — so `suggested_cut` is asked rather than guessed.
    # It narrows only the drawn picture: cohesion above is computed over every arc
    # regardless, which is okf's own rule, and the reason the two can be shown
    # together without the number moving when the list gets shorter.
    def dir_arcs
      @dir_arcs ||= begin
        skeleton = bundle.skeleton
        cut = skeleton.suggested_cut
        [ OKF::Bundle::Skeleton.arcs_above(skeleton.arcs, cut).sort_by { |arc| -arc[:weight] },
          cut, skeleton.arcs.length ]
      end
    end

    def concept_by_id(id)
      bundle.concept_by_id(id)
    end

    def row_by_id(id)
      rows.find { |row| row[:id] == id }
    end

    def types
      types_of(rows)
    end

    def tags
      tags_of(rows)
    end

    # The same tallies over an arbitrary subset, so the graph view can count
    # within a facet ("among Capability concepts, which tags?") rather than only
    # over the whole bundle.
    # okf's one rule for `--dir`: a directory names itself and everything beneath
    # it. `.` needs no special case — nothing starts with "./", so the root
    # selects only what lives directly in it, which is why okf's own `dirs` view
    # reports a subtree of 1 for the root of a five-concept bundle.
    #
    # Asked rather than re-spelled. This was a hand-written copy — byte-identical
    # to okf's, which is the good case and still the wrong one: okf published the
    # rule as `Bundle::RowFilter.under_dir?` precisely because three shells had
    # spelled it separately and diverged three recorded times. Both sides are
    # already okf's canonical spellings — a row's `dir` is `OKF.dir_of`, a facet's
    # value came out of `Bundle#directories` — so none of okf's argument handling
    # applies: no `root` alias to resolve, no trailing slash to trim, nothing here
    # was typed by a user.
    #
    # dirs_test.rb pins the result against okf's own subtree counts — agreement on
    # answers, which is what actually matters and what would survive okf changing
    # the rule underneath.
    def self.under_dir?(dir, ancestor)
      OKF::Bundle::RowFilter.under_dir?(dir, ancestor)
    end

    # okf's own label for a concept whose type is missing or blank — the one its
    # graph index uses, so the two agree about what the bundle contains.
    UNTYPED = "Untyped"

    def self.type_label(type)
      OKF.blank?(type) ? UNTYPED : type.to_s
    end

    def types_of(subset)
      tally(subset.map { |row| Model.type_label(row[:type]) })
    end

    def tags_of(subset)
      tally(subset.flat_map { |row| row[:tags] })
    end

    # §5.4, counted on the *effective* value — the same rule `--status` narrows
    # by, so a concept that declared nothing is counted as the `stable` it already
    # means rather than dropped. Without that the group would hide the majority
    # the one deprecated concept is measured against.
    def statuses_of(subset)
      tally(subset.map { |row| OKF::Concept.effective_status(row[:status]) })
    end

    # §5.3, counted only over rows whose tier this screen is willing to claim.
    # Counting the rest would make the facet promise more concepts than selecting
    # it returns — okf hit exactly that and describes it as "unverified 3" over
    # two chipped cards.
    def tiers_of(subset)
      tally(subset.select { |row| Model.shows_trust?(row) }.map { |row| row[:trust] })
    end

    # Each directory with the number of concepts at or below it — the same
    # "subtree" okf's `dirs` view prints, and by construction exactly what
    # narrowing to that directory will yield.
    #
    # Kept in okf's order (root first, then alphabetically) rather than sorted by
    # count like types and tags: a directory list sorted by size scrambles parents
    # away from their children, and the shape of the tree is the thing full-path
    # dirs exist to show.
    #
    # A directory with nothing under it is dropped — `history/`, whose only file is
    # its log, is a real directory that okf counts and `--dir` addresses, but as a
    # facet it is a row that narrows to nothing. The header's dir count still
    # includes it; the two answer different questions.
    def dirs_of(subset)
      dirs.map { |dir| [ dir, subset.count { |row| Model.under_dir?(row[:dir], dir) } ] }
          .reject { |_dir, count| count.zero? }
    end

    # Findings keyed by the concept path they were raised against, so the browse
    # pane can badge a concept with its own problems.
    def findings_by_path
      @findings_by_path ||= lint.findings.group_by { |finding| finding[:path] }
    end

    def findings_for(row)
      findings_by_path[row[:id]] || findings_by_path[row[:path]] || []
    end

    # index.md and log.md — structure rather than concepts, so the reader keeps
    # them as raw text (§6). The browse list shows them because they are part of
    # what is in the bundle, and often the first thing worth reading.
    def reserved
      bundle.reserved
    end

    # The body without its frontmatter, exactly as Bundle#directory_index does
    # it — the reader keeps reserved files as raw text, and the header is
    # metadata rather than something to read.
    def reserved_text(path)
      content = bundle.reserved_content(path)
      OKF::Markdown::Frontmatter.parse(content).last
    rescue OKF::Markdown::Frontmatter::ParseError
      content
    end

    def body_for(row)
      concept = concept_by_id(row[:id])
      concept ? concept.body.to_s : ""
    end

    # The outgoing cross-links of one document, in reading order and deduped by
    # target — what the reader can follow out of the page it is on.
    #
    # okf owns both halves. Markdown::Links is the same extraction Bundle::Graph
    # builds its edges with and the validator warns on, so a link the TUI offers
    # to follow is one okf already resolved; nothing here opens a file or parses
    # markdown of its own. Memoized per path, like every other analysis.
    def links_for(path)
      @links_for ||= {}
      return @links_for[path] if @links_for.key?(path)

      @links_for[path] = build_links(path)
    end

    private

    def id_by_path
      @id_by_path ||= bundle.paths_by_id.map { |id, path| [ path, id ] }.to_h
    end

    def reserved_paths
      @reserved_paths ||= reserved.map { |entry| [ entry.path, true ] }.to_h
    end

    # A concept body or a reserved file's text — both are documents to read, so
    # both can be followed out of.
    def document_body(path)
      id = id_by_path[path]
      return concept_by_id(id).body.to_s if id

      reserved_paths.key?(path) ? reserved_text(path).to_s : ""
    end

    def build_links(path)
      seen = {}
      OKF::Markdown::Links.extract(document_body(path)).each_with_object([]) do |raw, links|
        target = resolve_target(raw, path)
        next if target.nil? || target == path || seen.key?(target)

        seen[target] = true
        links << describe_link(target)
      end
    end

    # okf returns nil for a directory target, and is right to: `decisions/` is
    # not a graph edge and the validator has nothing to check about it. But it is
    # how every index.md points at its area, and §6 makes index.md the way in —
    # so the *root* index, the bundle's front door, would otherwise be the one
    # page with nothing to follow. Reading it as that directory's index is a
    # lookup in the reserved list okf already handed us: no directory is walked,
    # no markdown is parsed, and a directory with no index.md stays unfollowable.
    def resolve_target(raw, from)
      resolved = OKF::Markdown::Links.resolve(raw, from: from, bundle: bundle.root)
      return resolved if resolved

      target = raw.to_s.split("#", 2).first.to_s
      return nil unless target.end_with?("/")

      index = OKF::Markdown::Links.resolve("#{target}index.md", from: from, bundle: bundle.root)
      index && reserved_paths.key?(index) ? index : nil
    end

    # What sits at the other end: a concept, a reserved file, or nothing yet.
    # A target that resolves but is not in the bundle is not-yet-written
    # knowledge rather than an error — okf's own position, and lint is where it
    # gets reported.
    def describe_link(target)
      id = id_by_path[target]
      if id
        row = row_by_id(id)
        title = row ? row[:title].to_s : ""
        return { target: target, kind: :concept, id: id, type: row && row[:type],
                 label: title.empty? ? id : title }
      end

      return { target: target, kind: :reserved, id: nil, type: nil, label: reserved_label(target) } if reserved_paths.key?(target)

      { target: target, kind: :missing, id: nil, type: nil, label: target }
    end

    # A nested index.md is really the name of its area — that is what the link
    # meant, and what the reader is going to.
    def reserved_label(target)
      dir = File.dirname(target)
      base = File.basename(target)
      return base if dir == "."

      base == "index.md" ? dir : "#{dir}/#{base}"
    end

    # Blank values are dropped — a tag cannot be blank and a blank *type* has already
    # become UNTYPED by the time it arrives here. It used to be dropped instead, so
    # the type facet silently omitted every untyped concept: no row, and no way to
    # narrow to them, in the one view for exploring the bundle's shape — and untyped
    # concepts are exactly what a curator is looking for, since §9.2 requires a type.
    # okf names them rather than hiding them, and structure_test pins the agreement.
    def tally(values)
      counts = Hash.new(0)
      values.each { |value| counts[value.to_s] += 1 unless OKF.blank?(value) }
      counts.sort_by { |value, count| [ -count, value ] }
    end
  end
end
