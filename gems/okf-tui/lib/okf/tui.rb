# frozen_string_literal: true

require "okf"

require_relative "tui/version"

module OKF
  # A terminal UI over OKF bundles: read one, switch between many, configure the
  # registry, and search across all of them at once.
  #
  # `require "okf/tui"` loads the library only — the model, the workspace, and
  # the screens. The argv-facing shell (OKF::TUI::CLI, and its option parsing)
  # loads on demand: `okf tui` requires it from inside the plugin's #call, and so
  # must any test that drives it. An embedding app never pays for the
  # command-line machinery, and neither does an `okf lint` that merely made okf
  # read this gem's plugin file.
  #
  # The split okf enforces between its pure core and its shell is what makes this
  # small: OKF::Bundle::Reader and OKF::Registry are the only parts that touch
  # disk, and every answer on screen is a pure call on the resulting in-memory
  # bundles — catalog, graph, validate, lint, Bundle::Search. The TUI is one more
  # shell over the same core the `okf` CLI and the graph server already use, and
  # it invents no analysis of its own.
  module TUI
    class Error < OKF::Error
    end

    # What search needs from okf, checked rather than assumed: the engine facade
    # that merges several bundles into one ranked corpus (`across`, okf 1.9) and
    # the prepared corpus a long-lived caller queries instead of rebuilding
    # (`prepare`/`with`, okf 1.11).
    #
    # The gemspec's floor already requires both, so this is not about an old
    # dependency — it is about a *second* okf installed ahead of the intended one
    # on the load path, which no version constraint can prevent.
    #
    # It earns a check of its own because its absence is silent. Workspace#search
    # rescues a failed search into an empty result — right for a query okf cannot
    # parse, wrong for a method that is not there, because then every search
    # answers "no matches" and the screen reads as an empty bundle rather than a
    # broken install. The CLI refuses to boot instead of showing that screen.
    def self.search_capable?
      %i[across prepare with].all? { |name| OKF::Bundle::Search.respond_to?(name) }
    end

    # What §5 needs from okf, on the same argument and for a sharper reason.
    #
    # Every screen here now reads the v0.2 families — a concept's provenance in
    # browse, the spec version and the trust/status posture on health, two facets
    # in the graph — and each of them is a question only okf can answer:
    # `Bundle#okf_version` for what the bundle declares, and
    # `Bundle::RowFilter.shows_trust?` for whether a derived tier is one to claim.
    #
    # Against an okf without them the failure is a NoMethodError from inside a
    # frame, which is a crash where the screen should have been. Refusing at boot
    # says which gem is wrong instead, and says it once.
    def self.spec_capable?
      OKF::Bundle.method_defined?(:okf_version) &&
        defined?(OKF::Bundle::RowFilter) &&
        OKF::Bundle::RowFilter.respond_to?(:shows_trust?)
    end

    # ── layout: the primitives every screen draws through ──
    require_relative "tui/ui"

    # ── domain: one bundle, and the set of them a session can see ──
    require_relative "tui/model"
    require_relative "tui/workspace"

    # ── screens: pure row builders — no view writes to the terminal ──
    require_relative "tui/views"

    # ── shell: the interactive loop ──
    require_relative "tui/app"
  end
end
