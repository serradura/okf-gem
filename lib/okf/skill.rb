# frozen_string_literal: true

module OKF
  # Installs this gem's companion agent skill — the SKILL.md + reference/ +
  # templates/ that teach an agent to author, maintain, and consume OKF bundles
  # and to drive the `okf` executable — into a destination directory.
  #
  # The skill ships *inside* the gem (under lib/okf/skill), so `gem install okf`
  # provides both the CLI and the skill that uses it, and the two can never drift
  # apart in version: the skill's own reference/cli.md always matches the CLI it
  # was released with.
  class Skill
    class Error < OKF::Error
    end

    # The canonical skill tree, bundled in the sibling skill/ directory.
    ASSETS = File.expand_path("skill", __dir__)

    def self.install(dest, force: false)
      new(dest, force: force).install
    end

    attr_reader :dest

    def initialize(dest, force: false)
      @dest = File.expand_path(dest.to_s)
      @force = force
    end

    # Copy the skill tree into dest, creating it if needed. Refuses to write over
    # a non-empty directory unless forced, so an existing (possibly customized)
    # skill is never silently clobbered. Returns the relative paths written.
    def install
      if File.exist?(@dest) && !File.directory?(@dest)
        raise Error, "destination #{@dest} exists and is not a directory"
      end
      if File.directory?(@dest) && !Dir.empty?(@dest) && !@force
        raise Error, "destination #{@dest} is not empty (pass --force to overwrite)"
      end

      FileUtils.mkdir_p(@dest)
      FileUtils.cp_r(File.join(ASSETS, "."), @dest)
      files
    end

    # Relative paths of every file in the bundled skill, sorted for stable output.
    def files
      Dir.glob(File.join(ASSETS, "**", "*"))
         .select { |path| File.file?(path) }
         .map { |path| path[(ASSETS.length + 1)..-1] }
         .sort
    end
  end
end
