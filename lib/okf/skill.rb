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

    # The skill's own directory name. An agent discovers a skill as
    # <skills-dir>/<name>/SKILL.md, so by default (nest: true) the tree is
    # installed under a <dest>/okf subdirectory: pointing `okf skill` at a shared
    # skills directory drops the skill in its own folder instead of splattering its
    # files loose among the others. A <dest> already named "okf" is taken as-is
    # (idempotent), and nest: false installs straight into <dest>.
    NAME = "okf"

    def self.install(dest, force: false, nest: true)
      new(dest, force: force, nest: nest).install
    end

    attr_reader :dest

    def initialize(dest, force: false, nest: true)
      target = dest.to_s
      target = File.join(target, NAME) if nest && File.basename(target) != NAME
      @dest = target
      @path = File.expand_path(target)
      @force = force
    end

    # Copy the skill tree into dest, creating it if needed. Refuses to write over
    # a non-empty directory unless forced, so an existing (possibly customized)
    # skill is never silently clobbered. Returns the relative paths written.
    def install
      if File.exist?(@path) && !File.directory?(@path)
        raise Error, "destination #{@dest} exists and is not a directory"
      end
      if File.directory?(@path) && !Dir.empty?(@path) && !@force
        raise Error, "destination #{@dest} is not empty (pass --force to overwrite)"
      end

      FileUtils.mkdir_p(@path)
      FileUtils.cp_r(File.join(ASSETS, "."), @path)
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
