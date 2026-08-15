# frozen_string_literal: true

require "test_helper"

module Integration
  # The invariant the whole composition rests on: every painted row measures
  # exactly the terminal width.
  #
  # A composed terminal UI breaks the moment a row's display width disagrees
  # with String#length, which is exactly what colour causes — so this runs with
  # colour off *and* on. Pastel disables colour when stdout is not a terminal, so
  # an uncoloured capture exercises none of the ANSI-aware width, clipping and
  # wrapping code, which is where the mistakes are.
  class GeometryTest < OKF::TUI::TestCase
    SIZES = [ [ 80, 24 ], [ 100, 30 ], [ 132, 40 ], [ 200, 50 ] ].freeze

    # Every view, plus the states that only appear part-way through an
    # interaction: a prompt open, a facet chosen, a filter matching nothing.
    STATES = {
      "bundles" => "1",
      "bundles filtered" => "1/mal",
      "browse" => "2",
      "browse filtered" => "2/decay",
      "browse body" => "2<tab>",
      "browse find" => "2<tab>/registry",
      "browse links" => "2f",
      "browse links scrolled" => "2<down><down>fG",
      "browse followed a link" => "2f2",
      "search empty" => "3",
      "search typed" => "3/graph",
      "search done" => "3/graph<enter>",
      "search no scope" => "N3",
      "graph" => "4",
      "graph faceted" => "4<enter>",
      "graph concepts" => "4<tab>",
      "graph filtered" => "4/cli",
      "health" => "5",
      "health standing" => "5<tab>",
      "health find" => "5/conformance",
      "help" => "6",
      "help find" => "6/reload",
      "prompt add" => "1a/some/path",
      "prompt remove" => "1x"
    }.freeze

    test "every row is exactly the terminal width" do
      with_registry("okf-docs", "unhealthy", "malformed", "minimal", "wide") do |home|
        [ false, true ].each do |coloured|
          with_colour(coloured) do
            SIZES.each do |width, height|
              STATES.each do |label, keys|
                frame = render(home: home, keys: keys, size: [ width, height ])
                rows = frame.split("\n")

                refute_empty rows, "#{label} #{width}x#{height} colour=#{coloured}: painted nothing"
                assert_operator rows.length, :<=, height,
                  "#{label} #{width}x#{height} colour=#{coloured}: painted #{rows.length} rows"

                rows.each_with_index do |row, index|
                  measured = plain(row).length
                  next if measured.zero?

                  assert_equal width, measured,
                    "#{label} #{width}x#{height} colour=#{coloured}: row #{index} measured #{measured}"
                end
              end
            end
          end
        end
      end
    end

    # The rows this release added, which the sweep above cannot reach: the groups and
    # members panes need a registry that has groups, and the dirs facet and traffic
    # table need a bundle whose directories nest — `okf-docs`, the active bundle
    # above, is one level deep and is offered no dirs facet at all.
    #
    # Same invariant, and not a formality here. The bundles view is the only screen
    # that stacks *two* boxes down one column, so its left panes must sum to exactly
    # the body height as well as each measuring the full width — an off-by-one in
    # either box shears the pane beside it. The traffic table is the only
    # column-aligned block that pads to its own longest directory name, and the hub
    # rows compose four coloured segments each.
    NESTED_STATES = {
      "bundles pane" => "1",
      "groups pane" => "1<tab>",
      "members pane" => "1<tab><tab>",
      "members pane, last member" => "1<tab><tab>G",
      "groups filtered" => "1/nest",
      "groups filtered to none" => "1/unhealthy",
      "group remove prompt" => "1<tab><tab>-",
      "graph with dirs" => "5",
      "graph dir faceted" => "5G<enter>",
      "health hubs and traffic" => "6",
      "health find in traffic" => "6/cohesion"
    }.freeze

    test "the group and directory rows measure one terminal width too" do
      with_registry("nested", "conformant", "minimal") do |home, registry|
        registry.set_group("docs", %w[@nested @minimal])
        registry.set_group("everything", %w[@conformant @docs])

        [ false, true ].each do |coloured|
          with_colour(coloured) do
            SIZES.each do |width, height|
              NESTED_STATES.each do |label, keys|
                frame = render(home: home, keys: keys, size: [ width, height ])
                rows = frame.split("\n")

                refute_empty rows, "#{label} #{width}x#{height} colour=#{coloured}: painted nothing"

                rows.each_with_index do |row, index|
                  measured = Unicode::DisplayWidth.of(plain(row))
                  next if measured.zero?

                  assert_equal width, measured,
                    "#{label} #{width}x#{height} colour=#{coloured}: row #{index} measured #{measured} columns"
                end
              end
            end
          end
        end
      end
    end

    # The same invariant, on text where a character is not a column.
    #
    # Every other fixture is ASCII, where display width and String#length agree —
    # so the whole suite above passes whether the layout measures columns or
    # characters, and none of it can tell the two apart. CJK is two columns per
    # character, emoji two, a combining mark zero; only here does measuring the
    # wrong thing shear the frame.
    #
    # This is what stands behind the layout's dependency on unicode-display_width
    # arriving transitively through tty-box: if it ever stops arriving, `Ui.width`
    # falls back to counting characters and these rows go wrong.
    WIDE_STATES = {
      "browse" => "2",
      "browse body" => "2<tab>",
      "browse find" => "2<tab>/全角",
      "browse links" => "2f",
      "graph" => "5",
      "search done" => "4/日本語<enter>",
      "health" => "6"
    }.freeze

    test "a row of wide characters still measures one terminal width" do
      [ false, true ].each do |coloured|
        with_colour(coloured) do
          SIZES.each do |width, height|
            WIDE_STATES.each do |label, keys|
              frame = render(dirs: "wide", keys: keys, size: [ width, height ])
              rows = frame.split("\n")

              refute_empty rows, "#{label} #{width}x#{height} colour=#{coloured}: painted nothing"

              rows.each_with_index do |row, index|
                # Columns, not characters — measured here rather than through
                # Ui.width, so a regression in Ui cannot agree with its own test.
                measured = Unicode::DisplayWidth.of(plain(row))
                next if measured.zero?

                assert_equal width, measured,
                  "#{label} #{width}x#{height} colour=#{coloured}: row #{index} measured #{measured} columns"
              end
            end
          end
        end
      end
    end

    # The check that fails loudly if unicode-display_width stops arriving.
    #
    # It is deliberately not a rendering assertion: were the gem to vanish, both
    # the layout and the test above would fall back to counting characters and
    # would agree with each other, passing while the real terminal sheared.
    test "width is measured in display columns" do
      assert defined?(Unicode::DisplayWidth),
        "unicode-display_width is gone — it arrives through tty-box, and Ui.width silently falls back without it"

      assert_equal 6, OKF::TUI::Ui.width("日本語"), "CJK should measure two columns per character"
      assert_equal 2, OKF::TUI::Ui.width("🎨"), "an emoji should measure two columns"
      assert_equal 3, OKF::TUI::Ui.width("abc"), "ASCII should measure one column per character"
    end

    private

    # Pastel decides once, at load, whether colour is on. Swapping the instance
    # is the only way to exercise both paths in one process.
    def with_colour(enabled)
      previous = OKF::TUI::Ui::PASTEL
      OKF::TUI::Ui.send(:remove_const, :PASTEL)
      OKF::TUI::Ui.const_set(:PASTEL, Pastel.new(enabled: enabled))
      yield
    ensure
      OKF::TUI::Ui.send(:remove_const, :PASTEL)
      OKF::TUI::Ui.const_set(:PASTEL, previous)
    end
  end
end
