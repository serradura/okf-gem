# frozen_string_literal: true

# The plugin's PostToolUse curation hook: after Claude writes or edits a file
# inside an OKF bundle, run `okf validate` + `okf lint` on that bundle and hand
# the relevant findings back as additional context. Deterministic — the gem's
# own checks are the detector, no LLM in the loop.
#
# Contract (Claude Code hooks):
#   stdin   the event JSON (tool_input.file_path, session_id, …)
#   stdout  optional JSON: { "hookSpecificOutput": { "additionalContext": … } }
#   exit 0  always — curation must never turn an unrelated edit into an error.
#
# Plain Ruby, stdlib only, same 2.4 floor as the gem: the hook runs on whatever
# Ruby the machine already has, before the gem is even installed.

require "json"
require "open3"
require "tmpdir"

module OKF
  module PluginHook
    class Curate
      # Keep the feedback scannable; `/okf:gem curate` exists for the full report.
      MAX_LINES = 12

      def self.run(stdin: $stdin, stdout: $stdout)
        new.run(stdin, stdout)
      end

      # The CLI runner is injectable so tests drive the hook without a gem
      # install: it takes (verb, root) and returns the CLI's stdout.
      def initialize(runner: nil)
        @runner = runner || method(:run_cli)
      end

      def run(stdin, stdout)
        event = parse(stdin) or return 0
        file = edited_markdown(event) or return 0
        root = bundle_root(file) or return 0

        reports = fetch_reports(root)
        return missing_cli(event, stdout) if reports.nil?

        context = context_for(reports, relative(file, root))
        unless context.nil?
          emit(stdout, "hookSpecificOutput" => {
            "hookEventName" => "PostToolUse", "additionalContext" => context
          })
        end
        0
      end

      # ── the gate: cheap enough to run on every edit ──────────────────────────

      # The edited file when it is markdown, nil otherwise (other tools, other
      # file types, missing paths — all silently out of scope).
      def edited_markdown(event)
        input = event["tool_input"]
        path = input.is_a?(Hash) ? input["file_path"] : nil
        path.is_a?(String) && path.end_with?(".md") ? File.expand_path(path) : nil
      end

      # Walk up from the edited file looking for a bundle root: the directory
      # whose index.md opens a frontmatter block carrying okf_version — only the
      # bundle-root index has frontmatter at all (§9.3), so a nested index never
      # matches. A stat per level and one short read; no gem process.
      def bundle_root(file)
        dir = File.dirname(file)
        loop do
          return dir if root_index?(File.join(dir, "index.md"))

          parent = File.dirname(dir)
          return nil if parent == dir

          dir = parent
        end
      end

      def root_index?(path)
        return false unless File.file?(path)

        head = File.open(path, "rb") { |io| io.read(512) }.to_s
        head.start_with?("---") && head.include?("okf_version")
      end

      # ── the detectors: the okf CLI itself ────────────────────────────────────

      # Both reports parsed, or nil when the CLI is not installed. A CLI that
      # exists but misbehaves degrades to empty reports, never to an error.
      def fetch_reports(root)
        { validation: report("validate", root), lint: report("lint", root) }
      rescue Errno::ENOENT
        nil
      end

      def report(verb, root)
        JSON.parse(@runner.call(verb, root).to_s)
      rescue JSON::ParserError
        {}
      end

      def run_cli(verb, root)
        out, _err, _status = Open3.capture3("okf", verb, root, "--json")
        out
      end

      # ── findings → context ───────────────────────────────────────────────────

      # The curation text for this edit, or nil when there is nothing to say:
      # every conformance error (bundle-wide, always hard), plus the validate
      # warnings and lint findings that concern the edited file.
      def context_for(reports, rel)
        errors = Array(reports[:validation]["errors"])
        warnings = Array(reports[:validation]["warnings"]).select { |w| w["path"] == rel }
        findings = Array(reports[:lint]["findings"]).select { |f| concerns?(f, rel) }
        return nil if errors.empty? && warnings.empty? && findings.empty?

        build_context(errors, warnings, findings)
      end

      # A lint finding concerns the edit when it points at the edited file, or —
      # for backlog findings like missing_concept — when the edited concept is
      # among the sources demanding a target that does not exist.
      def concerns?(finding, rel)
        return true if finding["path"] == rel

        metric = finding["metric"]
        sources = metric.is_a?(Hash) ? Array(metric["sources"]) : []
        sources.include?(rel.sub(/\.md\z/, ""))
      end

      def build_context(errors, warnings, findings)
        lines = errors.map { |e| "  ✗ error #{e["path"]}: #{e["message"]}" } +
                warnings.map { |w| "  ! warn #{w["path"]}: #{w["message"]}" } +
                findings.map { |f| "  #{f["severity"] == "warn" ? "!" : "·"} lint/#{f["check"]} #{f["path"]}: #{f["message"]}" }

        shown = lines.take(MAX_LINES)
        shown << "  … #{lines.size - MAX_LINES} more (run /okf:gem curate for the full report)" if lines.size > MAX_LINES
        verdict = errors.empty? ? "Advisory curation debt — settle what this task touches." : "Fix the error(s) before finishing; the rest is curation debt."
        ([ "okf curation — #{summary(errors, warnings, findings)}:" ] + shown + [ verdict ]).join("\n")
      end

      def summary(errors, warnings, findings)
        parts = []
        parts << pluralize(errors.size, "error") unless errors.empty?
        parts << pluralize(warnings.size, "warning") unless warnings.empty?
        parts << pluralize(findings.size, "lint finding") unless findings.empty?
        parts.join(", ")
      end

      def pluralize(count, noun)
        count == 1 ? "#{count} #{noun}" : "#{count} #{noun}s"
      end

      # `okf` not installed: say so once per session (a marker file keyed by the
      # session id), then stay silent — never an error per edit.
      def missing_cli(event, stdout)
        session = event["session_id"].to_s.gsub(/[^\w-]/, "_")
        marker = File.join(Dir.tmpdir, "okf-plugin-#{session.empty? ? "nosession" : session}.notified")
        return 0 if File.exist?(marker)

        File.write(marker, "")
        emit(stdout, "systemMessage" => "okf plugin: the `okf` CLI is not installed, so bundle curation is off. Run /okf:gem to set it up.")
        0
      end

      # ── plumbing ─────────────────────────────────────────────────────────────

      def relative(file, root)
        file[(root.length + 1)..-1]
      end

      def emit(stdout, payload)
        stdout.puts(JSON.generate(payload))
      end

      def parse(stdin)
        JSON.parse(stdin.read)
      rescue JSON::ParserError
        nil
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    OKF::PluginHook::Curate.run
  rescue StandardError
    # Silence is the failure mode: a broken hook must not break the session.
  end
  exit 0
end
