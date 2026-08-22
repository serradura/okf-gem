# frozen_string_literal: true

require "tty-cursor"
require "tty-reader"
require "tty-screen"
require "tty-markdown"

require_relative "ui"
require_relative "model"
require_relative "views"

module OKF::TUI
  # The interactive loop: hold the state, read a key, mutate the state, repaint.
  #
  # Painting is whole-frame. Every view returns a rectangle of rows already
  # padded to the terminal width, so a repaint is "cursor home, print N rows" —
  # each row overwrites the one beneath it exactly, which is what keeps the
  # screen from flickering without any diffing machinery.
  #
  # Two axes of state, and keeping them apart is what makes the views simple:
  # the **active bundle** (what browse, health and graph are about) and the
  # **scope** (which bundles a search covers). Only the bundles view moves the
  # first; only the scope keys move the second.
  class App
    # Control keys, named so the source carries no invisible bytes.
    CTRL_C = "\u0003"
    CTRL_D = "\u0004"
    CTRL_U = "\u0015"
    DELETE = "\u007F"
    # Joins a group slug to one of its members inside a prompt's subject. A NUL can
    # appear in neither, which is why okf uses the same byte to key its own corpus.
    MEMBER_REF = "\u0000"
    ESCAPE = "\e"
    TAB = "\t"
    UP = "\e[A"
    DOWN = "\e[B"

    # The views that are about one bundle, and so have nothing to show when
    # none can be read.
    SINGLE_BUNDLE_VIEWS = %i[browse health graph].freeze

    # The views that are a single scrolling page rather than a selectable list.
    CONTENT_VIEWS = %i[health help].freeze

    # Six, and `help` stays last where a reader expects it. There was a seventh —
    # an `index` map beside `browse` — and it went because browse answers the same
    # question with a key the reader already has: `/index` lists every way in, one
    # per directory, and opens the authored file. What the map could show and browse
    # cannot is real but narrow (the tree indented as it nests, `▪`/`·` for a
    # directory that authored no index.md, okf's synthesized listing for one, and
    # the per-directory type/tag rollups), and it did not earn a permanent tab.
    TABS = [
      [ :bundles, "bundles" ],
      [ :browse, "browse" ],
      [ :search, "search" ],
      [ :graph, "graph" ],
      [ :health, "health" ],
      [ :help, "help" ]
    ].freeze

    KEY_VIEWS = { "1" => :bundles, "2" => :browse, "3" => :search,
                  "4" => :graph, "5" => :health, "6" => :help }.freeze

    # The views with a list to narrow. `/` starts typing in each of them; the
    # filter belongs to the view, so switching away drops it rather than
    # carrying a bundle filter into the concept list.
    FILTERABLE_VIEWS = %i[bundles browse graph].freeze

    # A pending question on the status line. `kind` decides what the answer does;
    # `free_text` says whether it collects a line or a single confirming key.
    class Prompt
      attr_reader :kind, :label, :buffer, :subject

      def initialize(kind:, label:, buffer:, subject:, free_text:)
        @kind = kind
        @label = label
        @buffer = buffer
        @subject = subject
        @free_text = free_text
      end

      def free_text?
        @free_text
      end
    end

    def initialize(dirs: [], ref_slugs: {}, home: nil, cwd: nil, output: $stdout)
      @output = output
      @workspace = Workspace.new(dirs: dirs, ref_slugs: ref_slugs, home: home, cwd: cwd)
      # With one readable bundle there is nothing to pick between, so open on it
      # directly. Otherwise start on the list — including when nothing is
      # readable, where the list is the only place the problem can be seen.
      @view = @workspace.entries.length == 1 && @workspace.model ? :browse : :bundles
      @pane = :list
      @cursor = 0
      @filter = +""
      @query = +""
      @searched = +"" # the query the current results belong to; see #search_hits
      @graph_facet = nil
      @search_focus = :results
      @search_mode = :fuzzy
      @find = +"" # find-in-document, when the detail pane has focus
      @finding = false
      @find_index = 0
      @find_jump = false
      @filtering = false
      @following = false # the link picker, over the document in the detail pane
      @follow_cursor = 0
      @follow_scroll = 0
      @group_cursor = 0  # the groups pane
      @group_scroll = 0
      @member_cursor = 0 # the member pane
      @trail = [] # where the reader was before each jump
      @prompt = nil
      @scroll = 0
      @detail_scroll = 0
      @content_scroll = 0
      # health's summary pane, which scrolls apart from its findings
      @health_scroll = 0
      @body_cache = {}
      @message = nil
      @running = true
      @quit_armed = false
      @cursor_control = TTY::Cursor
      @reader = TTY::Reader.new(interrupt: :exit, track_history: false)
      reset_cursor
    end

    # The active bundle. Nil only when nothing in the workspace could be read.
    def model
      workspace.model
    end

    def run
      @output.print @cursor_control.hide + @cursor_control.clear_screen
      paint
      loop do
        key = @reader.read_keypress(nonblock: false)
        break unless key

        handle(key)
        break unless @running

        paint
      end
    ensure
      @output.print @cursor_control.show + @cursor_control.clear_screen + @cursor_control.move_to(0, 0)
    end

    # ── frame ────────────────────────────────────────────────────────────────

    def paint
      width = TTY::Screen.width
      height = TTY::Screen.height

      header = Views.header(self, width)
      footer = [ Views.footer(self, width) ]
      body_height = [ height - header.length - footer.length - 1, 3 ].max

      # browse, health and graph are all about *a* bundle. With none readable
      # there is nothing for them to render, so the list stands in — it is the
      # one view that can still show what went wrong.
      view = model.nil? && SINGLE_BUNDLE_VIEWS.include?(@view) ? :bundles : @view

      body =
        case view
        when :bundles then Views.bundles(self, width, body_height)
        when :search then Views.search(self, width, body_height)
        when :health then Views.health(self, width, body_height)
        when :graph  then Views.graph(self, width, body_height)
        when :help   then Views.help(self, width, body_height)
        else Views.browse(self, width, body_height)
        end

      frame = header + Ui.fit_block(body, width: width, height: body_height) + [ message_row(width) ] + footer

      @output.print @cursor_control.move_to(0, 0)
      @output.print frame.first(height).join("\n")
      @output.flush
    end

    def message_row(width)
      Ui.line(width) do |row|
        if @prompt
          row.add(" #{@prompt.label} ", :black, :on_yellow, :bold)
          row.add(" #{@prompt.buffer}", :bright_white, :bold)
          row.add("▏", :yellow, :bold) if @prompt.free_text?
        elsif @finding
          row.add(" find: ", :black, :on_yellow, :bold)
          row.add(" #{@find}", :bright_white, :bold)
          row.add("▏", :yellow, :bold)
        elsif @filtering
          row.add(" filter: ", :black, :on_yellow, :bold)
          row.add(" #{@filter}", :bright_white, :bold)
          row.add("▏", :yellow, :bold)
        elsif find_status
          row.add("  #{find_status}", @find_total.to_i.zero? ? :yellow : :bright_black)
        elsif @message
          # Flash, in the strict sense: #handle clears it on the very next key, so
          # this line is on screen only until the user does anything at all. That is
          # what makes a strong mark right here rather than shouting — it cannot
          # become permanent noise, and :bright_black had made the one line that
          # reports what just happened the quietest thing on the screen.
          #
          # Cyan, not the yellow the prompt, find and filter lines wear. This row has
          # two states — it is *asking* you something, or it is *telling* you
          # something — and one colour each keeps them apart without reading a word.
          row.add(" #{@message} ", :black, :on_cyan, :bold)
        end
      end
    end

    def status_hints
      base =
        case @view
        when :bundles
          if filter_found_nothing?
            [ [ "↵", "search all bundles" ], [ "Esc", "clear filter" ] ]
          elsif @pane == :members
            [ [ "↑↓", "pick a member" ], [ "-", "remove it" ], [ "Esc", "back to the groups" ] ]
          elsif @pane == :groups
            [ [ "↵", "scope to it" ], [ "↑↓", "pick a group" ], [ "Tab", "its members" ],
              [ "n", "rename" ], [ "x", "delete" ], [ "Esc", "back to the bundles" ] ]
          else
            # The scope comes before the config keys, and `A`/`N` beside `space`. It
            # is one of the two axes this view is *about*, and the footer truncates:
            # at 80 columns everything from `d` rightward is already off screen, so
            # what the prefix names is the whole of what a narrow terminal teaches.
            # Reordered after "it is not clear how to control the scope" — which was
            # true, since neither `A` nor `N` appeared here at all.
            #
            #
            # `+` sits inside that prefix, and `a add` gave up the slot for it:
            # of the two keys a reader would have called "add", only one of them adds
            # to a group, and registering a directory is a once-per-bundle act that
            # the empty registry and view 6 both still teach.
            #
            # It does not name the group. The groups pane is right below with its own
            # cursor on the row, and spelling the slug out here read as a claim about
            # something the footer could not point at.
            [ [ "↵", "open" ], [ "space", "scope" ], [ "A/N", "all/none" ] ] +
              (selected_group ? [ [ "+", "join group" ] ] : []) +
              [ [ "/", "filter" ], [ "d", "default" ], [ "n", "rename" ], [ "x", "remove" ],
                [ "c", "group" ] ]
          end
        when :browse
          if @following
            [ [ "↑↓", "pick" ], [ "1-9", "jump straight to one" ], [ "↵", "follow" ],
              [ "Esc", "back to the body" ] ]
          elsif filter_found_nothing?
            [ [ "↵", "search all bundles" ], [ "Esc", "clear filter" ] ]
          elsif reading_body?
            # In the body, `/` looks through the document rather than the list.
            [ [ "↑↓ J/K", "scroll" ], [ "Tab", "pane" ], [ "/", "find in page" ], [ "f", "links" ] ] +
              (@find.empty? ? [] : [ [ "n/N", "next/prev match" ] ])
          else
            [ [ "↑↓", "move" ], [ "Tab", "pane" ], [ "J/K", "scroll body" ], [ "/", "filter" ], [ "f", "links" ] ]
          end
        when :search
          # Both Enter and the whole key set change with focus, so the hints do too.
          if editing_query?
            # `e` deliberately does not cycle the mode here — it is a letter, and
            # every letter belongs to the query while the field has focus. Esc
            # first, which the hint says.
            [ [ "type", "query" ], [ "↵", search_pending? ? "search" : "open" ],
              [ "Esc", "stop editing (then e changes the mode)" ] ]
          elsif @searched.empty?
            # Nothing searched yet, so there is nothing to navigate — the only
            # moves that matter are starting one, and choosing how it is asked.
            [ [ "/", "search" ], [ "e", search_mode_label ] ]
          else
            [ [ "↑↓", "results" ], [ "↵", "open" ], [ "/", "edit query" ], [ "e", search_mode_label ] ]
          end
        when :graph
          act = @pane == :detail ? "open concept" : "narrow by facet"
          hints = [ [ "↑↓", "move" ], [ "Tab", "pane" ], [ "↵", act ], [ "/", "filter" ] ]
          hints + (@graph_facet ? [ [ "Esc", "clear facet" ] ] : [])
        when :health
          # Two panes, each scrolling on its own, so Tab names the one the keys move.
          # A narrow terminal shows them one at a time and Tab swaps which — same key,
          # same meaning, a layout that stops pretending both fit.
          [ [ "↑↓", "scroll" ], [ "Tab", @pane == :detail ? "the findings" : "the standing" ],
            [ "/", "find" ] ] +
          (@find.empty? ? [] : [ [ "n/N", "next/prev match" ] ])
        else
          [ [ "↑↓", "scroll" ], [ "/", "find" ] ] +
          (@find.empty? ? [] : [ [ "n/N", "next/prev match" ] ])
        end
      # Only offered once there is somewhere to go back to, so the row does not
      # advertise a key that would do nothing.
      base += [ [ "⌫", "back" ] ] unless @trail.empty?
      base + [ %w[1-6 views], %w[r reload], %w[qq quit] ]
    end

    # ── bundles view state ───────────────────────────────────────────────────

    # The registry rows surviving the filter, matched on slug or path — the two
    # things a row shows that a user would type.
    def visible_entries
      return workspace.entries if @filter.empty?

      needle = @filter.downcase
      workspace.entries.select do |entry|
        "#{entry.slug} #{entry.dir}".downcase.include?(needle)
      end
    end

    # ── the bundles view's three panes ───────────────────────────────────────
    #
    # bundles (top left), groups (bottom left), and the detail of whichever of the
    # two has focus (right). Tab cycles; each pane keeps its own cursor.
    #
    # It was one interleaved list under a GROUPS heading, and the shape caused three
    # separate problems. The heading was a row nothing could select, so the cursor
    # had to skip it. A long registry pushed the groups below the fold, so they were
    # not reliably on screen at all. And with only one selection at a time, adding a
    # bundle to a group had nothing to name the bundle *with* — which is why `+`
    # reached for the search scope, and why it was the key that kept being wrong.
    #
    # Two selections make `+` direct: the bundle under the cursor joins the group
    # that is selected. Nothing about searching is involved.
    PANES = %i[bundles groups members].freeze

    def bundles_pane?
      @view == :bundles && @pane == :bundles
    end

    def groups_pane?
      @view == :bundles && @pane == :groups
    end

    def member_pane?
      @view == :bundles && @pane == :members && !selected_group.nil?
    end

    # Which of the two left panes the detail pane is describing. The members pane is
    # a view *of* a group, so it counts as the groups side.
    def detailing_group?
      @view == :bundles && %i[groups members].include?(@pane) && !selected_group.nil?
    end

    # Groups surviving the filter, matched on the group's own name, on its members
    # as written, and on the bundles it resolves to.
    #
    # All three, because the resolved set is what the filter is usually asking
    # about — "which named scope covers @nested?" — and for a nested group that
    # bundle appears nowhere in the member list. Matching only the members would
    # answer @docs and hide @everything, which covers @nested just as much.
    def visible_groups
      groups = workspace.groups
      return groups if @filter.empty?

      needle = @filter.downcase
      groups.select do |group|
        haystack = [ group.slug, group.members.join(" "), group.bundles.join(" ") ].join(" ")
        haystack.downcase.include?(needle)
      end
    end

    # Each pane indexes its own *filtered* list, so every action lands on the row
    # the user is looking at.
    def selected_entry
      visible_entries[@cursor]
    end

    def selected_group
      visible_groups[@group_cursor]
    end

    # ── the member pane ──────────────────────────────────────────────────────
    #
    # A group's members are listed in the detail pane, so Tab moves into them and
    # `-` removes the one under the cursor. That is the same Tab the browse view has
    # always used, and it replaced a `-` on the group row that acted on the
    # *intersection* of the scope and the member list — a set with no row on screen,
    # which a reader had to compute to predict what the key would do.
    #
    # Adding stays on the group row, because the bundles to add are the ones marked
    # `◉` in the list beside it. Removing is the direction with something to point at.
    def group_members
      selected_group&.members || []
    end

    def selected_member
      group_members[@member_cursor]
    end

    def scoped?(slug)
      workspace.scoped?(slug)
    end

    # Whether the scope in force *is* this group's set — set equality rather than
    # overlap. A group's ◉ says "a search right now covers exactly these", so
    # toggling one member off has to clear it; treating a superset as a match would
    # leave two groups both claiming to be in force.
    # The group under the groups cursor, when this bundle is one of its members —
    # which is what decides whether the detail pane has a `+` to offer. Direct
    # members only, deliberately: a bundle reached through a *nested* group is in the
    # set a search covers but not in the list `+` would change.
    def member_group(slug)
      group = selected_group
      group if group&.members&.include?(slug)
    end

    def group_in_scope?(group)
      return false if group.bundles.empty?

      workspace.scope.sort == group.bundles.sort
    end

    # ── browse list state ────────────────────────────────────────────────────

    # Rows surviving the filter, in catalog order.
    def filtered_rows
      return [] unless model
      return model.rows if @filter.empty?

      needle = @filter.downcase
      model.rows.select do |row|
        [ row[:id], row[:title], row[:type], Array(row[:tags]).join(" ") ]
          .join(" ").downcase.include?(needle)
      end
    end

    # The browse list as a flat sequence of directory headings and concept rows. The
    # headings are entries too, so windowing and the cursor share one index
    # space — but only concept entries are selectable, which `move` enforces.
    def list_entries
      @list_entries_key ||= nil
      # `dup` matters: @filter is mutated in place as the user types, so keying
      # on the object itself would compare a key against its own later state and
      # the cache would never invalidate. The active bundle is part of the key
      # too, or switching bundles would keep showing the previous ones list.
      key = [ @filter.dup, workspace.active_slug ]
      return @list_entries if @list_entries_key == key

      entries = []
      browse_groups.each do |dir, group|
        entries << { kind: :dir, label: dir == "." ? "(root)" : dir, count: group[:concepts].length }
        group[:reserved].each { |path| entries << { kind: :reserved, path: path } }
        group[:concepts].each { |row| entries << { kind: :concept, row: row } }
      end

      @list_entries_key = key
      @list_entries = entries
    end

    # The bundle as it sits on disk: each directory in turn, its index.md first,
    # then its log.md, then its concepts — and the root before anything nested,
    # since that is the order someone reads a bundle in (§6 makes index.md the
    # way in). Sorting by path puts every subfolder directly under its parent.
    def browse_groups
      return {} unless model

      groups = Hash.new { |hash, dir| hash[dir] = { reserved: [], concepts: [] } }

      model.reserved.each do |entry|
        next unless matches_filter?(entry.path)

        groups[File.dirname(entry.path)][:reserved] << entry.path
      end

      filtered_rows.each do |row|
        groups[File.dirname(row[:path])][:concepts] << row
      end

      groups.each_value { |group| group[:reserved].sort_by! { |path| File.basename(path) } }
      groups.sort_by { |dir, _| dir == "." ? [ 0, "" ] : [ 1, dir ] }
    end

    def matches_filter?(text)
      @filter.empty? || text.to_s.downcase.include?(@filter.downcase)
    end

    def selectable_indices
      list_entries.each_index.select { |index| %i[concept reserved].include?(list_entries[index][:kind]) }
    end

    # The row under the cursor, or the first one, when it is a concept. A
    # reserved file has no catalog row — the detail pane asks for it separately.
    def selected_row
      entry = selected_browse_entry
      entry && entry[:kind] == :concept ? entry[:row] : nil
    end

    def selected_browse_entry
      entry = list_entries[@cursor]
      return entry if entry && %i[concept reserved].include?(entry[:kind])

      first = selectable_indices.first
      first ? list_entries[first] : nil
    end

    # ── graph view state ─────────────────────────────────────────────────────
    #
    # The graph is two selectable lists rather than a page: facets on the left
    # (a type or a tag), concepts on the right. Tab moves between them, and what
    # Enter means follows from which kind of row the cursor is on — narrow by
    # this facet, or go read this concept.

    attr_reader :workspace, :view, :pane, :cursor, :filter, :query, :searched, :prompt, :find, :find_index,
      :graph_facet, :follow_cursor, :group_cursor, :member_cursor, :search_mode

    # Concepts the facet admits. Selecting `Capability` does not recompute link
    # degree — the counts stay the bundle's real ones — it narrows *which*
    # concepts the lists are drawn from.
    def faceted_rows
      return [] unless model
      return model.rows if @graph_facet.nil?

      field = @graph_facet[:field]
      value = @graph_facet[:value]
      model.rows.select { |row| facet_admits?(row, field, value) }
    end

    # A type and a tag match exactly; a dir names itself and everything beneath it,
    # which is okf's `--dir` rule (see Model.under_dir?). Narrowing to `platform`
    # therefore reaches `platform/services/api`, exactly as `okf catalog --dir
    # platform` does — a dir facet that matched only its own level would be the
    # first-path-segment rollup `--area` was, which okf deprecated for losing every
    # level below it.
    def facet_admits?(row, field, value)
      case field
      when :type then Model.type_label(row[:type]) == value
      when :dir then Model.under_dir?(row[:dir], value)
      # §5.4 and §5.3, narrowed exactly as `--status` and `--trust` narrow —
      # okf's own predicate, so an absent status reads `stable` here the way it
      # reads `stable` there, and a tier folds both spellings. Trust also gates on
      # what the row is willing to claim, so the facet covers exactly the rows
      # wearing a tier: counting rows this screen shows no tier for would narrow
      # to more concepts than the count promised.
      when :status then OKF::Bundle::RowFilter.matches?(row, status: value)
      when :trust then Model.shows_trust?(row) && OKF::Bundle::RowFilter.matches?(row, trust: value)
      else Array(row[:tags]).map(&:to_s).include?(value)
      end
    end

    def facet_active?(field, value)
      @graph_facet && @graph_facet[:field] == field && @graph_facet[:value] == value
    end

    # Left pane: the type and tag tallies, counted within the facet in force.
    def graph_facet_entries
      return [] unless model

      subset = faceted_rows
      types = Views.narrow(model.types_of(subset), @filter)
      tags = Views.narrow(model.tags_of(subset), @filter).first(12)
      dirs = Views.narrow(model.dirs_of(subset), @filter)

      entries = [ { kind: :heading, label: "types", colour: :cyan } ]
      entries.concat(facet_rows(types, :type))
      entries << { kind: :blank }
      entries << { kind: :heading, label: "tags", colour: :magenta }
      entries.concat(facet_rows(tags, :tag))

      # Only where the bundle actually nests. The test is a directory with a
      # separator in it, not a count of directories: `conformant/` has two
      # (datasets, tables) and is still one level deep, where every dir facet says
      # exactly what a top-level rollup would — and a rollup is what okf deprecated
      # `--area` for being. okf takes the same view on its graph page, which offers
      # a bundle that does not nest no depth control at all.
      if dirs.any? { |dir, _count| dir.include?("/") }
        entries << { kind: :blank }
        entries << { kind: :heading, label: "dirs", colour: :yellow }
        entries.concat(facet_rows(dirs, :dir))
      end

      entries.concat(provenance_facets(subset))
      entries
    end

    # §5's two facets, offered only where the bundle has something to say — the
    # same rule the dir facet follows, and the same rule okf's own graph page
    # applies to these two.
    #
    # Status needs one *declared* value, because a lone `stable` row is what an
    # undeclared status already means; the counts then use the effective value, so
    # the group reads `stable 22 · deprecated 1` rather than hiding the majority
    # the one deprecated concept is measured against. Trust needs one tier okf is
    # willing to claim, or every v0.1 bundle would offer a facet whose only row
    # said "unverified" about a family it never adopted — and both the count and
    # the narrowing read that same predicate, so the row and what it selects agree.
    def provenance_facets(subset)
      entries = []

      if subset.any? { |row| !row[:status].to_s.empty? }
        statuses = Views.narrow(model.statuses_of(subset), @filter)
        unless statuses.empty?
          entries << { kind: :blank }
          entries << { kind: :heading, label: "status", colour: :yellow }
          entries.concat(facet_rows(statuses, :status))
        end
      end

      tiers = Views.narrow(model.tiers_of(subset), @filter)
      unless tiers.empty?
        entries << { kind: :blank }
        entries << { kind: :heading, label: "trust", colour: :green }
        entries.concat(facet_rows(tiers, :trust))
      end

      entries
    end

    # Each block of bars is scaled to its own tallest, and its labels padded to
    # its own longest, so the two sections read independently.
    def facet_rows(pairs, field)
      peak = pairs.map { |_, count| count }.max
      pad = pairs.map { |value, _| Ui.width(value.to_s) }.max

      pairs.map do |value, count|
        { kind: :facet, field: field, value: value, count: count, peak: peak, pad: pad }
      end
    end

    # Right pane: the hubs and orphans among those concepts.
    def graph_concept_entries
      return [] unless model

      subset = Views.narrow_rows(faceted_rows, @filter)
      entries = []

      entries << { kind: :heading, label: "most linked-to", colour: :blue }
      entries.concat(degree_entries(subset, :links_in, :blue))
      entries << { kind: :blank }
      entries << { kind: :heading, label: "most linked-from", colour: :green }
      entries.concat(degree_entries(subset, :links_out, :green))
      entries << { kind: :blank }

      orphans = subset.map { |row| row[:id] } & model.orphan_ids
      entries << { kind: :heading, label: "orphans (no edges either way)", colour: orphans.empty? ? :green : :yellow }
      if orphans.empty?
        entries << { kind: :note, label: "every concept is reachable", colour: :green }
      else
        pad = orphans.first(6).map { |id| Ui.width(id.to_s) }.max
        orphans.first(6).each { |id| entries << { kind: :concept, id: id, count: 0, peak: 1, pad: pad, colour: :yellow } }
      end

      entries
    end

    def degree_entries(subset, field, colour)
      top = subset.sort_by { |row| -row[field].to_i }.first(8)
      peak = top.map { |row| row[field].to_i }.max
      pad = top.map { |row| Ui.width(row[:id].to_s) }.max

      top.map do |row|
        { kind: :concept, id: row[:id], count: row[field].to_i, peak: peak, pad: pad, colour: colour }
      end
    end

    def graph_entries
      @pane == :detail ? graph_concept_entries : graph_facet_entries
    end

    def graph_selectable
      graph_entries.each_index.select { |index| %i[facet concept].include?(graph_entries[index][:kind]) }
    end

    def graph_selected
      graph_entries[@cursor]
    end

    # ── scrolling ────────────────────────────────────────────────────────────

    # The first visible index, scrolled just enough to keep the cursor on screen.
    def window(count, height)
      height = [ height, 1 ].max
      @scroll = [ @scroll, @cursor - height + 1 ].max
      @scroll = [ @scroll, @cursor ].min
      @scroll = [ [ @scroll, count - height ].min, 0 ].max
      @scroll
    end

    # The groups pane scrolls independently of the bundles pane, so it needs its own
    # offset: sharing @scroll would make paging one list drag the other.
    def group_window(count, height)
      height = [ height, 1 ].max
      @group_scroll = [ @group_scroll.to_i, @group_cursor - height + 1 ].max
      @group_scroll = [ @group_scroll, @group_cursor ].min
      @group_scroll = [ [ @group_scroll, count - height ].min, 0 ].max
    end

    def detail_scroll_for(count, visible)
      max = [ count - visible, 0 ].max
      @detail_scroll = [ [ @detail_scroll, max ].min, 0 ].max
    end

    # The offset for the views that are one long page rather than a list —
    # health, graph and help. Clamped here, against the row count the view
    # actually produced, so the state can never point past the end.
    def content_scroll_for(count, visible, key = :content)
      max = [ count - visible, 0 ].max
      set_scroll(key, [ [ scroll_for(key), max ].min, 0 ].max)
    end

    # Health is two pages side by side and each keeps its own place: the findings
    # are unbounded and the summary is not, so one shared offset would drag the
    # short pane to its end and hold it there while the long one scrolled.
    def scroll_for(key)
      key == :health ? @health_scroll : @content_scroll
    end

    def set_scroll(key, value)
      key == :health ? (@health_scroll = value) : (@content_scroll = value)
    end

    # Which of the two the keys move: the one with focus.
    def content_scroll_key
      @view == :health && @pane == :detail ? :health : :content
    end

    # Wide enough that tty-markdown never wraps a line itself.
    #
    # Its wrapper (the `strings` gem) miscounts ANSI escapes and raises
    # IndexError from String#insert on coloured input — 50 of 192 concept/width
    # combinations in the okf bundle alone, and only in a real terminal, since a
    # pipe turns the colour off. Handing it a width it can never reach sidesteps
    # the wrapping entirely, and Ui.reflow does the job instead: it was already
    # re-wrapping this output anyway, because tty-markdown otherwise keeps the
    # source line breaks. Tables come out at their natural width and are clipped
    # to the pane exactly as before.
    PARSE_WIDTH = 10_000

    # Concept bodies are rendered by tty-markdown once and cached — re-rendering
    # on every keypress is what would make scrolling feel heavy. Keyed by bundle
    # too, since ids are only unique within one.
    def rendered_body(row, width)
      render_markdown([ workspace.active_slug, row[:id], width ], model.body_for(row), width)
    end

    def rendered_reserved(path, width)
      render_markdown([ workspace.active_slug, :reserved, path, width ], model.reserved_text(path), width)
    end

    def render_markdown(cache_key, source, width)
      @body_cache[cache_key] ||= begin
        if source.to_s.strip.empty?
          [ Ui.pastel.decorate("(empty)", :bright_black) ]
        else
          limit = [ width, 20 ].max
          # Say the colour decision out loud rather than letting tty-markdown
          # sniff the terminal: it is the coloured path that trips the wrapping
          # bug PARSE_WIDTH avoids, and a check that cannot turn colour on
          # cannot see that bug at all.
          mode = Ui.pastel.enabled? ? :always : :never
          Ui.reflow(TTY::Markdown.parse(source, width: PARSE_WIDTH, color: mode).lines, limit)
        end
      rescue StandardError => e
        # Name the failure. "IndexError" alone sent this one looking in the
        # wrong place for a while.
        [ Ui.pastel.decorate("(could not render markdown: #{e.class}: #{e.message})", :red) ]
      end
    end

    # Cross-bundle: the hits come from every scoped bundle, ranked together.
    #
    # Results belong to `@searched`, not to `@query`, and only Enter moves one to
    # the other. Searching per keystroke meant building a fresh index over every
    # scoped bundle for each letter, and the view churning through answers to
    # half-typed words; a timed pause fixed the cost but still left the moment
    # of searching up to a guess about typing rhythm. Submitting is explicit
    # instead, so the field edits freely and the results below hold still.
    def search_hits
      return [] if @searched.empty? # nothing submitted yet — nothing to ask

      key = [ @searched.dup, workspace.scope, @search_mode ]
      return @search_hits if @search_hits_key == key

      @search_hits_key = key
      @search_hits = workspace.search(@searched, mode: @search_mode)
    end

    # The three ways okf can be asked a question, cycled with `e`. Modes rather than
    # engine names, because that is how okf routes: a query declares the capability
    # it needs and the facade picks the engine that has it.
    SEARCH_MODES = [
      { id: :fuzzy, label: "fuzzy", note: "ranked, typo-tolerant — misses terms glued to symbols" },
      { id: :text, label: "text", note: "raw substring, okf's default — finds $OKF_HOME and `minifts`" },
      { id: :regexp, label: "regexp", note: "a pattern over the same raw text" }
    ].freeze

    def search_mode_entry
      SEARCH_MODES.find { |mode| mode[:id] == @search_mode } || SEARCH_MODES.first
    end

    def search_mode_label
      search_mode_entry[:label]
    end

    def search_mode_note
      search_mode_entry[:note]
    end

    # Cycling re-asks the question rather than leaving the previous engine's answer
    # sitting under a new label: the hits are keyed on the mode, so it reruns.
    def cycle_search_mode
      index = SEARCH_MODES.index { |mode| mode[:id] == @search_mode }.to_i
      @search_mode = SEARCH_MODES[(index + 1) % SEARCH_MODES.length][:id]
      @cursor = 0
      @message = "search: #{search_mode_label} — #{search_mode_note}"
    end

    # Does the search field have focus — i.e. do printable keys type into it?
    def editing_query?
      @view == :search && @search_focus == :field
    end

    def focus_field
      @search_focus = :field
    end

    # Stop editing, stay where you are.
    #
    # Unsearched edits are dropped, not run: Esc is how you abandon a query you
    # started typing, and running it would be the opposite of stopping. Reverting
    # to the query the results actually answer also means the field and the list
    # below it always agree once the field is released — there is no lingering
    # "these results are for something else" state to explain.
    def leave_field
      @query = @searched.dup
      @search_focus = :results
    end

    # Is there typing the results have not caught up with yet?
    def search_pending?
      @view == :search && @searched != @query
    end

    # Adopt the typed query and let the next #search_hits do the work. Called
    # from the loop after the pause, and directly on Enter.
    def commit_search
      return false unless @searched != @query

      @searched = @query.dup
      @cursor = 0
      @scroll = 0
      true
    end

    # ── input ────────────────────────────────────────────────────────────────

    def handle(key)
      return handle_prompt(key) if @prompt

      @message = nil
      # Whether the *previous* key armed the quit, and the disarm for this one.
      # Above the mode handlers on purpose: typing `q` into a filter or a query
      # has to cancel the arming too, or the chord leaks across a text field.
      armed = @quit_armed
      @quit_armed = false
      # The picker is the innermost mode, so it owns the keyboard outright —
      # including the digits, which is the whole reason it is a mode and not a
      # pane. `1` picks a link while it is open; everywhere else it is view one.
      return handle_follow(key) if @following
      return handle_find(key) if @finding
      return handle_filter(key) if @filtering
      # Only while the field has focus do printable keys mean query text. Once
      # Esc leaves it, the search view answers the same keys as everywhere else.
      return handle_query(key) if @view == :search && @search_focus == :field

      if KEY_VIEWS.key?(key)
        switch(KEY_VIEWS[key])
        return
      end

      case key
      when "q" then armed ? (@running = false) : arm_quit
      # Ctrl-C stays single. It is the escape hatch, and an escape hatch that
      # needs confirming is not one.
      when CTRL_C then @running = false
      when "?" then switch(:help)
      when "j", DOWN then move(1)
      when "k", UP then move(-1)
      when "g" then jump(:first)
      when "G" then jump(:last)
      when CTRL_D then move(10)
      when CTRL_U then move(-10)
      # A `when` matches whether or not its guard holds, so these must hand the
      # key back rather than swallow it — `n` is rename in the bundles view.
      when "n" then findable? ? step_match(1) : fallback(key)
      when "N" then findable? ? step_match(-1) : fallback(key)
      when "J" then @detail_scroll += 3
      when "K" then @detail_scroll = [ @detail_scroll - 3, 0 ].max
      when TAB then toggle_pane
      when "f" then start_follow
      when DELETE then back
      when "/" then start_typing
      when "i" then focus_field if @view == :search
      when "e" then cycle_search_mode if @view == :search
      when "s" then switch(:search)
      when "r" then reload
      when "\r", "\n" then handle_return
      when ESCAPE then handle_escape
      else fallback(key)
      end
    end

    def fallback(key)
      handle_bundle_key(key) if @view == :bundles
    end

    def running?
      @running
    end

    # `q` quit on the first press, so one stray keystroke ended the session with
    # nothing to undo it. It arms instead, and says so — a chord nobody is told
    # about is just a key that stopped working.
    def arm_quit
      @quit_armed = true
      @message = "press q again to quit"
    end

    # Enter, once the field no longer has focus: open whatever is selected.
    def handle_return
      case @view
      when :search then open_hit
      when :browse then escalate_to_search if filter_found_nothing?
      when :graph then activate_graph_row
      when :bundles then filter_found_nothing? ? escalate_to_search : open_registry_row
      end
    end

    # The keys that only mean something over the registry list.
    def handle_bundle_key(key)
      case @pane
      when :members then member_key(key)
      when :groups then group_key(key)
      else bundle_key(key)
      end
    end

    # The bundles pane. `+` is the one that reaches across: the bundle under this
    # cursor joins the group selected in the pane below, which is two visible rows
    # rather than an invisible set.
    def bundle_key(key)
      case key
      when " " then toggle_scope
      when "A" then workspace.scope_all && @search_hits_key = nil
      when "N" then workspace.scope_none && @search_hits_key = nil
      when "d" then set_default
      when "a" then ask(:add, "directory to register:", free_text: true)
      when "n" then ask_rename
      when "x" then ask_remove
      when "c" then ask_group
      when "+" then add_selected_to_group
      # Removal lives in the pane that lists the members, where each one has a row
      # of its own. Saying so beats going silent: a key that quietly stopped working
      # is indistinguishable from a broken one.
      when "-" then @message = "- removes a member: Tab to the groups, Tab again into them"
      end
    end

    # The groups pane. `n` and `x` are the same keys they are for a bundle, on the
    # slug this pane has selected — okf's rename and del span a group and cascade.
    def group_key(key)
      case key
      when "n" then ask_rename
      when "x" then ask_remove
      when "c" then ask_group
      when "+" then @message = "+ adds from the bundles pane — Tab back, point at one, then +"
      when "-" then @message = "- removes a member: Tab into them, or point at the bundle and press -"
      end
    end

    def member_key(key)
      case key
      when "-" then ask_member_removal
      end
    end

    # `c` names the bundles now in scope. The scope *is* the selection in this
    # view — `◉` says so on every row — so a group is made by toggling what you
    # want and giving it a name, rather than by typing a member list a second time.
    def ask_group
      scoped = workspace.scope
      return (@message = "nothing in scope to name — space toggles a bundle in") if scoped.empty?

      ask(:group, "name for a group of #{scoped.length} scoped #{scoped.length == 1 ? "bundle" : "bundles"}:",
        free_text: true)
    end

    # `+` and `-` on a group row: the cursor names the group, the scope names the
    # bundles. No prompt, because neither half is ambiguous — which is the reason
    # to spend the scope on this rather than ask for a typed list.
    # `+` from the bundles pane: the bundle under this cursor joins the group the
    # groups pane has selected. Two rows, both on screen, neither of them the search
    # scope — which is what the earlier cuts of this key got wrong twice.
    #
    # Additive and reversible, so it does not ask.
    def add_selected_to_group
      entry = selected_entry
      group = selected_group
      return (@message = "no bundle here to add") if entry.nil?
      return (@message = "no group to add it to — c names the bundles in scope as one") if group.nil?
      return (@message = "@#{group.slug} already names @#{entry.slug}") if group.members.include?(entry.slug)
      # Both halves: a linked bundle cannot be stored as a member (its name lives
      # only while its link resolves), and a linked group cannot be written to.
      return if refused_linked?(entry, "grouping")
      return if refused_linked?(group, "adding to")

      apply_group_edit_keeping_focus do
        keeping_group_scoped(group.slug) { workspace.add_to_group(group.slug, [ entry.slug ]) }
      end
    end

    # A group that *is* the scope in force stays in force across an edit to it.
    # Without this, `+` on a bundle left the ◉ on its row hollow and quietly emptied
    # the one on the group row too: the group had grown, the scope had not, so set
    # equality stopped holding and a search still covered the old set. The report was
    # the visible half — "it does not select the bundle" — and this was the cause.
    #
    # Only when it was in force beforehand. Re-scoping a group nobody had scoped
    # would make an edit to it silently replace the reader's own selection.
    def keeping_group_scoped(slug)
      group = workspace.group(slug)
      in_force = !group.nil? && group_in_scope?(group)
      message = yield
      workspace.scope_group(slug) if in_force && workspace.group(slug)
      message
    end

    # Removing acts on the member row under the cursor — one member, the one being
    # pointed at. It still asks, because okf deletes a group whose last member
    # leaves, so this key can destroy the group rather than trim it, and the question
    # says which of the two is about to happen.
    def ask_member_removal
      group = selected_group
      return (@message = "Tab into a group's members to remove one") if group.nil?

      member = selected_member
      return (@message = "@#{group.slug} has no members to remove") if member.nil?

      ask_member_gone(group, member)
    end

    # One question for both panes that can ask it, so the consequence is named the
    # same way whichever row the reader was pointing at.
    def ask_member_gone(group, member)
      label =
        if group.members.length == 1
          "remove @#{member} — its last, so @#{group.slug} goes too. remove? (y/n)"
        else
          "remove @#{member} from @#{group.slug}? (y/n)"
        end

      ask(:ungroup, label, free_text: false, subject: [ group.slug, member ].join(MEMBER_REF))
    end

    # The cursor stays where it was in both panes: a write should not move the
    # reader, and with two selections there are two to preserve.
    def apply_group_edit_keeping_focus
      bundle = selected_entry&.slug
      group = selected_group&.slug
      @message = yield
      @search_hits_key = nil
      invalidate
      clamp_cursor
      focus(bundle) if bundle
      focus_group(group) if group
      @message
    end

    # Keep the cursor on the group that was just edited, rather than on whatever
    # ends up at that index after the reload — the same reason #set_default follows
    # its bundle instead of its position.
    def focus_group(slug)
      index = visible_groups.index { |group| group.slug == slug }
      @group_cursor = index if index
      @message
    end

    # Find-in-document. Live rather than submitted: this only scans the lines
    # already rendered, so it costs nothing to follow every keystroke, and
    # watching the body jump as you type is the whole point.
    def handle_find(key)
      case key
      when "\r", "\n" then @finding = false
      when ESCAPE then clear_find
      when DELETE, "\b" then (@find.chop! || @find) && jump_to_match(0)
      when CTRL_C then @running = false
      else
        return unless printable?(key)

        @find << key
        jump_to_match(0)
      end
    end

    # ── following a link ─────────────────────────────────────────────────────
    #
    # The links of the document in the detail pane, in reading order. Both kinds
    # of document have them: a concept body, and a reserved file — and it is the
    # reserved ones that matter most, since an index.md is a list of links by
    # design (§6) and the log is a list of what changed where.

    def follow_links
      return [] unless model

      entry = selected_browse_entry
      return [] if entry.nil?

      path = entry[:kind] == :reserved ? entry[:path] : entry[:row][:path]
      model.links_for(path.to_s)
    end

    def following?
      @following
    end

    def start_follow
      return unless @view == :browse

      if follow_links.empty?
        @message = "no links in this document"
        return
      end

      @following = true
      @follow_cursor = 0
      @follow_scroll = 0
      # The picker draws where the body does, so the pane it belongs to has to
      # be the one showing.
      @pane = :detail
    end

    def handle_follow(key)
      links = follow_links

      case key
      when ESCAPE, "f" then @following = false
      when CTRL_C then @running = false
      when "\r", "\n" then follow_selected(links)
      when "j", DOWN then @follow_cursor = [ @follow_cursor + 1, links.length - 1 ].min
      when "k", UP then @follow_cursor = [ @follow_cursor - 1, 0 ].max
      when "g" then @follow_cursor = 0
      when "G" then @follow_cursor = [ links.length - 1, 0 ].max
      when /\A[1-9]\z/
        index = key.to_i - 1
        return if index >= links.length

        @follow_cursor = index
        follow_selected(links)
      end
    end

    def follow_selected(links)
      link = links[@follow_cursor]
      return if link.nil?

      case link[:kind]
      when :concept
        @following = false
        open_concept(link[:id])
        @message = "opened #{link[:id]}"
      when :reserved
        @following = false
        open_reserved(link[:target])
        @message = "opened #{link[:target]}"
      else
        # Not an error: a link with nothing at the end of it is knowledge that
        # has not been written yet — okf's own position, and lint's job to
        # report. The picker says so and stays open, because a dead link means
        # the reader has not finished choosing, and closing would make them
        # press `f` again to find that out.
        @message = "#{link[:target]} is not in this bundle yet"
      end
    end

    # The window over the picker, mirroring #window — its own offset, because
    # the list pane's scroll belongs to a different list.
    def follow_window(count, height)
      height = [ height, 1 ].max
      @follow_scroll = [ @follow_scroll, @follow_cursor - height + 1 ].max
      @follow_scroll = [ @follow_scroll, @follow_cursor ].min
      @follow_scroll = [ [ @follow_scroll, count - height ].min, 0 ].max
    end

    # ── the way back ─────────────────────────────────────────────────────────
    #
    # A jump nobody can undo is a jump nobody makes twice. Pushed inside the two
    # openers, which means following a link, opening a search hit and leaving the
    # graph for a concept are all reversible by the same key.

    MAX_TRAIL = 32

    def trail_depth
      @trail.length
    end

    def push_trail
      @trail << { slug: workspace.active_slug, view: @view, pane: @pane, cursor: @cursor,
                  scroll: @scroll, detail_scroll: @detail_scroll, filter: @filter.dup }
      @trail.shift while @trail.length > MAX_TRAIL
    end

    def back
      spot = @trail.pop
      return if spot.nil?

      # activate resets every offset, so the remembered ones are restored after
      # it rather than before — otherwise the bundle switch quietly wipes them.
      activate(spot[:slug]) if spot[:slug] != workspace.active_slug
      @following = false
      @view = spot[:view]
      @pane = spot[:pane]
      @filter = spot[:filter].dup
      @list_entries_key = nil
      @cursor = spot[:cursor]
      @scroll = spot[:scroll]
      @detail_scroll = spot[:detail_scroll]
      @message = "back"
    end

    def clear_find
      @finding = false
      @find = +""
      @find_index = 0
      @find_jump = false
    end

    def jump_to_match(index)
      @find_index = index
      @find_jump = true
    end

    def step_match(delta)
      return unless findable? && !@find.empty?

      @find_index += delta
      @find_jump = true
    end

    # The lines of a rendered body carrying the term. Matched on the visible
    # text, so a word split by colour still counts.
    def find_matches(body)
      return [] if @find.empty?

      needle = @find.downcase
      body.each_index.select { |index| body[index].to_s.gsub(Ui::ANSI, "").downcase.include?(needle) }
    end

    # The scroll offset for a body, honouring a pending jump. The match lands a
    # couple of lines down rather than flush at the top, so it arrives with the
    # context above it.
    def detail_offset(count, visible, matches)
      if @find_jump && !matches.empty?
        @find_index %= matches.length
        @detail_scroll = [ matches[@find_index] - 2, 0 ].max
        @find_jump = false
      end

      # Remembered so the status line can report the find without needing the
      # body, which only the detail pane has.
      @find_total = matches.length
      detail_scroll_for(count, visible)
    end

    # Same jump, against the offset the one-long-page views scroll on.
    # The rows the current page last rendered. Only a scrolling page keeps this,
    # and only so a check can assert against the same list on screen.
    def remember_page(rows)
      @last_page_rows = rows
    end

    def content_offset(count, visible, matches, key = :content)
      if @find_jump && !matches.empty?
        @find_index %= matches.length
        set_scroll(key, [ matches[@find_index] - 2, 0 ].max)
        @find_jump = false
      end

      @find_total = matches.length
      content_scroll_for(count, visible, key)
    end

    def find_status
      return nil if @find.empty? || !findable?
      return "no line matches “#{@find}”" if @find_total.to_i.zero?

      "match #{(@find_index % @find_total) + 1} of #{@find_total} for “#{@find}” · n/N steps"
    end

    def handle_filter(key)
      case key
      # Enter accepts the filter — or, when it matched nothing, takes the term
      # to the search view instead. Widening is the natural next move from an
      # empty list, so it costs the same keystroke rather than a new one.
      when "\r", "\n" then return filter_found_nothing? ? escalate_to_search : (@filtering = false)
      when ESCAPE then (@filtering = false) || clear_filter
      when DELETE, "\b" then @filter.chop!
      when CTRL_C then @running = false
      else @filter << key if printable?(key)
      end
      reset_cursor
    end

    def handle_query(key)
      case key
      when CTRL_C then return @running = false
      # Esc stops editing and nothing else. It used to clear the query and then,
      # on a second press, leave for the bundles view — but wanting to stop
      # typing is not wanting to leave: the results are right there, and the
      # arrows should reach them without the view changing underfoot.
      when ESCAPE then return leave_field
      when CTRL_U then return @query.clear # clear the line, as in a shell
      # Enter means "search" while the query has unsearched edits, and "open the
      # selected hit" once it does not. No mode flag decides this — whether the
      # typed query and the searched one agree is the whole state, and the
      # footer says which of the two the next Enter will do.
      when "\r", "\n" then return commit_search ? nil : open_hit
      when DELETE, "\b" then @query.chop!
      when DOWN then return move(1)
      when UP then return move(-1)
      when TAB then return switch(:bundles)
      else @query << key if printable?(key)
      end
      @cursor = 0
      @scroll = 0
    end

    # A prompt takes either a line of text or a single confirming key.
    def handle_prompt(key)
      unless @prompt.free_text?
        pending = @prompt
        @prompt = nil
        @message = key.downcase == "y" ? resolve(pending) : "cancelled"
        return
      end

      case key
      when ESCAPE, CTRL_C then (@prompt = nil) || (@message = "cancelled")
      when "\r", "\n"
        pending = @prompt
        @prompt = nil
        @message = resolve(pending)
      when DELETE, "\b" then @prompt.buffer.chop!
      else @prompt.buffer << key if printable?(key)
      end
    end

    # A facet row narrows the graph; a concept row leaves for it. Selecting the
    # facet already in force clears it, so the same key toggles.
    def activate_graph_row
      entry = graph_selected
      return if entry.nil?

      case entry[:kind]
      when :facet
        if facet_active?(entry[:field], entry[:value])
          @graph_facet = nil
          @message = "cleared the facet"
        else
          @graph_facet = { field: entry[:field], value: entry[:value] }
          @message = "graph narrowed to #{entry[:field]} #{entry[:value]}"
        end
        @cursor = graph_selectable.first.to_i
      when :concept
        open_concept(entry[:id])
        @message = "opened #{entry[:id]}"
      end
    end

    # ── registry config ──────────────────────────────────────────────────────

    # Carry out an answered prompt. Every registry write goes through here.
    def resolve(pending)
      message =
        case pending.kind
        when :add then resolve_add(pending)
        when :rename then resolve_rename(pending)
        when :remove then workspace.remove(pending.subject)
        when :group then workspace.create_group(pending.buffer, workspace.scope)
        when :ungroup then resolve_ungroup(pending)
        end

      invalidate
      clamp_cursor
      message
    end

    # Both halves come from the prompt rather than from the cursor: a write that
    # re-read the pane would act on whatever is selected *now*, not on what the
    # question named.
    def resolve_ungroup(pending)
      slug, member = pending.subject.split(MEMBER_REF, 2)
      message = keeping_group_scoped(slug) { workspace.remove_from_group(slug, [ member ]) }
      @member_cursor = 0
      # Nothing left to point at, so step back out rather than hold focus in a pane
      # describing a group that is gone. #clamp_cursor catches the same case for a
      # group emptied any other way; this is the one that knows *which* group.
      #
      # Only from the members, though: the same question can now be asked from the
      # bundles pane, and answering it is no reason to move that reader elsewhere.
      @pane = :groups if @pane == :members && workspace.group(slug).nil?
      message
    end

    # A newly registered bundle is one the user just expressed interest in, so
    # it joins the scope and the cursor moves to it.
    def resolve_add(pending)
      before = workspace.entries.map(&:slug)
      message = workspace.add(pending.buffer)

      added = workspace.entries.find { |entry| !before.include?(entry.slug) }
      if added
        # A reload keeps the scope that was there before, which cannot mention a
        # bundle that did not exist yet — so put the new one in explicitly.
        workspace.toggle_scope(added.slug) unless workspace.scoped?(added.slug)
        focus(added.slug)
      end
      message
    end

    # Scope membership survives a rename. It is keyed by slug, but what the user
    # put in scope is the *bundle*, and its directory is what stays the same
    # across a rename — so reconcile on the directory, or the bundle silently
    # drops out of search the moment it is renamed.
    def resolve_rename(pending)
      dir = workspace.entry(pending.subject)&.dir
      message = workspace.rename(pending.subject, pending.buffer)

      renamed = workspace.entries.find { |entry| entry.dir == dir }
      if renamed
        workspace.toggle_scope(renamed.slug) unless workspace.scoped?(renamed.slug)
        focus(renamed.slug)
      end
      message
    end

    def ask(kind, label, free_text:, subject: nil)
      @prompt = Prompt.new(kind: kind, label: label, buffer: +"", subject: subject, free_text: free_text)
    end

    # Both span a group, because okf's own `rename` and `del` do: one rename
    # cascades across every member list, and one `del` cascade-drops the slug and
    # deletes any group it empties. Nothing here has to know that — it just has to
    # pass the slug the cursor is on rather than assuming it is a bundle's.
    # A bundle or group an okf registry *link* brought in is read-only: the file
    # that owns it is another registry, and okf refuses every config write against
    # one. The refusal belongs here, before the prompt — letting the ask through
    # makes a user type a new name and confirm it before learning it could never
    # land, and this view's own rule is that a key which stops working says so.
    # True when it refused, so a caller reads as `return if refused_linked?(…)`.
    def refused_linked?(subject, action)
      return false if subject.nil? || !subject.linked?

      @message = "#{action} @#{subject.slug} is read-only — it comes from the linked registry " \
                 "@#{subject.link}, so edit it there"
      true
    end

    def ask_rename
      subject = detailing_group? ? selected_group : selected_entry
      return if subject.nil?
      return if refused_linked?(subject, "renaming")

      ask(:rename, "rename @#{subject.slug} to:", free_text: true, subject: subject.slug)
    end

    def ask_remove
      subject = detailing_group? ? selected_group : selected_entry
      return if subject.nil?
      return if refused_linked?(subject, "removing")

      what = detailing_group? ? "group @#{subject.slug}" : "@#{subject.slug}"
      ask(:remove, "remove #{what} from the registry? (y/n)", free_text: false, subject: subject.slug)
    end

    # The slug the focused pane has selected — a group's when the groups or member
    # pane holds focus, a bundle's otherwise.
    def selected_slug
      detailing_group? ? selected_group&.slug : selected_entry&.slug
    end

    def set_default
      entry = selected_entry
      return if entry.nil?
      return if refused_linked?(entry, "defaulting to")

      @message = workspace.make_default(entry.slug)
      # Making a bundle the default moves it to the front, so the list reorders
      # under the cursor. Follow the bundle rather than the position, or the
      # selection silently lands on a different one.
      focus(entry.slug)
    end

    def toggle_scope
      entry = selected_entry
      return if entry.nil?

      workspace.toggle_scope(entry.slug)
      @search_hits_key = nil
    end

    def focus(slug)
      index = visible_entries.index { |entry| entry.slug == slug }
      @cursor = index if index
    end

    # ── switching bundles ────────────────────────────────────────────────────

    # Enter in the bundles view: which pane has focus decides what it means.
    def open_registry_row
      return open_bundle unless detailing_group?

      group = selected_group
      return if group.nil?

      @message = workspace.scope_group(group.slug)
      @search_hits_key = nil
    end

    # Enter on a bundle: make it the active one and go read it.
    def open_bundle
      entry = selected_entry
      return if entry.nil?

      unless entry.loaded?
        @message = "@#{entry.slug} cannot be read: #{entry.error}"
        return
      end

      activate(entry.slug)
      switch(:browse)
      @message = "@#{entry.slug} — #{model.concept_count} concepts"
    end

    def activate(slug)
      return false unless workspace.switch(slug)

      # The browse list and every scroll offset belong to the bundle that was
      # active; none of them mean anything against the new one.
      invalidate
      @filter = +""
      @graph_facet = nil
      @scroll = 0
      @detail_scroll = 0
      @content_scroll = 0
      @health_scroll = 0
      true
    end

    def invalidate
      @list_entries_key = nil
      @search_hits_key = nil
    end

    def printable?(key)
      key.length == 1 && key.ord >= 32 && key.ord < 127
    end

    # A filter that is looking for something and finding nothing — the moment
    # where offering the wider search is worth the line it costs.
    #
    # The registry counts too. A filter there looks through a dozen slugs and the
    # groups beside them, which is a narrow thing to be typing: a term matching none
    # of them is far more likely a question about what the bundles *say* than about
    # what one is called. Same key, same escalation.
    #
    # Both panes have to be empty, not just the focused one. A filter matching a
    # group and no bundle has found something — the first cut of this read only the
    # bundles pane, and swallowed the Enter that accepts such a filter.
    def filter_found_nothing?
      return false if @filter.empty?

      case @view
      when :browse then selectable_indices.empty?
      when :bundles then visible_entries.empty? && visible_groups.empty?
      else false
      end
    end

    # What the escalation is actually worth, which is not the same in both cases:
    # the browse filter matches titles, ids, types and tags in *this* bundle,
    # while search reads bodies too and spans every bundle. With one bundle open
    # the win is the full text; with several it is also the reach.
    def escalation_offer
      return nil unless filter_found_nothing?

      if workspace.entries.length > 1
        "search all #{workspace.entries.length} bundles"
      else
        "run a full-text search"
      end
    end

    # Carry the filter term over to the search view and run it. The scope widens
    # to every bundle, because "not in this one" is the whole reason to escalate
    # — and the header keeps saying so, so the widening is visible and undoable.
    def escalate_to_search
      term = @filter.dup
      return if term.empty?

      @filtering = false
      @filter = +""
      workspace.scope_all

      switch(:search)
      @query = term
      commit_search
      @message = "searched #{workspace.scope.length} bundles for “#{term}”"
    end

    # One key, three fields — whichever the focus makes it. The list pane and
    # the body pane are different things to look through, so `/` in each looks
    # through the one under the cursor rather than always the list.
    def start_typing
      return focus_field if @view == :search
      return start_find if findable?

      start_filter
    end

    # Is the cursor in a rendered document rather than a list? Two kinds, because
    # they scroll on different offsets: a concept body in the browse detail pane,
    # and the one-long-page views. Both are things to read, so both take a find.
    def reading_body?
      @view == :browse && @pane == :detail
    end

    def reading_page?
      CONTENT_VIEWS.include?(@view)
    end

    def findable?
      reading_body? || reading_page?
    end

    def start_find
      @finding = true
      @find = +""
      @find_index = 0
    end

    def start_filter
      return unless FILTERABLE_VIEWS.include?(@view)

      @filtering = true
      @filter = +""
    end

    # Esc undoes the narrowing in force, innermost first: a graph facet before
    # the filter, so one key backs out of both without leaving the view.
    def toggle_pane
      return cycle_bundles_pane if @view == :bundles

      @pane = @pane == :list ? :detail : :list
      # The two graph panes hold different lists, so a cursor carried across
      # would point at an arbitrary row — or at a heading, where it vanishes.
      @cursor = graph_selectable.first.to_i if @view == :graph
    end

    # bundles → groups → members → bundles, skipping what is not there: an empty
    # registry has no groups pane to reach, and a group with no members has no member
    # pane. Skipping rather than stopping, so Tab never appears to do nothing.
    def cycle_bundles_pane
      order = [ :bundles ]
      order << :groups unless visible_groups.empty?
      order << :members unless selected_group.nil? || group_members.empty?

      return @message = "nothing else to step into — no groups here yet" if order.length == 1

      @pane = order[(order.index(@pane) || 0) + 1] || order.first
      @member_cursor = 0 if @pane == :members
      @pane
    end

    def handle_escape
      return if @view == :search

      # Esc ends the innermost thing first, and a submitted find is still one of
      # them: Enter only releases the field, it does not end the find — the term
      # stays lit and n/N still step through it. Falling through to the list's
      # Esc from there resets the cursor and throws the reader back to the first
      # file, which is the one thing a find must never cost.
      if findable? && !@find.empty?
        clear_find
        return
      end

      if @view == :graph && @graph_facet
        @graph_facet = nil
        @cursor = graph_selectable.first.to_i
        @message = "cleared the facet"
        return
      end

      # Each pane is a layer, and all of them are innermore than the filter.
      if @view == :bundles && @pane == :members
        @pane = :groups
        @member_cursor = 0
        return
      end

      if @view == :bundles && @pane == :groups
        @pane = :bundles
        return
      end

      clear_filter
    end

    def clear_filter
      @filter = +""
      reset_cursor
    end

    def switch(target)
      # Entering search does *not* grab the field. A view that swallows every
      # printable key the moment you arrive turns "3" into query text and takes
      # the number keys away from navigation. Typing starts on `/` here, the
      # same key that starts the filter in browse.
      @search_focus = :results if target == :search
      @view = target
      # The filter described the view being left, not the one being entered.
      @filtering = false
      @filter = +""
      @graph_facet = nil
      reset_cursor
      @pane = target == :bundles ? :bundles : :list if %i[browse bundles].include?(target)
    end

    def reset_cursor
      @pane = :bundles if @view == :bundles
      @group_cursor = 0
      @member_cursor = 0
      @cursor = 0
      @scroll = 0
      @detail_scroll = 0
      @content_scroll = 0
      @health_scroll = 0
      @pane = :list if @view == :health
      @cursor = selectable_indices.first.to_i if @view == :browse
      @cursor = active_index if @view == :bundles
      @cursor = graph_selectable.first.to_i if @view == :graph
    end

    # Opening the bundles view puts the cursor on the bundle currently active,
    # which is the one the user is most likely reasoning about.
    def active_index
      visible_entries.index { |entry| entry.slug == workspace.active_slug } || 0
    end

    def items_length
      case @view
      when :bundles then visible_entries.length
      when :search then search_hits.length
      else 0
      end
    end

    def clamp_cursor
      count = items_length
      @cursor = count.zero? ? 0 : [ [ @cursor, count - 1 ].min, 0 ].max
      return unless @view == :bundles

      # The other two panes are rebuilt by the same writes, so they need clamping
      # for the same reason — a group removed under the cursor leaves it past the end.
      groups = visible_groups.length
      @group_cursor = groups.zero? ? 0 : [ [ @group_cursor, groups - 1 ].min, 0 ].max
      members = group_members.length
      @member_cursor = members.zero? ? 0 : [ [ @member_cursor, members - 1 ].min, 0 ].max
      # A pane with nothing in it cannot hold focus.
      @pane = :bundles if (@pane == :groups && groups.zero?) || (@pane == :members && members.zero?)
    end

    def step(position, delta, length)
      [ [ position + delta, 0 ].max, [ length - 1, 0 ].max ].min
    end

    # Move the selection, skipping the directory headings so the cursor only ever
    # lands on something selectable.
    def move(delta)
      # health, graph and help are one long page with nothing to select, so the
      # keys scroll them instead of moving a cursor.
      if CONTENT_VIEWS.include?(@view)
        key = content_scroll_key
        set_scroll(key, [ scroll_for(key) + delta, 0 ].max)
        return
      end

      if @view == :graph
        indices = graph_selectable
        return if indices.empty?

        position = indices.index(@cursor) || 0
        @cursor = indices[[ [ position + delta, 0 ].max, indices.length - 1 ].min]
        return
      end

      if @view == :bundles
        case @pane
        when :members then @member_cursor = step(@member_cursor, delta, group_members.length)
        when :groups then @group_cursor = step(@group_cursor, delta, visible_groups.length)
        else @cursor = step(@cursor, delta, visible_entries.length)
        end
        return
      end

      if @view == :browse && @pane == :detail
        @detail_scroll = [ @detail_scroll + delta, 0 ].max
        return
      end

      if @view == :search
        return if search_hits.empty?

        @cursor = [ [ @cursor + delta, 0 ].max, search_hits.length - 1 ].min
        return
      end

      indices = selectable_indices
      return if indices.empty?

      position = indices.index(@cursor) || 0
      position = [ [ position + delta, 0 ].max, indices.length - 1 ].min
      @cursor = indices[position]
      @detail_scroll = 0
    end

    def jump(where)
      if CONTENT_VIEWS.include?(@view)
        # `G` on a scrolling page: a deliberately large offset, clamped to the
        # real end by content_scroll_for once the view reports its length.
        set_scroll(content_scroll_key, where == :first ? 0 : 1_000_000)
        return
      end

      if @view == :graph
        indices = graph_selectable
        @cursor = (where == :first ? indices.first : indices.last).to_i
        return
      end

      if @view == :bundles
        length =
          case @pane
          when :members then group_members.length
          when :groups then visible_groups.length
          else visible_entries.length
          end
        last = [ length - 1, 0 ].max
        position = where == :first ? 0 : last

        case @pane
        when :members then @member_cursor = position
        when :groups then @group_cursor = position
        else @cursor = position
        end
        return
      end

      if @view == :search
        @cursor = where == :first ? 0 : [ items_length - 1, 0 ].max
        return
      end

      indices = selectable_indices
      return if indices.empty?

      @cursor = where == :first ? indices.first : indices.last
      @detail_scroll = 0
    end

    # Enter on a search hit. Across bundles the hit may belong to one that is not
    # active, so switching to it is part of opening — otherwise browse would
    # select an id in the wrong bundle, or in none.
    def open_hit
      hit = search_hits[@cursor]
      return if hit.nil?

      slug = hit[:slug] || workspace.active_slug
      switched = slug != workspace.active_slug
      activate(slug) if switched

      open_concept(hit[:id])
      @message = switched ? "opened @#{slug} — #{hit[:id]}" : "opened #{hit[:id]}"
    end

    # Land in browse with `id` selected and its body showing. Shared by opening
    # a search hit, following a concept out of the graph, and following a link
    # out of a document.
    def open_concept(id)
      push_trail
      @view = :browse
      @pane = :detail
      @filtering = false
      @filter = +""
      @detail_scroll = 0
      @list_entries_key = nil

      index = list_entries.index { |entry| entry[:kind] == :concept && entry[:row][:id] == id }
      @cursor = index || selectable_indices.first.to_i
      @scroll = 0
    end

    # The reserved-file twin of open_concept. An index.md is a bundle's way in
    # (§6), so a link that points at one has to land the same way a concept does.
    def open_reserved(path)
      push_trail
      @view = :browse
      @pane = :detail
      @filtering = false
      @filter = +""
      @detail_scroll = 0
      @list_entries_key = nil

      index = list_entries.index { |entry| entry[:kind] == :reserved && entry[:path] == path }
      @cursor = index || selectable_indices.first.to_i
      @scroll = 0
    end

    def reload
      workspace.reload
      @body_cache = {}
      # The trail holds ids and offsets from before the reload; a bundle that
      # changed on disk may no longer have them.
      @trail = []
      invalidate
      reset_cursor
      @message = "reloaded #{workspace.entries.length} bundles"
    rescue StandardError => e
      @message = "reload failed: #{e.message}"
    end
  end
end
