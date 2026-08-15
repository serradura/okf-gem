# frozen_string_literal: true

require "test_helper"

module Integration
  # Browse: the bundle in reading order, its bodies rendered, and finding within
  # one.
  class BrowseTest < OKF::TUI::TestCase
    test "the list is the bundle in reading order" do
      app = app_for(dirs: "okf-docs", keys: "2")

      kinds = app.list_entries.first(3).map { |entry| entry[:kind] }
      assert_equal %i[dir reserved reserved], kinds, "a directory should be followed by its reserved files"

      names = app.list_entries.select { |entry| entry[:kind] == :reserved }
                 .first(2).map { |entry| File.basename(entry[:path]) }
      assert_equal %w[index.md log.md], names, "index.md comes before log.md"

      assert_equal :reserved, app.selected_browse_entry[:kind], "reserved files should be selectable"
    end

    test "a reserved file reads without its frontmatter" do
      app = app_for(dirs: "okf-docs", keys: "2")
      entry = app.selected_browse_entry

      text = plain(app.rendered_reserved(entry[:path], 60).join("\n"))
      refute_includes text, "okf_version", "the frontmatter should be stripped for reading"
      refute_empty text.strip, "the index should have a body to read"
    end

    # tty-markdown wraps with the `strings` gem, which miscounts ANSI escapes and
    # raises IndexError from String#insert. It only bites when the output is
    # coloured — a pipe turns colour off, so an uncoloured render of the same
    # file is perfectly happy. That is why this forces colour on.
    test "every body renders, in colour, at every width" do
      with_colour do
        app = app_for(dirs: "okf-docs", keys: "2")

        app.model.rows.each do |row|
          [ 40, 66, 80, 120 ].each do |width|
            first = plain(app.rendered_body(row, width).first.to_s)
            refute_includes first, "could not render", "#{row[:id]} at width #{width}: #{first}"
          end
        end

        app.model.reserved.each do |entry|
          [ 40, 80 ].each do |width|
            first = plain(app.rendered_reserved(entry.path, width).first.to_s)
            refute_includes first, "could not render", "#{entry.path} at width #{width}: #{first}"
          end
        end
      end
    end

    test "/ filters the list, and finds inside the body" do
      app = app_for(dirs: "okf-docs", keys: "2/graph")
      assert_equal "graph", app.filter, "/ in the list pane should filter the list"

      app.handle(OKF::TUI::App::ESCAPE)
      app.handle(OKF::TUI::App::TAB)
      app.handle("/")
      "registry".each_char { |char| app.handle(char) }

      assert_empty app.filter, "/ in the body pane should not touch the list filter"
      assert_equal "registry", app.find, "the find should have collected the term"
    end

    test "the find scrolls the body to the match and steps through them" do
      app = app_for(dirs: "okf-docs", keys: "2")
      # Named, not counted: the list contains reserved files as well as concepts,
      # so a cursor arithmetic like <down><down><down> is a guess about ordering
      # rather than a statement about which concept is open.
      app.open_concept("overview")
      app.handle("/")
      "registry".each_char { |char| app.handle(char) }

      row = app.selected_row
      refute_nil row, "a concept should be selected"
      assert_equal "overview", row[:id]

      body = app.rendered_body(row, 58)
      matches = app.find_matches(body)
      refute_empty matches, "the fixture should contain the term"

      window = 10
      offset = app.detail_offset(body.length, window, matches)
      assert_includes (offset...(offset + window)), matches.first,
        "the match at line #{matches.first} is outside the window at #{offset}"

      next unless matches.length > 1

      app.handle("\r")
      app.handle("n")
      assert_operator app.detail_offset(body.length, window, matches), :!=, offset, "n did not step to the next match"
    end

    # Esc ends the find, and that is all it ends. Once Enter has submitted the
    # term the field no longer has focus, so Esc used to fall through to the
    # list's own Esc — which clears the filter and resets the cursor, throwing
    # the reader back to the first file. The file you were reading is the one
    # thing a find must never cost you.
    test "Esc after a submitted find keeps the file open" do
      app = app_for(dirs: "okf-docs", keys: "2")
      app.open_concept("overview")
      app.handle("/")
      "registry".each_char { |char| app.handle(char) }
      app.handle("\r")

      cursor = app.cursor
      app.handle(OKF::TUI::App::ESCAPE)

      assert_equal cursor, app.cursor, "Esc moved the cursor off the open file"
      assert_equal "overview", app.selected_row[:id], "Esc jumped away from the file being read"
      assert_empty app.find, "Esc should have ended the find"
    end

    test "a term that matches nothing finds nothing" do
      app = app_for(dirs: "okf-docs", keys: "2")
      app.open_concept("overview")
      app.handle("/")
      "zzzznope".each_char { |char| app.handle(char) }

      assert_empty app.find_matches(app.rendered_body(app.selected_row, 58))
    end

    private

    def with_colour
      previous = OKF::TUI::Ui::PASTEL
      OKF::TUI::Ui.send(:remove_const, :PASTEL)
      OKF::TUI::Ui.const_set(:PASTEL, Pastel.new(enabled: true))
      yield
    ensure
      OKF::TUI::Ui.send(:remove_const, :PASTEL)
      OKF::TUI::Ui.const_set(:PASTEL, previous)
    end
  end
end
