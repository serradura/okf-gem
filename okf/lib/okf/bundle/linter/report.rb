# frozen_string_literal: true

module OKF
  class Bundle
    class Linter
      # The result of linting a bundle for curation quality (see OKF::Bundle::Linter). Mirrors
      # OKF::Bundle::Validator::Result, but lint has no errors — only `:warn` and `:info`
      # findings — and carries free-form `stats` in place of conformance counts. A
      # bundle is "healthy" when it has no `:warn` findings; `:info` never makes it
      # unhealthy. Every finding is a self-describing Hash so #to_h is a stable machine
      # substrate an agent can act on.
      class Report
        attr_reader :findings, :stats

        def initialize
          @findings = []
          @stats = {}
        end

        def add_warning(check, path, message, metric: nil)
          @findings << finding(:warn, check, path, message, metric)
        end

        def add_info(check, path, message, metric: nil)
          @findings << finding(:info, check, path, message, metric)
        end

        def warnings
          findings.select { |f| f[:severity] == :warn }
        end

        def info
          findings.select { |f| f[:severity] == :info }
        end

        def healthy?
          warnings.empty?
        end

        def stat(key, value)
          @stats[key] = value
        end

        def to_h
          { healthy: healthy?, stats: stats, findings: findings }
        end

        private

        def finding(severity, check, path, message, metric)
          { check: check, severity: severity, path: path, message: message, metric: metric }
        end
      end
    end
  end
end
