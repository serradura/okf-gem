# frozen_string_literal: true

require "open3"

require_relative "../cli_integration_case"

# The branch added body-scanning regexes — FOOTNOTE, the Citations URL items,
# the label-capturing INLINE_LINK and the footnote-aware DEFINITION — and the
# em-dash-raises-on-first-regex class has already bitten this ecosystem: under
# a stripped locale Ruby's default_external is US-ASCII, and a regex meeting a
# UTF-8 string read in the wrong encoding raises on first contact. In-process
# runs inherit the suite's own sane locale, so this file is the one place the
# CLI runs as a real subprocess with LANG/LC_ALL/LC_CTYPE unset.
module ByDir
  # Bundles named by path — the plain form every verb accepts.
  class CLILocaleTest < CLIIntegrationCase
    test "non-ASCII source titles and footnote labels survive a stripped locale" do
      dir = fixture("unicode-sources")

      lint = bare_locale("lint", dir, "--json")
      assert_equal 0, lint[:status], "lint raised or failed under US-ASCII default_external: #{lint[:err]}"
      report = JSON.parse(lint[:out])
      refute(report["findings"].any? { |f| f["check"] == "unattributed_claim" },
        "the non-ASCII footnote label must join its non-ASCII sources[].id")

      search = bare_locale("search", dir, "receita", "--json")
      assert_equal 0, search[:status], search[:err]
      assert_equal [ "metricas" ], JSON.parse(search[:out])["matches"].map { |row| row["id"] }

      validate = bare_locale("validate", dir)
      assert_equal 0, validate[:status], validate[:err]
    end

    private

    def bare_locale(*argv)
      gem_root = File.expand_path("../../../..", __dir__)
      env = { "LANG" => nil, "LC_ALL" => nil, "LC_CTYPE" => nil }
      out, err, status = Open3.capture3(env, RbConfig.ruby, "-I", File.join(gem_root, "lib"),
        File.join(gem_root, "exe", "okf"), *argv)
      { out: out, err: err, status: status.exitstatus }
    end
  end
end
