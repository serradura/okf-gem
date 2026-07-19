# frozen_string_literal: true

require "test_helper"
require "okf"

# The dependency rule made executable: the pure core must not reach into the
# shell (Storage/Render/CLI) or touch disk/stdio. If someone drops a File.read
# back into the Validator, this fails.
class OKF::BoundaryTest < OKF::TestCase
  CORE = %w[
    path
    markdown/frontmatter markdown/links markdown/citations
    concept bundle bundle/graph
    bundle/search bundle/search/index bundle/search/scan
    bundle/validator bundle/validator/result bundle/linter bundle/linter/report
  ].freeze

  LIB = File.expand_path("../../lib/okf", __dir__)

  FORBIDDEN = {
    "a shell namespace (CLI, Server) or an on-disk handle (Concept::File, Bundle::{Reader,Writer,Folder})" =>
      %r{\bOKF::CLI\b|\bOKF::Server\b|\bServer::(App|Graph)\b|\bConcept::File\b|\bBundle::(Reader|Writer|Folder)\b|\b(Storage|Render)::[A-Z]},
    "filesystem I/O" => /\bFile\.(read|write|open|delete|rename|unlink)\b|\bDir\.[a-z]|\bFileUtils\b|\bIO\.\w/,
    "stdio" => /\$stdout|\$stderr|\bSTDOUT\b|\bSTDERR\b/
  }.freeze

  CORE.each do |name|
    test "core file #{name}.rb keeps the boundary — no shell deps, no I/O" do
      lines = File.readlines(File.join(LIB, "#{name}.rb"), encoding: "UTF-8")
      FORBIDDEN.each do |label, pattern|
        offenders = lines.each_with_index.map do |line, index|
          next if line.match?(/\A\s*#/) # ignore doc comments; the rule is about code

          "L#{index + 1}: #{line.strip}" if line.match?(pattern)
        end.compact
        assert_empty offenders, "#{name}.rb must not reference #{label}"
      end
    end
  end
end
