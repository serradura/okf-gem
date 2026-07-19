# frozen_string_literal: true

module OKF
  class CLI
    # Install this gem's companion agent skill into a destination directory. The
    # destination is required (no magic default) so the user always decides where
    # their agent picks the skill up. By default the skill lands in a skills/okf/
    # folder under it — point at a project or skills dir (.claude, .agents/skills)
    # and it settles in its own folder, never loose among the others — so the
    # resolved path is echoed back. --here installs straight into <dest-dir>.
    class Skill < Command
      def self.id
        :skill
      end

      def self.group
        :act
      end

      def self.help_rows
        [
          [ "skill     <dest> [--here] [--force]", "install the companion agent skill" ]
        ]
      end

      def call(argv)
        options = { force: false, nest: true }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf skill <dest-dir> [--here] [--force]"
          o.on("--here", "install straight into <dest-dir>, wherever it is (no skills/okf nesting)") { options[:nest] = false }
          o.on("--force", "overwrite a non-empty destination") { options[:force] = true }
          help_flag(o)
        end
        parser.parse!(argv)
        dest = argv.shift
        if dest.nil?
          @err.puts parser.banner
          return 2
        end

        skill = OKF::Skill.new(dest, force: options[:force], nest: options[:nest])
        files = skill.install
        @out.puts "installed the okf skill (#{files.size} files) -> #{skill.dest}"
        files.each { |f| @out.puts "  #{f}" }
        @out.puts "your agent picks it up from #{skill.dest} (needs the `okf` CLI, which you already have)."
        0
      rescue OptionParser::ParseError => e
        @err.puts e.message
        2
      rescue OKF::Skill::Error => e
        @err.puts "error: #{e.message}"
        2
      end
    end

    register(Skill)
  end
end
