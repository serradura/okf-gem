# frozen_string_literal: true

require "pastel"
require "tty-box"

begin
  require "unicode/display_width"
rescue LoadError # rubocop:disable Lint/SuppressedException
end

module OKF::TUI
  # Layout primitives. Everything the views draw goes through here, because the
  # one thing that breaks a composed terminal UI is a line whose *display* width
  # disagrees with its String#length — which is exactly what happens the moment
  # colour is involved. So width is always measured on the ANSI-stripped text,
  # and colour is only ever applied to a segment already clipped to fit.
  module Ui
    ANSI = /\e\[[0-9;]*[a-zA-Z]/.freeze

    # Pastel disables colour when stdout is not a terminal, which is right for a
    # pipe but means a captured frame exercises none of the ANSI paths the
    # layout depends on. FORCE_COLOR=1 turns it back on so those can be checked.
    PASTEL = Pastel.new(enabled: ENV["FORCE_COLOR"] ? true : nil)

    module_function

    def pastel
      PASTEL
    end

    # Display columns a string occupies, ignoring colour escapes.
    def width(string)
      plain = string.to_s.gsub(ANSI, "")

      if defined?(Unicode::DisplayWidth)
        Unicode::DisplayWidth.of(plain)
      else
        plain.length
      end
    end

    # Clip a *plain* string to at most `limit` columns, ellipsizing when it does
    # not fit. Never called on coloured text — see Line.
    def clip(string, limit)
      string = string.to_s.tr("\t", " ").delete("\n")
      return "" if limit <= 0
      return string if width(string) <= limit
      return "…" if limit == 1

      out = +""
      string.each_char do |char|
        break if width(out) + width(char) > limit - 1

        out << char
      end
      "#{out}…"
    end

    # Clip a string that already carries colour. Escape sequences cost no
    # columns and are copied through, so the result keeps its styling and is cut
    # only on visible characters — a plain clip would slice an escape in half and
    # leave the rest of the screen wearing whatever colour it opened.
    def clip_ansi(string, limit)
      return clip(string, limit) unless string.match?(ANSI)

      out = +""
      spent = 0
      scanner = string.to_s.scan(/\e\[[0-9;]*[a-zA-Z]|./m)

      scanner.each do |token|
        if token.start_with?("\e")
          out << token
          next
        end

        break if spent + width(token) > limit

        out << token
        spent += width(token)
      end

      reset_if_styled(out)
    end

    # Box-drawing glyphs, i.e. a rendered table or code fence. Re-flowing one of
    # those destroys the alignment that carries its meaning, so such a row is
    # clipped instead of wrapped.
    TABULAR = /[┌┬┐├┼┤└┴┘─│┃━╭╮╰╯]/.freeze

    # Word-wrap a line that may already carry colour, into rows of at most
    # `limit` columns. tty-markdown keeps the source's own hard line breaks
    # rather than reflowing to the width it is given, so bodies authored at 80
    # columns have to be re-wrapped here to fit a narrower pane.
    #
    # Escapes cost no columns and ride along with the word they precede; the
    # style open at a break is re-opened on the next row so a colour spanning a
    # wrap does not stop halfway.
    def wrap_ansi(string, limit)
      line = string.to_s.chomp
      return [ clip_ansi(line, limit) ] if limit <= 0 || line.match?(TABULAR)
      return [ line ] if width(line) <= limit

      indent = " " * [ line[/\A */].length, [ limit - 8, 0 ].max ].min
      rows = []
      current = +""
      spent = 0
      style = nil

      words(line).each do |word|
        visible = width(word[:text])
        next if visible.zero? && word[:escapes].empty?

        if spent.positive? && spent + 1 + visible > limit
          rows << reset_if_styled(current)
          current = +"#{indent}#{style}"
          spent = width(indent)
        elsif spent > width(indent)
          current << " "
          spent += 1
        end

        style = word[:escapes].last if word[:escapes].any? { |code| code != "\e[0m" }
        current << word[:escapes].join << word[:text]
        spent += visible
      end

      rows << reset_if_styled(current) unless current.strip.empty?
      rows.empty? ? [ "" ] : rows
    end

    # Split a line into words, each carrying the escape sequences that preceded
    # it so styling survives the re-flow.
    def words(line)
      out = []
      pending = []
      current = +""

      line.scan(/\e\[[0-9;]*[a-zA-Z]|\s+|[^\s\e]+/) do |token|
        if token.start_with?("\e")
          current.empty? ? pending << token : (out << { escapes: pending, text: current }; pending = [ token ]; current = +"")
        elsif token.strip.empty?
          unless current.empty?
            out << { escapes: pending, text: current }
            pending = []
            current = +""
          end
        else
          current << token
        end
      end

      out << { escapes: pending, text: current } unless current.empty?
      out
    end

    # A line that opens a list item — a boundary reflow must not cross.
    LIST_START = /\A\s*(?:[•▪◦*+-]|\d+[.)])\s/.freeze

    # Re-flow rendered markdown to `limit` columns.
    #
    # Wrapping alone is not enough: the bodies are authored at ~80 columns and
    # tty-markdown keeps those hard breaks, so wrapping each line in isolation
    # leaves a short orphan after every one it splits. Consecutive prose lines
    # are therefore joined back into a paragraph and wrapped as a unit. Blank
    # lines, tables and list items end a paragraph, which is what keeps headings
    # and structure from being swallowed into the prose beneath them.
    def reflow(lines, limit)
      out = []
      paragraph = []

      flush = lambda do
        next if paragraph.empty?

        indent = paragraph.first[/\A */]
        out.concat(wrap_ansi(indent + paragraph.map(&:strip).join(" "), limit))
        paragraph = []
      end

      lines.each do |line|
        line = line.chomp
        plain = line.gsub(ANSI, "")

        if plain.strip.empty? || plain.match?(TABULAR) || plain.match?(LIST_START)
          flush.call
          out.concat(wrap_ansi(line, limit))
        else
          paragraph << line
        end
      end

      flush.call
      out
    end

    # Close a row that opened a colour, so the style cannot bleed into the pane
    # beside it. A row carrying no escapes needs no reset — and withholding it
    # there keeps uncoloured output byte-clean, which is what makes a captured
    # frame worth diffing.
    def reset_if_styled(row)
      row.match?(ANSI) ? "#{row}\e[0m" : row
    end

    def blank_line(limit)
      " " * [ limit, 0 ].max
    end

    # A single output row assembled segment by segment, each optionally styled.
    # The builder tracks how many columns it has spent, so a segment that would
    # overflow is clipped before it is coloured and the finished row always
    # measures exactly `limit` columns.
    class Line
      def initialize(limit)
        @limit = [ limit, 0 ].max
        @spent = 0
        @buffer = +""
      end

      # Append `text`, styled with zero or more Pastel colour names.
      def add(text, *styles)
        room = @limit - @spent
        return self if room <= 0

        piece = Ui.clip(text, room)
        return self if piece.empty?

        @spent += Ui.width(piece)
        @buffer << (styles.empty? ? piece : Ui.pastel.decorate(piece, *styles))
        self
      end

      # Append `count` spaces (no-op past the edge).
      def space(count = 1)
        add(" " * count)
      end

      # Pad the rest of the row out to `limit` columns.
      def to_s
        @buffer + (" " * (@limit - @spent))
      end

      def empty?
        @spent.zero?
      end
    end

    def line(limit)
      row = Line.new(limit)
      yield row if block_given?
      row.to_s
    end

    # Force a list of rows to exactly `height` rows of exactly `width` columns —
    # the invariant every pane must satisfy before it can be joined to another.
    # Both directions matter: a short row leaves the pane beside it smeared
    # across the gap, and a long one wraps onto the next terminal row and pushes
    # the whole frame down.
    def fit_block(rows, width:, height:)
      rows = rows.first(height)
      rows += [ blank_line(width) ] * (height - rows.length)

      rows.map do |row|
        spent = Ui.width(row)
        if spent < width
          row + (" " * (width - spent))
        elsif spent > width
          clip_ansi(row, width)
        else
          row
        end
      end
    end

    # Join panes side by side, row for row. Each pane must already be a
    # rectangle (see fit_block), which is what makes this a plain zip.
    def hjoin(*panes)
      height = panes.map(&:length).max.to_i
      Array.new(height) do |index|
        panes.map { |pane| pane[index].to_s }.join
      end
    end

    # A framed pane. TTY::Box draws the border; we hand it content that is
    # already clipped to the inner width so its own padding never has to guess.
    def box(rows, width:, height:, title: nil, active: false)
      inner_width = width - 2
      inner_height = height - 2
      body = fit_block(rows, width: inner_width, height: inner_height)

      border_fg = active ? :cyan : :bright_black
      titles = title ? { top_left: title_label(title, active) } : {}

      frame = TTY::Box.frame(
        width: width,
        height: height,
        border: { type: active ? :thick : :light },
        style: { border: { fg: border_fg } },
        title: titles
      ) { body.join("\n") }

      frame.lines.map(&:chomp)
    end

    def title_label(title, active)
      label = " #{title} "
      active ? pastel.decorate(label, :black, :on_cyan, :bold) : pastel.decorate(label, :bright_white, :bold)
    end
  end
end
