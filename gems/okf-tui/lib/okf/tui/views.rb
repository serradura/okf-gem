# frozen_string_literal: true

require "tty-markdown"
require_relative "ui"

module OKF::TUI
  # The screens. Each renders into a fixed rectangle and returns plain rows —
  # no view writes to the terminal itself, so the app can compose and repaint
  # them as one frame.
  module Views
    module_function

    TYPE_COLOURS = {
      "Overview" => :magenta,
      "Capability" => :cyan,
      "Component" => :green,
      "Constraint" => :yellow,
      "Format" => :blue
    }.freeze

    def type_colour(type)
      TYPE_COLOURS.fetch(type.to_s, :white)
    end

    # A bundle's standing, in the order that matters: conformance is a hard
    # failure (§9), lint is advisory. Asking forces a validate and a lint, which
    # Model memoizes, so a bundle is judged once however many places show it.
    def health_status(model)
      return :unknown if model.nil?
      return :error unless model.validation.valid?
      return :warn unless model.lint.warnings.empty?

      :ok
    end

    # One vocabulary for that standing, so the name in the header, the badge in
    # the footer, the row in the registry and the health tab cannot disagree.
    STATUS = {
      error: { fg: :red, bg: :on_red, mark: "✗" },
      warn: { fg: :yellow, bg: :on_yellow, mark: "▲" },
      ok: { fg: :green, bg: :on_green, mark: "✓" },
      unknown: { fg: :bright_black, bg: :on_bright_black, mark: "·" }
    }.freeze

    def status_style(model)
      STATUS.fetch(health_status(model))
    end

    # ── header ───────────────────────────────────────────────────────────────

    def header(app, width)
      model = app.model
      return workspace_header(app, width) if model.nil?

      health = model.validation.valid?
      warnings = model.lint.warnings.length

      title = Ui.line(width) do |row|
        row.add(" okf ", :black, :on_cyan, :bold)
        # The active bundle is reversed, not just bold: with several open, which
        # one the other views are about is the single most important thing on
        # screen, and it has to survive a glance after switching.
        row.add(" @#{model.name} ", :black, status_style(model)[:bg], :bold)
        row.add(" #{model.dir} ", :bright_black)
        unless app.workspace.entries.length < 2
          row.add(" · #{app.workspace.entries.length} bundles ", :cyan)
          row.add("· #{app.workspace.scope.length} in scope ", :bright_black)
        end
      end

      stats = Ui.line(width) do |row|
        row.add(" #{model.concept_count} concepts", :white)
        row.add("  #{model.edge_count} links", :white)
        row.add("  #{model.dirs.length} dirs", :white)
        row.space(2)
        if health
          row.add("✓ conformant", :green)
        else
          row.add("✗ #{model.validation.errors.length} errors", :red, :bold)
        end
        row.space(2)
        if warnings.zero?
          row.add("✓ lint clean", :green)
        else
          row.add("▲ #{warnings} lint warnings", :yellow)
        end

        # Reads are best-effort: a file the reader could not use is skipped
        # rather than aborting the bundle. Say so — a silently shorter list is
        # the one failure mode that reads as success.
        skipped = model.bundle.unparseable.length
        unless skipped.zero?
          row.space(2)
          row.add("⊘ #{skipped} unreadable", :red)
        end
      end

      [ title, stats, tabs(app, width) ]
    end

    # Shown when no bundle could be read — an empty registry, or one whose
    # directories have all gone. There is nothing to say about a bundle, so the
    # header talks about the workspace instead.
    def workspace_header(app, width)
      title = Ui.line(width) do |row|
        row.add(" okf ", :black, :on_cyan, :bold)
        row.add(" no bundle open ", :bright_white, :bold)
        row.add("· #{app.workspace.registry_path} ", :bright_black) if app.workspace.registry_backed?
      end

      stats = Ui.line(width) do |row|
        if app.workspace.empty?
          row.add(" the registry is empty — press a to register a bundle", :yellow)
        else
          row.add(" #{app.workspace.entries.length} bundles, none readable", :red)
        end
      end

      [ title, stats, tabs(app, width) ]
    end

    def tabs(app, width)
      Ui.line(width) do |row|
        row.space
        style = status_style(app.model)
        attention = %i[error warn].include?(health_status(app.model))

        app.class::TABS.each_with_index do |(key, label), index|
          # The health tab wears the verdict. Nothing else on a browse or graph
          # screen says the bundle is broken, and "go look at tab 5" is exactly
          # what a user needs told before they think to ask.
          flagged = key == :health && attention
          text = " #{index + 1} #{label}#{" #{style[:mark]}" if flagged} "

          if app.view == key
            row.add(text, :black, flagged ? style[:bg] : :on_bright_white, :bold)
          elsif flagged
            row.add(text, style[:fg], :bold)
          else
            row.add(text, :bright_black)
          end
          row.space
        end
      end
    end

    # Keys on the left, the active bundle pinned to the right. The header names
    # it too, but the footer is the line the eye is already on while working,
    # and after switching bundles "which one am I in" should never need a look
    # away from it.
    def footer(app, width)
      badge = active_badge(app)
      badge_width = Ui.width(badge)

      keys = Ui.line([ width - badge_width, 0 ].max) do |row|
        row.space
        app.status_hints.each do |key, meaning|
          row.add(" #{key} ", :black, :on_bright_black)
          row.add(" #{meaning}  ", :bright_black)
        end
      end

      keys + badge
    end

    def active_badge(app)
      model = app.model
      return "" if model.nil? || app.workspace.entries.length < 2

      Ui.line(Ui.width(" bundle @#{model.name} ")) do |row|
        row.add(" bundle ", :bright_black)
        row.add("@#{model.name} ", :black, status_style(model)[:bg], :bold)
      end
    end

    # ── bundles: the workspace — switch, scope, configure ───────────────────

    # Three panes: the registry's bundles and its groups stacked down the left, and
    # the detail of whichever of the two has focus on the right.
    #
    # The groups get a box rather than a heading inside the bundle list, because a
    # heading scrolls away — a registry of thirteen bundles put the groups below the
    # fold on a short terminal, which is no way to show a thing you are meant to
    # select. Boxed, they are always on screen, and Tab is the jump to them.
    def bundles(app, width, height)
      left_width = [ [ (width * 0.44).to_i, 38 ].max, width - 32 ].min
      groups_height = groups_box_height(app, height)

      left = Ui.box(
        bundle_list(app, left_width - 2, height - groups_height - 2),
        width: left_width, height: height - groups_height,
        title: bundles_title(app), active: app.bundles_pane?
      )

      # Vertical stacking is concatenation: both boxes are already rectangles of the
      # same width, which is the invariant Ui.box guarantees.
      left += Ui.box(
        group_list(app, left_width - 2, groups_height - 2),
        width: left_width, height: groups_height,
        title: groups_title(app), active: app.groups_pane?
      )

      right = Ui.box(
        bundle_detail(app, width - left_width - 2, height - 2),
        width: width - left_width, height: height,
        title: detail_title(app), active: app.member_pane?
      )

      Ui.hjoin(left, right)
    end

    # Sized to the groups it holds, so a registry with none gives its rows to the
    # bundles instead of framing an empty box — but never more than half the column,
    # since the bundles are the longer list and the one opened by default.
    def groups_box_height(app, height)
      wanted = app.visible_groups.length + 2
      floor = app.workspace.groups.empty? ? 3 : 4
      [ [ wanted, floor ].max, [ height / 2, 3 ].max ].min
    end

    def groups_title(app)
      count = app.workspace.groups.length
      return "groups" if count == app.visible_groups.length

      "groups #{app.visible_groups.length}/#{count}"
    end

    def detail_title(app)
      return "members of @#{app.selected_group.slug}" if app.member_pane?
      return "group" if app.detailing_group?

      "bundle"
    end

    def bundles_title(app)
      base = app.workspace.registry_backed? ? "registry" : "bundles (ad-hoc)"
      app.filter.empty? ? base : "#{base} /#{app.filter}"
    end

    def bundle_list(app, width, height)
      return no_bundles(app, width) if app.workspace.entries.empty?

      entries = app.visible_entries
      if entries.empty?
        rows = [ Ui.line(width) { |r| r.add("  no bundle matches “#{app.filter}”", :yellow) } ]
        # The way out, on the row under the dead end rather than in the footer
        # alone: this pane is wide, and the offer is the whole reason Enter still
        # does something here.
        if app.filter_found_nothing?
          rows << Ui.blank_line(width)
          rows << Ui.line(width) do |r|
            r.add("  ↵ searches every bundle for “#{app.filter}” instead", :bright_black)
          end
        end
        return rows
      end

      # One pad across both left panes, so the two lists line up: a group is
      # addressed by an @slug exactly as a bundle is, and staggered columns would
      # suggest otherwise.
      pad = registry_pad(app)
      window = app.window(entries.length, height)

      entries[window, height].to_a.each_with_index.map do |entry, offset|
        bundle_row(app, entry, window + offset == app.cursor && app.bundles_pane?, width, pad)
      end
    end

    def registry_pad(app)
      (app.visible_entries.map { |entry| entry.slug.to_s.length } +
        app.visible_groups.map { |group| group.slug.to_s.length }).max.to_i
    end

    def group_list(app, width, height)
      groups = app.visible_groups
      if groups.empty?
        return [ Ui.line(width) do |r|
          r.add(app.workspace.registry_backed? ? "  none — c names the scoped bundles as one" : "  none",
            :bright_black)
        end ]
      end

      pad = registry_pad(app)
      # Its own window: a pane with its own cursor needs its own scroll, or a long
      # group list would be clipped rather than scrolled.
      window = app.group_window(groups.length, height)

      groups[window, height].to_a.each_with_index.map do |group, offset|
        group_row(app, group, window + offset == app.group_cursor, width, pad)
      end
    end

    # A group row reads as what it is for: a named search scope. It carries no
    # active dot and no default flag — a group is never the bundle the other views
    # are about — and the ◉ is filled only when the scope in force *is* this
    # group's set, which is the one thing a glance wants to know.
    def group_row(app, group, selected, width, pad)
      Ui.line(width) do |row|
        # The cursor shows even when this pane has no focus, dimmed. `+` in the
        # bundles pane acts on *this* row, and a key that reaches across panes needs
        # a row the reader can see it pointing at — the footer used to spell the slug
        # out instead, which claimed a selection nothing on screen agreed with.
        focused = app.groups_pane?
        row.add(selected ? "▸ " : "  ", focused ? :cyan : :bright_black, *(focused ? [ :bold ] : []))
        in_force = app.group_in_scope?(group)
        row.add(in_force ? "◉ " : "○ ", in_force ? :cyan : :bright_black)
        row.add("  ", :bright_black) # where a bundle carries its active dot
        row.add("@#{group.slug}".ljust(pad + 2), group.cyclic? ? :red : :blue, :bold)

        if group.cyclic?
          row.add(" unresolvable — a cycle in the registry", :red)
        else
          row.add(group.size.to_s.rjust(4), :bright_black)
          row.add(group.size == 1 ? " bundle" : " bundles", :bright_black)
        end
      end
    end

    def no_bundles(_app, width)
      [
        Ui.line(width) { |r| r.add("  nothing registered", :yellow) },
        Ui.blank_line(width),
        Ui.line(width) { |r| r.add("  press a to register a bundle directory", :bright_black) }
      ]
    end

    def bundle_row(app, entry, selected, width, pad)
      scoped = app.scoped?(entry.slug)
      active = entry.slug == app.workspace.active_slug

      Ui.line(width) do |row|
        row.add(selected ? "▸ " : "  ", :cyan, :bold)
        # Two different states, so two different marks: ◉ is "a search covers
        # this", ● is "this is the bundle the other views are about".
        row.add(scoped ? "◉ " : "○ ", scoped ? :cyan : :bright_black)
        row.add(active ? "● " : "  ", :green, :bold)
        # Red for a non-conformant bundle, amber for lint warnings — the point
        # of the list is spotting which one needs attention.
        slug_colour = entry.loaded? ? status_style(entry.model)[:fg] : :red
        row.add("@#{entry.slug}".ljust(pad + 2), slug_colour, :bold)

        if entry.loaded?
          row.add(entry.concepts.to_s.rjust(4), :bright_black)
          row.add(entry.concepts == 1 ? " concept" : " concepts", :bright_black)
        else
          row.add(" #{entry.error}", :red)
        end

        row.add("  default", :magenta) if entry.default?
      end
    end

    def bundle_detail(app, width, height)
      group = bundle_detail_subject(app)
      return group_detail(app, group, width) if group

      entry = app.selected_entry
      return [ Ui.line(width) { |r| r.add("  nothing selected", :bright_black) } ] if entry.nil?

      bundle_entry_detail(app, entry, width, height)
    end

    def bundle_detail_subject(app)
      app.detailing_group? ? app.selected_group : nil
    end

    # What a group is: the members as the registry file records them, and the
    # bundles they resolve to. Both, because for a nested group they differ — a
    # member can itself be a group — and the resolved list is what a search would
    # actually cover.
    def group_detail(app, group, width)
      rows = []
      rows << Ui.line(width) do |r|
        r.add("@#{group.slug}", group.cyclic? ? :red : :blue, :bold)
        r.add("  group", :bright_black)
        r.add("  in scope", :cyan, :bold) if app.group_in_scope?(group)
      end
      rows << Ui.blank_line(width)

      if group.cyclic?
        rows << Ui.line(width) { |r| r.add("  ⚠ its members form a cycle, so okf cannot resolve it", :red) }
        rows << Ui.blank_line(width)
        rows << Ui.line(width) { |r| r.add("  edit #{app.workspace.registry.path} to break it", :bright_black) }
        return rows
      end

      rows << pair(width, "members", group.members.length)
      rows << pair(width, "bundles", group.size)
      rows << Ui.blank_line(width)

      rows.concat(group_member_rows(app, group, width))
      rows << Ui.blank_line(width)
      rows << Ui.blank_line(width)
      if app.member_pane?
        rows << Ui.line(width) { |r| r.add("  - removes the member under the cursor (asks first)", :bright_black) }
        rows << Ui.line(width) { |r| r.add("  Esc steps back to the groups", :bright_black) }
      else
        rows << Ui.line(width) { |r| r.add("  ↵ scopes the search to it · n renames · x deletes", :bright_black) }
        rows << Ui.line(width) { |r| r.add("  Tab steps into the members, where - removes one", :bright_black) }
        rows << Ui.line(width) do |r|
          r.add("  + in the bundles pane adds the bundle under that cursor", :bright_black)
        end
      end
      rows
    end

    # A member is named as the registry names it, with what it turned out to be
    # beside it: a bundle's concept count, or "group" for a nested one. A member
    # naming nothing registered is called out rather than dropped — that is a
    # registry to fix, and a silently shorter list is how it stays unfixed.
    def group_member_rows(app, group, width)
      focused = app.member_pane?

      group.members.each_with_index.map do |member, index|
        entry = app.workspace.entry(member)
        nested = app.workspace.group(member)
        on = focused && index == app.member_cursor

        Ui.line(width) do |r|
          r.add(on ? "  ▸ " : "    ", :cyan, :bold)
          r.add("@#{member}", entry || nested ? :bright_white : :red, *(on ? [ :bold ] : []))
          if entry
            r.add("  #{entry.concepts} #{entry.concepts == 1 ? "concept" : "concepts"}", :bright_black) if entry.loaded?
            r.add("  #{entry.error}", :red) unless entry.loaded?
          elsif nested
            r.add("  group of #{nested.size}", :blue)
          else
            r.add("  not registered", :red)
          end
        end
      end
    end

    def bundle_entry_detail(app, entry, width, _height)
      rows = []
      rows << Ui.line(width) do |r|
        r.add("@#{entry.slug}", entry.loaded? ? status_style(entry.model)[:fg] : :red, :bold)
        r.add("  active", :green, :bold) if entry.slug == app.workspace.active_slug
        r.add("  default", :magenta) if entry.default?
      end
      rows << Ui.line(width) { |r| r.add(entry.dir.to_s, :bright_black) }
      rows.concat(membership_rows(app, entry, width))
      rows << Ui.blank_line(width)

      unless entry.loaded?
        rows << Ui.line(width) { |r| r.add("  ⚠ #{entry.error}", :red) }
        rows << Ui.blank_line(width)
        rows << Ui.line(width) { |r| r.add("  x removes it from the registry", :bright_black) }
        return rows
      end

      model = entry.model
      rows << pair(width, "concepts", model.concept_count)
      rows << pair(width, "links", model.edge_count)
      rows << pair(width, "dirs", model.dirs.length)
      rows << pair(width, "orphans", model.orphan_ids.length, model.orphan_ids.empty? ? :green : :yellow)
      rows << Ui.blank_line(width)

      rows << Ui.line(width) do |r|
        r.add("  conformance  ", :bright_black)
        if model.validation.valid?
          version = model.okf_version
          r.add(version.to_s.empty? ? "✓ conformant" : "✓ legal OKF v#{version}", :green)
        else
          r.add("✗ #{model.validation.errors.length} errors", :red, :bold)
        end
      end
      rows << Ui.line(width) do |r|
        r.add("  curation     ", :bright_black)
        warnings = model.lint.warnings.length
        if warnings.zero?
          r.add("✓ lint clean", :green)
        else
          r.add("▲ #{warnings} warnings", :yellow)
        end
      end

      skipped = model.bundle.unparseable.length
      unless skipped.zero?
        rows << Ui.line(width) do |r|
          r.add("  files        ", :bright_black)
          r.add("⊘ #{skipped} unreadable", :red)
        end
      end

      rows << Ui.blank_line(width)
      rows << Ui.line(width) { |r| r.add("  ↵ open it · space toggles search scope", :bright_black) }

      # Only the offer, and only when there is one to make: a bundle already in the
      # group says so on its own row and in the `in @…` line above.
      group = app.selected_group
      if group && !app.member_group(entry.slug)
        rows << Ui.line(width) { |r| r.add("  + puts it in @#{group.slug}", :bright_black) }
      end

      rows
    end

    # Every group that names this bundle, not only the one selected below: the row
    # can show one membership, and a bundle can have several. This is the line that
    # answers "did that + land" when the group being edited is scrolled out of the
    # groups pane.
    def membership_rows(app, entry, width)
      groups = app.workspace.groups.select { |group| group.members.include?(entry.slug) }
      return [] if groups.empty?

      [ Ui.line(width) do |r|
        r.add("in ", :bright_black)
        groups.each { |group| r.add("@#{group.slug} ", :blue) }
      end ]
    end

    def pair(width, label, value, colour = :bright_white)
      Ui.line(width) do |r|
        r.add("  #{label.ljust(12)} ", :bright_black)
        r.add(value.to_s, colour, :bold)
      end
    end

    # ── browse: concept list + detail ────────────────────────────────────────

    def browse(app, width, height)
      left_width = [ [ (width * 0.38).to_i, 34 ].max, width - 30 ].min
      right_width = width - left_width

      left = Ui.box(
        concept_list(app, left_width - 2, height - 2),
        width: left_width, height: height,
        title: browse_list_title(app), active: app.pane == :list
      )

      right = Ui.box(
        concept_detail(app, right_width - 2, height - 2),
        width: right_width, height: height,
        title: "detail", active: app.pane == :detail
      )

      Ui.hjoin(left, right)
    end

    def browse_list_title(app)
      app.filter.empty? ? "concepts" : "concepts /#{app.filter}"
    end

    # The list, grouped under directory headings, windowed around the cursor.
    def concept_list(app, width, height)
      entries = app.list_entries
      return empty_list(app, width) if entries.empty?

      window = app.window(entries.length, height)

      entries[window, height].to_a.each_with_index.map do |entry, offset|
        index = window + offset
        if entry[:kind] == :dir
          Ui.line(width) do |row|
            row.space
            row.add(entry[:label].upcase, :bright_black, :bold)
            row.add(" (#{entry[:count]})", :bright_black)
          end
        elsif entry[:kind] == :reserved
          reserved_row(entry, index == app.cursor, width)
        else
          concept_row(app, entry[:row], index == app.cursor, width)
        end
      end
    end

    # An empty list is a dead end unless it says where to go next. A filter that
    # found nothing is usually not "it does not exist" but "it is not in the
    # part of this bundle a filter can see", so the way out is offered here.
    def empty_list(app, width)
      return [ Ui.line(width) { |r| r.add("  no concepts here", :bright_black) } ] unless app.filter_found_nothing?

      # Short here — the pane is narrow. The offer itself goes in the detail
      # pane, which is wide and otherwise saying "nothing selected".
      [ Ui.line(width) { |r| r.add("  no matches in this bundle", :yellow) } ]
    end

    # index.md and log.md are structure, not concepts, so they read differently
    # in the list: a file name rather than a title, and no type dot.
    def reserved_row(entry, selected, width)
      name = File.basename(entry[:path])

      Ui.line(width) do |row|
        row.add(selected ? "▸ " : "  ", :cyan, :bold)
        row.add("▪ ", :bright_black)
        row.add(name, selected ? :bright_white : :bright_black, :bold)
        row.add(name == "index.md" ? "  the way in" : "  the log", :bright_black)
      end
    end

    def concept_row(app, item, selected, width)
      Ui.line(width) do |row|
        row.add(selected ? "▸ " : "  ", :cyan, :bold)
        row.add("● ", type_colour(item[:type]))

        label = item[:title].to_s.empty? ? item[:id] : item[:title]
        if selected
          row.add(label, :bright_white, :bold)
        else
          row.add(label, :white)
        end

        findings = app.model.findings_for(item)
        row.add(" ▲#{findings.length}", :yellow) unless findings.empty?
      end
    end

    # The right-hand pane: frontmatter, then the body rendered as markdown.
    def concept_detail(app, width, height)
      return escalation_panel(app, width) if app.filter_found_nothing?

      entry = app.selected_browse_entry
      return reserved_detail(app, entry, width, height) if entry && entry[:kind] == :reserved

      item = app.selected_row
      return [ Ui.line(width) { |r| r.add("  nothing selected", :bright_black) } ] if item.nil?

      rows = []
      rows << Ui.line(width) { |r| r.add(item[:title].to_s, :bright_white, :bold) }
      rows << Ui.line(width) do |r|
        r.add(item[:type].to_s, type_colour(item[:type]), :bold)
        r.add("  #{item[:path]}", :bright_black)
      end

      unless item[:description].to_s.empty?
        rows << Ui.blank_line(width)
        wrap(item[:description], width - 2).each do |text|
          rows << Ui.line(width) { |r| r.add("  #{text}", :white) }
        end
      end

      rows << Ui.blank_line(width)
      rows << Ui.line(width) do |r|
        r.add("  links ", :bright_black)
        r.add("→#{item[:links_out]} ", :green)
        r.add("←#{item[:links_in]}", :blue)
        unless Array(item[:tags]).empty?
          r.add("   tags ", :bright_black)
          r.add(Array(item[:tags]).join(" · "), :cyan)
        end
      end

      rows.concat(provenance_rows(item, width))

      findings = app.model.findings_for(item)
      unless findings.empty?
        rows << Ui.blank_line(width)
        findings.first(4).each do |finding|
          rows << Ui.line(width) do |r|
            r.add("  ▲ ", :yellow)
            r.add("#{finding[:check]} ", :yellow, :bold)
            r.add(finding[:message].to_s, :white)
          end
        end
      end

      rows << Ui.blank_line(width)
      rows << Ui.line(width) { |r| r.add("─" * width, :bright_black) }

      rows.concat(document_block(app, width, height - rows.length) { app.rendered_body(item, width - 2) })
      rows
    end

    # §5's provenance families, on the rows that declared them.
    #
    # Everything here is conditional on the concept having *said* something, which
    # is the v0.1 half of okf's own rule: v0.2 only added optional keys, so a
    # bundle that adopted none of them must not read as deficient — it reads as it
    # always did, with no rows at all. §13.1 does the rest: a v0.1 `timestamp:`
    # arrives as `generated_at` with no actor invented for it, so the "updated"
    # line an unmigrated bundle has always shown still shows.
    #
    # The trust tier is the one that needs a rule rather than a presence check,
    # because §5.3 *derives* `unverified` for every concept that verified nothing.
    # Printing that would paint a provenance verdict onto a document that never
    # made one. `Model.shows_trust?` is okf's predicate, shared with its server and
    # its graph page, and the facet in the graph view gates on the same call.
    def provenance_rows(item, width)
      rows = []

      unless item[:generated_at].to_s.empty?
        rows << Ui.line(width) do |r|
          r.add("  updated ", :bright_black)
          r.add(item[:generated_at].to_s, :white)
          # No actor means §13.1 lifted this from a v0.1 `timestamp`, which
          # recorded none. Naming one would be the false provenance §5 prevents.
          unless item[:generated_by].to_s.empty?
            r.add(" by ", :bright_black)
            r.add(item[:generated_by].to_s, :white)
          end
        end
      end

      marks = []
      marks << [ item[:trust].to_s, trust_colour(item[:trust]) ] if Model.shows_trust?(item)
      # The producer's own spelling, and only when it is not the §5.4 default:
      # `stable` is what an undeclared status already means, so a row saying it
      # carries no information the absence did not.
      unless item[:status].to_s.empty? || OKF::Concept.effective_status(item[:status]) == "stable"
        marks << [ item[:status].to_s, :yellow ]
      end
      marks << [ "expires #{item[:stale_after]}", :bright_black ] unless item[:stale_after].to_s.empty?
      marks << [ "#{item[:sources]} sources", :bright_black ] if item[:sources].to_i.positive?

      unless marks.empty?
        rows << Ui.line(width) do |r|
          r.add("  ", :bright_black)
          marks.each_with_index do |(text, colour), index|
            r.add("  ", :bright_black) if index.positive?
            r.add(text, colour)
          end
        end
      end

      rows
    end

    # §5.3's three tiers, warm for the one a human signed off. Unverified stays
    # neutral: where it is shown at all the concept declared §5 and simply has no
    # verification yet, which is a state rather than a fault.
    def trust_colour(trust)
      case trust.to_s
      when "human-reviewed" then :green
      when "machine-confirmed" then :cyan
      else :bright_black
      end
    end

    # A filter that found nothing is usually not "it does not exist" but "it is
    # not in the part of this bundle a filter can see" — the filter reads
    # metadata only, and only this bundle. So the dead end offers the way on.
    def escalation_panel(app, width)
      rows = []
      rows << Ui.line(width) { |r| r.add("nothing matched “#{app.filter}” here", :yellow, :bold) }
      rows << Ui.blank_line(width)

      wrap("The filter reads titles, ids, types and tags, in this bundle only.", width - 4).each do |text|
        rows << Ui.line(width) { |r| r.add("  #{text}", :bright_black) }
      end

      rows << Ui.blank_line(width)
      rows << Ui.line(width) do |r|
        r.add("  ↵  ", :black, :on_cyan, :bold)
        r.add(" #{app.escalation_offer}", :cyan, :bold)
      end
      rows << Ui.blank_line(width)

      wrap("That reads every concept body too, ranked, and merges the bundles into one result list.", width - 4).each do |text|
        rows << Ui.line(width) { |r| r.add("  #{text}", :bright_black) }
      end

      rows
    end

    # A reserved file has no frontmatter to summarise — it is all body.
    def reserved_detail(app, entry, width, height)
      rows = []
      rows << Ui.line(width) { |r| r.add(File.basename(entry[:path]), :bright_white, :bold) }
      rows << Ui.line(width) do |r|
        r.add(entry[:path], :bright_black)
        r.add(File.basename(entry[:path]) == "index.md" ? "  ·  progressive disclosure (§6)" : "  ·  the bundle log", :bright_black)
      end
      rows << Ui.blank_line(width)
      rows << Ui.line(width) { |r| r.add("─" * width, :bright_black) }

      rows.concat(document_block(app, width, height - rows.length) { app.rendered_reserved(entry[:path], width - 2) })
      rows
    end

    # The detail pane's document area — the body, or the link picker in its
    # place. Replacing rather than overlaying keeps the header above it, and
    # means Esc puts the body back exactly where it was: nothing here touches
    # the detail scroll. The body is yielded rather than passed so the picker
    # does not pay tty-markdown to render a page it is covering.
    def document_block(app, width, visible)
      return links_block(app, width, visible) if app.following?

      body_block(app, yield, width, visible)
    end

    # Where this document points. The list comes from okf — the same extraction
    # the graph builds edges with — so these rows are a value a check can assert
    # on, rather than a pattern matched against rendered markdown.
    def links_block(app, width, visible)
      links = app.follow_links

      rows = []
      rows << Ui.line(width) do |r|
        r.add("  links in this document ", :bright_white, :bold)
        r.add("(#{links.length})", :bright_black)
      end
      rows << Ui.blank_line(width)

      room = [ visible - rows.length, 1 ].max
      body = links.each_with_index.map { |link, index| link_row(app, link, index, width) }
      offset = app.follow_window(body.length, room)
      rows.concat(body[offset, room].to_a)
      rows
    end

    # A link reads as whatever is at the far end of it, not as the path it was
    # written with: a concept by its title and type colour, a nested index by its
    # area, and a target with nothing behind it as exactly that — not-yet-written
    # knowledge is what a broken cross-link usually is.
    def link_row(app, link, index, width)
      selected = index == app.follow_cursor

      Ui.line(width) do |r|
        r.add(selected ? "▸ " : "  ", :cyan, :bold)
        r.add(index < 9 ? "#{index + 1} " : "  ", :bright_black)

        case link[:kind]
        when :concept
          r.add("● ", type_colour(link[:type]))
          r.add(link[:label], selected ? :bright_white : :white, :bold)
          r.add("  #{link[:target]}", :bright_black)
        when :reserved
          r.add("▪ ", :bright_black)
          r.add(link[:label], selected ? :bright_white : :bright_black, :bold)
          r.add("  #{link[:target]}", :bright_black)
        else
          r.add("○ ", :yellow)
          r.add(link[:target], :yellow)
          r.add("  not written yet", :bright_black)
        end
      end
    end

    # The scrolling window over a rendered document, with the find matches
    # marked. The body is already coloured by tty-markdown, so these rows bypass
    # Line and are squared off by fit_block on the way into the box.
    def body_block(app, body, _width, visible)
      matches = app.find_matches(body)
      offset = app.detail_offset(body.length, visible, matches)

      body[offset, visible].to_a.each_with_index.map do |text, index|
        line = offset + index
        next "  #{text}" unless matches.include?(line)

        # The mark goes in the gutter the other rows leave empty, so a hit is
        # visible without touching the rendered markdown itself.
        current = matches[app.find_index % [ matches.length, 1 ].max] == line
        Ui.pastel.decorate(current ? "▶ " : "· ", current ? :black : :yellow, *(current ? %i[on_yellow bold] : [])) + text
      end
    end

    def wrap(text, limit)
      words = text.to_s.split(/\s+/)
      lines = []
      current = +""
      words.each do |word|
        candidate = current.empty? ? word : "#{current} #{word}"
        if Ui.width(candidate) > limit
          lines << current unless current.empty?
          current = word.dup
        else
          current = candidate
        end
      end
      lines << current unless current.empty?
      lines
    end

    # ── search ───────────────────────────────────────────────────────────────

    def search(app, outer_width, height)
      width = outer_width - 2
      rows = []
      editing = app.editing_query?

      rows << Ui.line(width) do |r|
        r.add("  search ", :bright_black)
        r.add(app.query.empty? && !editing ? "(no query)" : app.query, :bright_white, :bold)
        # The caret is the focus indicator: it is only in the field while the
        # field is where the typing goes.
        r.add(editing ? "▏" : " ", :cyan, :bold)

        # Until Enter, whatever is listed below answers the *previous* query.
        # Saying so is the difference between "not searched yet" and a wrong
        # answer sitting under a query it does not belong to.
        if app.search_pending?
          r.add("  ↵ to search", :black, :on_yellow, :bold)
        elsif !editing
          r.add(app.query.empty? ? "  /  to search" : "  /  to edit", :bright_black)
        end
      end
      rows << Ui.line(width) do |r|
        r.add("  mode ", :bright_black)
        r.add(app.search_mode_label, :cyan, :bold)
        r.add(" (e) ", :bright_black)
        r.add(" #{app.search_mode_note}", :bright_black)
      end
      rows << Ui.line(width) do |r|
        error = app.workspace.search_error
        next r.add("  #{error}", :yellow) if error

        r.add("  one corpus over every scoped bundle, so the scores compare", :bright_black)
      end
      rows << Ui.blank_line(width)

      scope = app.workspace.scope
      hits = app.search_hits

      if scope.empty?
        rows << Ui.line(width) { |r| r.add("  no bundles in scope — press 1, then space to pick some", :yellow) }
      elsif app.searched.empty?
        # Nothing has been searched yet, so there are no results to describe —
        # and saying "no matches" here would blame the query for an answer that
        # was never asked for.
        rows << Ui.line(width) do |r|
          if app.query.empty?
            r.add("  press / to type a query — titles, ids, tags, types, descriptions, bodies", :bright_black)
          else
            r.add("  press ↵ to search for “#{app.query}”", :yellow)
          end
        end
      elsif hits.empty?
        rows << Ui.line(width) { |r| r.add("  no matches for “#{app.searched}”", :yellow) }
      else
        rows << Ui.line(width) do |r|
          r.add("  #{count(hits.length, "match", "matches")} across #{count(scope.length, "bundle")}", :bright_black)
          # While the field is being edited the list still answers the old query.
          r.add("  for “#{app.searched}”", :yellow) if app.search_pending?
        end
        rows << Ui.blank_line(width)

        visible = height - rows.length - 2
        window = app.window(hits.length, visible / 3)
        hits[window, [ visible / 3, 1 ].max].to_a.each_with_index do |hit, offset|
          rows.concat(search_hit(app, hit, window + offset == app.cursor, width))
        end
      end

      Ui.box(rows, width: outer_width, height: height, title: search_title(app), active: true)
    end

    # The scope, named the way the equivalent CLI invocation would name it.
    def search_title(app)
      scope = app.workspace.scope
      return "search — nothing in scope" if scope.empty?
      return "search" if app.workspace.entries.length < 2

      label = scope.length == app.workspace.entries.length ? "@all" : scope.map { |slug| "@#{slug}" }.join(" ")
      "search #{label}"
    end

    def count(number, singular, plural = nil)
      "#{number} #{number == 1 ? singular : plural || "#{singular}s"}"
    end

    def search_hit(app, hit, selected, inner)
      head = Ui.line(inner) do |r|
        r.add(selected ? "▸ " : "  ", :cyan, :bold)
        # The slug only earns its space when a search can span bundles.
        r.add("@#{hit[:slug]} ", :cyan) if hit[:slug] && app.workspace.entries.length > 1
        r.add(hit[:title].to_s, selected ? :bright_white : :white, :bold)
        r.add("  #{hit[:type]}", type_colour(hit[:type]))
        r.add("  #{format("%.2f", hit[:score])}", :bright_black)
      end

      meta = Ui.line(inner) do |r|
        r.add("    #{hit[:id]}", :bright_black)
        r.add("  matched: ", :bright_black)
        r.add(Array(hit[:matched]).join(", "), :magenta)
      end

      snippet = Ui.line(inner) do |r|
        r.add("    #{hit[:snippet]}", :bright_black)
      end

      [ head, meta, snippet ]
    end

    # ── health: validate + lint ──────────────────────────────────────────────

    # Two panes: what is wrong on the left, how it stands on the right.
    #
    # One page mixed them, and the findings are the unbounded half — a bundle with
    # two hundred lint findings pushed the dir traffic and the stats off the bottom,
    # which is exactly the bundle whose structure you opened this view to look at.
    # The summary is bounded by construction, so given a pane of its own it can
    # never be pushed away, and the two scroll apart.
    #
    # The right pane carries verdicts and numbers, never a path: every row in it is
    # short by design, which is what lets it keep a fixed width. The findings that
    # go with those verdicts are on the left, where the columns are.
    HEALTH_SUMMARY_WIDTH = 56

    # Below this the two panes would each be too narrow for the paths a finding is
    # *about*, so the same Tab shows one at a time instead. Splitting anyway and
    # letting both clip would be the layout lying about fitting.
    HEALTH_SPLIT_WIDTH = 112

    def health(app, outer_width, height)
      return health_page(app, outer_width, height) if outer_width < HEALTH_SPLIT_WIDTH

      right_width = HEALTH_SUMMARY_WIDTH
      left_width = outer_width - right_width
      findings = app.pane != :detail

      left = scrollable(app, health_findings(app.model, left_width - 2), left_width, height,
        "findings", scroll: :content, focused: findings)
      right = scrollable(app, health_summary(app.model, right_width - 2), right_width, height,
        "standing", scroll: :health, focused: !findings)

      Ui.hjoin(left, right)
    end

    # Narrow: one pane at a time, chosen by the same Tab that puts them side by side
    # when there is room. The title says which, since only one is on screen.
    def health_page(app, outer_width, height)
      if app.pane == :detail
        scrollable(app, health_summary(app.model, outer_width - 2), outer_width, height,
          "health · standing", scroll: :health)
      else
        scrollable(app, health_findings(app.model, outer_width - 2), outer_width, height,
          "health · findings")
      end
    end

    # The left pane: every row that names a file. Conformance errors lead, because
    # a bundle that is not legal has a different first job than one that is merely
    # untidy.
    def health_findings(model, width)
      rows = []

      unless model.validation.valid?
        rows << section(width, "conformance — spec §9", :red)
        model.validation.errors.first(8).each do |error|
          rows << detail_line(width, "✗", "#{error[:path]} — #{error[:message]}", :red)
        end
        rows << Ui.blank_line(width)
      end

      model.validation.warnings.first(5).each do |warning|
        rows << detail_line(width, "▲", "#{warning[:path]} — #{warning[:message]}", :yellow)
      end
      rows << Ui.blank_line(width) unless model.validation.warnings.empty?

      rows << section(width, "curation — lint", model.lint.warnings.empty? ? :green : :yellow)
      if model.lint.findings.empty?
        rows << detail_line(width, "✓", "no curation findings", :green)
      else
        rows.concat(lint_block(model, width))
      end

      rows.concat(hubs_block(model, width))
      rows
    end

    # The right pane: the verdicts, then the shape. It says how many errors there
    # are rather than listing them — the list is beside it, and a path in a column
    # this narrow would be clipped into a different path.
    def health_summary(model, width)
      valid = model.validation.valid?
      rows = [ section(width, "conformance — spec §9", valid ? :green : :red) ]
      rows <<
        if valid
          detail_line(width, "✓", conformance_line(model), :green)
        else
          detail_line(width, "✗", "#{count(model.validation.errors.length, "error")} — in the findings", :red)
        end

      rows << Ui.blank_line(width)
      warnings = model.lint.warnings.length
      rows << section(width, "curation — lint", warnings.zero? ? :green : :yellow)
      if model.lint.findings.empty?
        rows << detail_line(width, "✓", "no curation findings", :green)
      else
        info = model.lint.findings.length - warnings
        note = [ warnings.zero? ? nil : count(warnings, "warning"),
                 info.zero? ? nil : "#{info} info" ].compact.join(" · ")
        rows << detail_line(width, warnings.zero? ? "ℹ" : "▲", "#{note} — in the findings",
          warnings.zero? ? :blue : :yellow)
      end
      rows.concat(skipped_block(model, width))

      rows.concat(posture_block(model, width))
      rows.concat(traffic_block(model, width))
      rows.concat(stats_block(model, width))
      rows
    end

    # What the bundle declares itself to be (§12), not what this screen assumes.
    # It said "legal OKF v0.1" for a release — about every bundle equally,
    # including one that had migrated — which is the whole failure mode of reading
    # a fact off a literal instead of off okf. §12 lets a bundle declare nothing,
    # and there the honest answer names no version: `validate` backs conformance,
    # never a version claim.
    def conformance_line(model)
      version = model.okf_version
      version.to_s.empty? ? "a conformant bundle" : "a legal OKF v#{version} bundle"
    end

    # A verdict is only as good as the checks behind it, so a check that did not
    # run is said out loud. §5.5's freshness pair is clock-gated and the pure
    # library runs neither unless handed a clock — and "✓ lint clean" over a check
    # that never ran is worse than no verdict at all. okf's own CLI confesses the
    # same thing in the same words.
    def skipped_block(model, width)
      skipped = model.skipped_checks
      return [] if skipped.empty?

      [ detail_line(width, "·", "#{skipped.join(", ")} not run — no clock supplied", :bright_black) ]
    end

    # The bundle's trust and status posture — the two distributions okf's own lint
    # prints on its summary line, and the two `stats_block` cannot show because it
    # keeps scalars only.
    #
    # Each is shown only where the bundle has something to say, on the same rule
    # the graph page's facets use: status needs one *declared* value, since a
    # column of `stable` is what an undeclared status already means; trust needs
    # one tier okf is willing to claim, or every v0.1 bundle would wear a row
    # reading only "unverified" about a family it never adopted.
    def posture_block(model, width)
      claims_trust = model.rows.any? { |row| Model.shows_trust?(row) }
      declared_status = model.rows.any? { |row| !row[:status].to_s.empty? }
      return [] unless claims_trust || declared_status

      rows = [ Ui.blank_line(width), section(width, "posture — §5 trust and status", :blue) ]
      # okf's own numbers, unedited — this is the line `okf lint` prints. Only the
      # *gate* is this view's, and it is a gate on the bundle rather than on the
      # tiers: once one concept claims a tier the whole distribution is the answer,
      # including the unverified ones it is measured against.
      rows << posture_row(width, "trust", model.trust_posture) if claims_trust
      rows << posture_row(width, "status", model.status_posture) if declared_status
      rows
    end

    # Tiers and statuses the bundle has none of are dropped. okf's lint line
    # prints all three tiers because a terminal line is as wide as it needs to be;
    # this pane holds a fixed width, and it holds it because every row in it is
    # short *by construction*. `trust unverified 31  machine-confirmed 0
    # human-reviewed 0` is not, and clipped to fit it read "human-rev…".
    def posture_row(width, label, counts)
      counts = posture_counts(counts)

      Ui.line(width) do |r|
        r.add("  #{label} ", :bright_black)
        counts.each_with_index do |(value, count), index|
          r.add("  ", :bright_black) if index.positive?
          r.add(value.to_s, :white)
          r.add(" #{count}", :bright_white, :bold)
        end
      end
    end

    def posture_counts(counts)
      counts.reject { |_, count| count.to_i.zero? }
    end

    # Findings grouped by check, warnings before info. Each group lists a few
    # examples and says how many it withheld, so a long list stays readable
    # without the page pretending it showed everything.
    def lint_block(model, width)
      grouped = model.lint.findings.group_by { |finding| finding[:check] }
      ordered = grouped.sort_by do |check, list|
        [ list.first[:severity] == :warn ? 0 : 1, -list.length, check.to_s ]
      end

      # Examples shown per check. The page scrolls, so this is about keeping one
      # noisy check from burying the others, not about fitting the screen.
      examples = 3
      rows = []

      ordered.each do |check, list|
        warn = list.first[:severity] == :warn
        rows << Ui.line(width) do |r|
          r.add("  #{warn ? "▲" : "ℹ"} ", warn ? :yellow : :blue)
          r.add(check.to_s, :bright_white, :bold)
          r.add("  ×#{list.length}", :bright_black)
        end

        list.first(examples).each do |finding|
          rows << Ui.line(width) do |r|
            r.add("      #{finding[:path]}", :bright_black)
            r.add("  #{finding[:message]}", :white)
          end
        end

        hidden = list.length - examples
        rows << Ui.line(width) { |r| r.add("      … #{hidden} more", :bright_black) } if hidden.positive?
      end

      rows
    end

    # Hubs, and whether each is well homed — okf's `graph --hubs`.
    #
    # The number alone is already in the graph view; what earns a place here is the
    # *judgement*, which needs the inbound breakdown beside it. A hub drawing most
    # of its links from outside its own top-level dir is flagged, and when a single
    # foreign dir dominates, that dir is named — it is the better home the concept
    # already has.
    HUBS_SHOWN = 6

    def hubs_block(model, width)
      hubs = model.hubs
      rows = [ Ui.blank_line(width), section(width, "hubs — where their inbound links come from", :blue) ]

      if hubs.empty?
        rows << detail_line(width, "·", "nothing is linked to yet", :bright_black)
        return rows
      end

      hubs.first(HUBS_SHOWN).each { |hub| rows << hub_row(hub, width) }
      hidden = hubs.length - HUBS_SHOWN
      rows << Ui.line(width) { |r| r.add("      … #{hidden} more", :bright_black) } if hidden.positive?
      rows
    end

    def hub_row(hub, width)
      home = hub[:top_dir].to_s
      foreign = hub[:by_top_dir].reject { |dir, _| dir.to_s == home }
      foreign_total = foreign.values.reduce(0, :+)
      away = foreign_total * 2 > hub[:inbound]

      Ui.line(width) do |r|
        r.add(away ? "  ▲ " : "  · ", away ? :yellow : :bright_black)
        r.add(hub[:id].to_s, :bright_white, :bold)
        r.add("  ←#{hub[:inbound]}", :blue)
        r.add("  in #{home}", :bright_black)
        # Named only when one foreign dir carries the majority on its own: that is
        # the case where okf says the hub has already named its better home. A
        # scattered inbound majority is a different finding, and saying "move it
        # to X" on the strength of a plurality would be the wrong advice.
        top_dir, top_count = foreign.max_by { |_, count| count }
        if away && top_count && top_count * 2 > hub[:inbound]
          r.add("  → mostly from #{top_dir}", :yellow)
        elsif away
          r.add("  → #{foreign_total} of #{hub[:inbound]} from elsewhere", :yellow)
        end
      end
    end

    # Cohesion versus coupling, one row per directory — okf's `graph --traffic`.
    #
    # This is the measurement okf added because the refine playbook's directory
    # judgements ("does this directory prune? a concern, or a container?") had
    # nothing at their own grain: `--hubs` measures concepts. Near-zero cohesion
    # under heavy inbound is a shared vocabulary doing its job; heavy outbound with
    # nothing coming back is a projection wearing a directory. Which of those it is
    # remains the reader's call — the row supplies the evidence, not the verdict.
    #
    # Model#dir_traffic has already sorted by cohesion ascending, so the directories
    # with a case to answer are the ones on screen first.
    TRAFFIC_SHOWN = 8

    def traffic_block(model, width)
      traffic = model.dir_traffic
      rows = [ Ui.blank_line(width), section(width, "dir traffic — internal share of each dir's links", :yellow) ]

      # One directory is the whole bundle: there is no traffic *between*
      # directories to weigh, so every row would be a tautology.
      if traffic.length < 2
        rows << detail_line(width, "·", "one directory — nothing to weigh it against", :bright_black)
        return rows
      end

      rows << Ui.line(width) do |r|
        r.add("      #{"dir".ljust(traffic_pad(traffic))}", :bright_black)
        r.add("  internal   out    in  cohesion", :bright_black)
      end
      traffic.first(TRAFFIC_SHOWN).each { |row| rows << traffic_row(row, width, traffic_pad(traffic)) }
      hidden = traffic.length - TRAFFIC_SHOWN
      rows << Ui.line(width) { |r| r.add("      … #{hidden} more", :bright_black) } if hidden.positive?
      rows.concat(arc_rows(model, width))
      rows
    end

    # Which directories actually talk to which. The table above says how much of a
    # directory's traffic stays home; these say where the rest of it goes, which is
    # the other half of `graph --traffic` and the half that names a pair.
    ARCS_SHOWN = 6

    def arc_rows(model, width)
      arcs, cut, total = model.dir_arcs
      return [] if arcs.empty?

      rows = [ Ui.blank_line(width) ]
      rows << Ui.line(width) do |r|
        r.add("      #{arcs.length} of #{total} arcs", :bright_black)
        # Say the cut, because the list is narrowed and a silently shortened list
        # reads as a complete one. It is fitted to this bundle by okf, not fixed.
        r.add(" at weight #{cut} or more", :bright_black)
      end

      pad = arcs.first(ARCS_SHOWN).map { |arc| Ui.width(traffic_label(dir: arc[:source])) }.max.to_i
      arcs.first(ARCS_SHOWN).each do |arc|
        rows << Ui.line(width) do |r|
          r.add("      #{traffic_label(dir: arc[:source]).ljust(pad)}", :white)
          r.add(" → ", :bright_black)
          r.add(traffic_label(dir: arc[:target]), :white)
          r.add("  ×#{arc[:weight]}", :bright_black)
        end
      end

      hidden = arcs.length - ARCS_SHOWN
      rows << Ui.line(width) { |r| r.add("      … #{hidden} more", :bright_black) } if hidden.positive?
      rows
    end

    def traffic_pad(traffic)
      traffic.map { |row| Ui.width(traffic_label(row)) }.max.to_i
    end

    # `(root)` for a reader, as everywhere else — `.` is the stored spelling.
    def traffic_label(row)
      row[:dir] == "." ? "(root)" : row[:dir].to_s
    end

    def traffic_row(row, width, pad)
      cohesion = row[:cohesion]

      Ui.line(width) do |r|
        r.add("      #{traffic_label(row).ljust(pad)}", :white)
        r.add("  #{row[:internal].to_s.rjust(8)}", :bright_black)
        r.add("  #{row[:out].to_s.rjust(4)}", :bright_black)
        r.add("  #{row[:in].to_s.rjust(4)}", :bright_black)
        # A dash, not 0% — a directory with no traffic at all has not earned a
        # number, which is the distinction okf's own view is careful to draw.
        if cohesion.nil?
          r.add("         —", :bright_black)
        else
          r.add("      #{"#{cohesion}%".rjust(4)}", cohesion_colour(cohesion))
        end
      end
    end

    # Low cohesion is the thing worth looking at, so it is the thing that is
    # coloured. Not a verdict — okf is explicit that near-zero cohesion can be a
    # shared vocabulary doing exactly its job — which is why this is a shade of
    # attention rather than the ▲ the lint findings wear.
    def cohesion_colour(cohesion)
      return :yellow if cohesion < 25
      return :white if cohesion < 60

      :green
    end

    def stats_block(model, width)
      # Scalars only. The linter also reports structured stats (`hubs`, `tags`)
      # whose #to_s is a Ruby literal — the graph view already draws those
      # properly, so printing them here as inspect output would be noise.
      scalars = model.lint.stats.reject { |_, value| value.is_a?(Enumerable) }

      rows = [ Ui.blank_line(width), section(width, "stats", :cyan) ]
      scalars.each_slice(4) do |slice|
        rows << Ui.line(width) do |r|
          slice.each do |key, value|
            r.add("  #{key} ", :bright_black)
            r.add(value.to_s, :bright_white, :bold)
          end
        end
      end
      rows
    end

    # Draw `rows` as a box showing only the slice the scroll offset selects, and
    # say so in the title when there is more than fits. A pane that silently
    # shows the first N rows of a longer list reads as a complete one.
    def scrollable(app, rows, outer_width, height, title, offset: nil, scroll: :content, focused: true)
      inner_height = height - 2
      # `/` looks through the pane with focus. Matching both halves of a split view
      # would put the find cursor on a page the keys are not moving.
      live = offset.nil? && focused
      matches = live ? app.find_matches(rows) : []
      app.remember_page(rows) if live
      # A shared offset is passed in; otherwise the page owns its own, and a pending
      # find jump moves it.
      offset ||= app.content_offset(rows.length, inner_height, matches, scroll)

      # Clamp to this pane's own end. A shared offset (the graph view's two
      # panes) can otherwise run past the shorter one and blank it.
      offset = [ [ offset, [ rows.length - inner_height, 0 ].max ].min, 0 ].max
      visible = (rows[offset, inner_height] || []).each_with_index.map do |row, index|
        line = offset + index
        next row unless matches.include?(line)

        # Marked in the gutter rather than restyled: these rows are already
        # coloured. The marker costs a column, so one of the rows own trailing
        # pad spaces pays for it — clipping the tail instead would ellipsise a
        # line that actually fits.
        current = matches[app.find_index % [ matches.length, 1 ].max] == line
        mark = Ui.pastel.decorate(current ? "▶" : "·", current ? :black : :yellow, *(current ? %i[on_yellow bold] : []))
        mark + row.sub(/ \z/, "")
      end

      title = "#{title} · “#{app.find}”" unless app.find.to_s.empty? || matches.empty?

      label =
        if rows.length > inner_height
          last = [ offset + inner_height, rows.length ].min
          "#{title} #{offset + 1}-#{last}/#{rows.length}"
        else
          title
        end

      Ui.box(visible, width: outer_width, height: height, title: label, active: focused)
    end

    def section(width, label, colour)
      Ui.line(width) do |r|
        r.add(" ▌", colour, :bold)
        r.add(" #{label} ", :bright_white, :bold)
      end
    end

    def detail_line(width, glyph, text, colour)
      Ui.line(width) do |r|
        r.add("  #{glyph} ", colour)
        r.add(text, :white)
      end
    end

    # ── graph: shape of the knowledge graph ──────────────────────────────────

    def graph(app, width, height)
      half = width / 2

      left = graph_pane(app, app.graph_facet_entries, half, height, "distribution", :list)
      right = graph_pane(app, app.graph_concept_entries, width - half, height, "connectivity", :detail)

      Ui.hjoin(left, right)
    end

    # One pane of the graph: its rows, windowed around the cursor when it is the
    # focused one. Only the focused pane carries a cursor, so the two lists never
    # both look selected.
    def graph_pane(app, entries, width, height, title, pane)
      focused = app.pane == pane
      inner_height = height - 2
      inner_width = width - 2

      window = focused ? app.window(entries.length, inner_height) : 0
      rows = entries[window, inner_height].to_a.each_with_index.map do |entry, offset|
        graph_row(app, entry, inner_width, focused && window + offset == app.cursor)
      end

      Ui.box(rows, width: width, height: height, title: graph_title(app, title, entries, window, inner_height), active: focused)
    end

    def graph_title(app, title, entries, window, inner_height)
      title = "#{title} /#{app.filter}" unless app.filter.empty?
      title = "#{title} · #{app.graph_facet[:value]}" if app.graph_facet
      return title if entries.length <= inner_height

      "#{title} #{window + 1}-#{[ window + inner_height, entries.length ].min}/#{entries.length}"
    end

    # A row is a heading, a blank, a note, or something selectable — a facet to
    # narrow by or a concept to go read.
    def graph_row(app, entry, width, selected)
      case entry[:kind]
      when :blank then Ui.blank_line(width)
      when :heading then section(width, entry[:label], entry[:colour])
      when :note then detail_line(width, "✓", entry[:label], entry[:colour])
      when :facet then facet_row(app, entry, width, selected)
      else concept_bar(entry, width, selected)
      end
    end

    FACET_COLOURS = { type: :cyan, tag: :magenta, dir: :yellow }.freeze

    # `.` is how okf stores the bundle root and `(root)` is what it calls it for a
    # reader — the same pair `okf dirs` prints. The stored spelling stays in
    # `entry[:value]`, which is what the facet matches on.
    def facet_label(entry)
      value = entry[:value].to_s
      entry[:field] == :dir && value == "." ? "(root)" : value
    end

    def facet_row(app, entry, width, selected)
      on = app.facet_active?(entry[:field], entry[:value])
      colour = FACET_COLOURS.fetch(entry[:field], :magenta)

      bar_row(width, selected,
        label: facet_label(entry),
        count: entry[:count],
        peak: entry[:peak],
        pad: entry[:pad],
        colour: colour,
        mark: on ? "◉ " : "  ",
        label_colour: if on
                        colour
                      else
                        (selected ? :bright_white : :white)
                      end)
    end

    def concept_bar(entry, width, selected)
      bar_row(width, selected,
        label: entry[:id].to_s,
        count: entry[:count],
        peak: entry[:peak],
        pad: entry[:pad],
        colour: entry[:colour] || :blue,
        mark: "",
        label_colour: selected ? :bright_white : :white)
    end

    # A selectable row that still draws its bar. Making the graph navigable is
    # no reason to stop it being a graph — the bar is what makes a distribution
    # readable at a glance, and the cursor rides in front of it.
    def bar_row(width, selected, label:, count:, peak:, pad:, colour:, mark:, label_colour:)
      Ui.line(width) do |r|
        r.add(selected ? "▸ " : "  ", :cyan, :bold)
        r.add(mark, colour, :bold) unless mark.empty?

        r.add(label.ljust(pad.to_i), label_colour, :bold)
        r.add(" #{count.to_s.rjust(3)} ", :bright_black)

        # Whatever is left after the label and the count belongs to the bar.
        room = [ width - 4 - mark.length - pad.to_i - 5, 2 ].max
        top = [ peak.to_i, 1 ].max
        blocks = count.to_i.zero? ? 0 : [ (count.to_f / top * room).round, 1 ].max
        r.add("█" * blocks, colour)
      end
    end

    # The filter narrows every list on the page by label — a type, a tag, or a
    # concept id. Counts are the ones already computed, so a filtered bar still
    # says how many there are in the bundle, not how many survived the filter.
    def narrow_rows(rows, filter)
      return rows if filter.to_s.empty?

      needle = filter.downcase
      rows.select { |row| row[:id].to_s.downcase.include?(needle) }
    end

    def narrow(pairs, filter)
      return pairs if filter.to_s.empty?

      needle = filter.downcase
      pairs.select { |label, _| label.to_s.downcase.include?(needle) }
    end

    # ── help ─────────────────────────────────────────────────────────────────

    KEYS = [
      [ "Navigation", [
        [ "j / ↓", "next item" ],
        [ "k / ↑", "previous item" ],
        [ "g / G", "first / last item" ],
        [ "Ctrl-d / Ctrl-u", "half page down / up" ]
      ] ],
      [ "Views", [
        [ "1 … 6", "bundles · browse · search · graph · health · help" ],
        [ "Tab", "switch pane — browse's body, a group's members, the graph's lists," ],
        [ "", "health's findings and its standing" ],
        [ "J / K", "scroll the concept body" ]
      ] ],
      [ "Bundles (view 1)", [
        [ "Enter", "open that bundle — browse/health/graph follow it" ],
        [ "Enter", "on a group: scope the search to exactly its bundles" ],
        [ "space", "put it in, or out of, the search scope" ],
        [ "A / N", "scope all bundles / none — N is how you start a fresh selection" ],
        [ "G", "jump to the end of the list, where the groups are" ],
        [ "d", "make it the registry default" ],
        [ "a", "register a directory — the one bundles key the footer leaves to here" ],
        [ "n", "rename its slug — or a group's" ],
        [ "x", "remove it from the registry (asks first) — or delete a group" ],
        [ "c", "name the bundles now in scope as a group" ]
      ] ],
      [ "Groups (view 1)", [
        [ "Tab", "cycle the three panes: bundles → groups → members" ],
        [ "Esc", "step back out, one pane at a time" ],
        [ "Enter", "on a group: make a search cover exactly its bundles" ],
        [ "+", "in the bundles pane: the bundle under the cursor joins the group" ],
        [ "", "selected below — the detail pane lists what a bundle is in" ],
        [ "-", "in the members: remove the one under the cursor (asks first)" ],
        [ "", "removing the last member deletes the group, and the question says so" ],
        [ "n / x", "rename or delete a group; okf cascades through every member list" ],
        [ "c", "name the bundles now in scope as a new group" ]
      ] ],
      [ "Graph (view 4)", [
        [ "↑ ↓", "move over the facets, or the concepts" ],
        [ "Tab", "switch between the two lists" ],
        [ "Enter", "on a type, tag or dir: narrow the whole graph by it" ],
        [ "", "a dir reaches everything beneath it, as okf's --dir does" ],
        [ "Enter", "on a concept: open it in browse" ],
        [ "Esc", "clear the facet" ]
      ] ],
      [ "Following links (view 2)", [
        [ "f", "list what this document links to — a concept body, an index, the log" ],
        [ "1 … 9", "follow that link straight away" ],
        [ "Enter", "follow the one under the cursor" ],
        [ "Esc", "put the body back, where you left it" ],
        [ "Backspace", "back to wherever you jumped from — search hits and the graph too" ]
      ] ],
      [ "Finding things", [
        [ "/", "look through what has focus — the list, or the open document" ],
        [ "n / N", "next / previous match, while reading a body" ],
        [ "Enter", "when a filter matches nothing: search every bundle for it" ],
        [ "", "the registry filter offers the same escalation, from view 1" ],
        [ "s", "jump to search — it covers every scoped bundle" ],
        [ "e", "how the query is asked: fuzzy · text · regexp (Esc out of the field first)" ],
        [ "", "fuzzy ranks and forgives typos; text is raw substring, so it finds" ],
        [ "", "$OKF_HOME and `minifts`, which the index tokenizer splits apart" ],
        [ "Enter", "search; press it again to open the selected hit" ],
        [ "↑ ↓", "pick a hit — works while typing or after Esc" ],
        [ "Esc", "stop editing and stay put; drops an unsearched query" ],
        [ "/ or i", "start or resume editing the query" ],
        [ "Ctrl-u", "clear the query while editing" ]
      ] ],
      [ "Session", [
        [ "r", "reload every bundle from disk" ],
        [ "q q", "quit — the second press confirms, so a stray q costs nothing" ]
      ] ]
    ].freeze

    def help(app, outer_width, height)
      width = outer_width - 2
      rows = []
      rows << Ui.blank_line(width)
      KEYS.each do |group, bindings|
        rows << section(width, group, :cyan)
        bindings.each do |key, meaning|
          rows << Ui.line(width) do |r|
            r.add("      #{key.rjust(16)}", :bright_white, :bold)
            r.add("   #{meaning}", :white)
          end
        end
        rows << Ui.blank_line(width)
      end

      rows << section(width, "about", :magenta)
      [
        "A terminal UI over the okf gem, built with the TTY toolkit.",
        "It reads bundles through OKF::Bundle::Reader and derives every",
        "answer from the pure core — the same catalog, graph, validator,",
        "linter and MiniFTS search the CLI and the graph server use.",
        "",
        "A search spans every bundle in scope through one shared index,",
        "which is what makes the scores comparable between them — the",
        "same thing `okf search @all` does.",
        "",
        "Nothing here is authored twice: the TUI is one more shell."
      ].each do |text|
        rows << Ui.line(width) { |r| r.add("      #{text}", :bright_black) }
      end

      scrollable(app, rows, outer_width, height, "help")
    end
  end
end
