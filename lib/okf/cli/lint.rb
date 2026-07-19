# frozen_string_literal: true

module OKF
  class CLI
    # The curation judge: is this bundle *good*? Advisory by design — findings
    # never change the exit code unless --fail-on says so, because a stub or a
    # loose leaf can be deliberate. Freshness is off unless --stale-after asks.
    class Lint < Command
      # Lint findings grouped for display, in category order.
      LINT_CATEGORIES = {
        "Reachability" => %i[orphan not_in_index disconnected_component unlinked],
        "Backlog" => %i[missing_concept broken_index_entry],
        "Completeness" => %i[stub missing_title missing_description missing_timestamp],
        "Freshness" => %i[stale],
        "Provenance" => %i[uncited_external broken_citation],
        "Hygiene" => %i[duplicate_title unused_reference_def undefined_reference self_link]
      }.freeze

      def self.id
        :lint
      end

      def self.group
        :judge
      end

      def self.help_rows
        [
          [ "lint      <dir|@slug> [--json] [--fail-on warn] [...]", "report curation-quality issues" ]
        ]
      end

      def call(argv)
        options = { json: false, min_body: OKF::Bundle::Linter::DEFAULT_MIN_BODY, stale_after: nil, only: nil, except: nil, fail_on: :never }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf lint <dir|@slug> [--json] [--min-body N] [--stale-after DUR] [--only a,b] [--except a,b] [--fail-on warn]"
          json_flags(o, options, "emit a JSON report")
          o.on("--min-body N", Integer, "stub threshold in body characters (default #{OKF::Bundle::Linter::DEFAULT_MIN_BODY})") { |v| options[:min_body] = v }
          o.on("--stale-after DUR", "flag concepts older than DUR (e.g. 90d, 12w, 2026-01-01)") { |v| options[:stale_after] = v }
          o.on("--only LIST", Array, "run only these checks (comma-separated)") { |v| options[:only] = v.map(&:to_sym) }
          o.on("--except LIST", Array, "skip these checks (comma-separated)") { |v| options[:except] = v.map(&:to_sym) }
          o.on("--fail-on LEVEL", %w[never warn], "exit 1 when a finding at LEVEL exists (never | warn)") { |v| options[:fail_on] = v.to_sym }
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        unknown = ((options[:only] || []) + (options[:except] || [])) - OKF::Bundle::Linter::CHECKS
        unless unknown.empty?
          @err.puts "error: unknown check(s): #{unknown.uniq.join(", ")}"
          return 2
        end

        stale_before = parse_stale_after(options[:stale_after])
        if stale_before == :invalid
          @err.puts "error: invalid --stale-after `#{options[:stale_after]}` (use 90d, 12w, or an ISO date like 2026-01-01)"
          return 2
        end

        folder = OKF::Bundle::Folder.load(dir)
        report = folder.lint(min_body: options[:min_body], stale_before: stale_before, only: options[:only], except: options[:except])
        note_skipped(report.stats[:skipped])
        options[:json] ? print_lint_json(dir, report) : print_lint(dir, report)
        options[:fail_on] == :warn && report.warnings.any? ? 1 : 0
      end

      private

      # Turn a --stale-after value (90d, 12w, or an ISO date) into an absolute cutoff
      # Time so the pure Linter never reads the clock. nil when unset, :invalid on a
      # bad value.
      def parse_stale_after(value)
        return nil if value.nil?

        if (match = value.match(/\A(\d+)([dw])\z/))
          days = match[1].to_i * (match[2] == "w" ? 7 : 1)
          Time.now - (days * 86_400)
        else
          Date.iso8601(value).to_time
        end
      rescue ArgumentError
        :invalid
      end

      def print_lint(dir, report)
        stats = report.stats
        @out.puts "OKF lint — #{bundle_label(dir)}"
        @out.puts "  concepts: #{stats[:concepts]}   edges: #{stats[:edges]}   index.md: #{stats[:indexes]}   log.md: #{stats[:logs]}"
        summary = lint_summary(stats)
        @out.puts "  #{summary}" unless summary.empty?

        LINT_CATEGORIES.each do |name, checks|
          findings = report.findings.select { |finding| checks.include?(finding[:check]) }
          next if findings.empty?

          @out.puts
          @out.puts "  #{name}"
          findings.each do |finding|
            @out.puts "    #{lint_glyph(finding)}  #{[ finding[:path], finding[:message] ].compact.join(": ")}"
          end
        end

        @out.puts
        @out.puts "  #{lint_verdict(report)}"
      end

      def print_lint_json(dir, report)
        emit_json(bundle_head(dir).merge(
          "healthy" => report.healthy?,
          "stats" => report.stats,
          "findings" => report.findings
        ))
      end

      def lint_summary(stats)
        parts = []
        hubs = stats[:hubs].map { |hub| "#{hub[:id]} (×#{hub[:in_degree]})" }.join(", ")
        types = stats[:types].map { |type, count| "#{type} #{count}" }.join(", ")
        parts << "hubs: #{hubs}" unless hubs.empty?
        parts << "types: #{types}" unless types.empty?
        parts.join("   ")
      end

      def lint_glyph(finding)
        finding[:severity] == :warn ? paint("! warn", 33) : "· info"
      end

      def lint_verdict(report)
        warnings = report.warnings.size
        infos = report.info.size
        return paint("✓ healthy — no issues", 32) if warnings.zero? && infos.zero?

        marker = warnings.zero? ? paint("✓", 32) : paint("⚠", 33)
        "#{marker} #{warnings} warn, #{infos} info"
      end
    end

    register(Lint)
  end
end
