# frozen_string_literal: true

module OKF
  class CLI
    # The §9 conformance judge: is this legal OKF? Binary and tolerant — it is
    # forbidden from failing a bundle over a broken link or a missing optional
    # field, which is lint's job. Exit 1 when non-conformant.
    class Validate < Command
      def self.id
        :validate
      end

      def self.group
        :judge
      end

      def self.help_rows
        [
          [ "validate  <dir|@slug> [--json]", "check OKF v0.1 conformance" ]
        ]
      end

      def call(argv)
        options = { json: false }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf validate <dir|@slug> [--json]"
          json_flags(o, options, "emit a JSON report")
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        result = OKF::Bundle::Folder.load(dir).validate
        options[:json] ? print_validation_json(dir, result) : print_validation(dir, result)
        result.valid? ? 0 : 1
      end

      private

      def print_validation(dir, result)
        counts = result.counts
        @out.puts "OKF v0.1 conformance — #{bundle_label(dir)}"
        @out.puts "  concepts: #{counts[:concepts]}   index.md: #{counts[:indexes]}   log.md: #{counts[:logs]}"
        result.errors.each { |e| @out.puts "  #{paint("✗ ERROR", 31)}  #{e[:path]}: #{e[:message]}" }
        result.warnings.each { |w| @out.puts "  #{paint("! warn", 33)}  #{w[:path]}: #{w[:message]}" }
        if result.valid? && result.warnings.empty?
          @out.puts "  #{paint("✓ conformant — no issues", 32)}"
        elsif result.valid?
          @out.puts "  #{paint("✓ conformant", 32)} (#{result.warnings.size} warning(s))"
        else
          @out.puts "  #{paint("✗ non-conformant", 31)} (#{result.errors.size} error(s))"
        end
      end

      def print_validation_json(dir, result)
        emit_json(bundle_head(dir).merge(
          "conformant" => result.valid?,
          "counts" => result.counts,
          "errors" => result.errors,
          "warnings" => result.warnings
        ))
      end
    end

    register(Validate)
  end
end
