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

    # An agent discovers a skill as <skills-dir>/<name>/SKILL.md, so by default
    # (nest: true) the tree lands in a skills/okf/ folder under the destination:
    #
    #   okf skill .claude         -> .claude/skills/okf   (adds skills/ then okf/)
    #   okf skill .agents/skills  -> .agents/skills/okf   (already a skills dir)
    #   okf skill .../skills/okf  -> .../skills/okf        (already the skill dir)
    #
    # Point it at a project or skills directory and the skill settles in its own
    # folder instead of splattering its files loose among the others. Pass
    # nest: false (`--here`) to install straight into the destination, wherever it
    # is.
    NAME = "okf"
    SKILLS_DIR = "skills"

    def self.install(dest, force: false, nest: true)
      new(dest, force: force, nest: nest).install
    end

    attr_reader :dest

    def initialize(dest, force: false, nest: true)
      @dest = nest ? resolve(dest.to_s) : dest.to_s
      @path = File.expand_path(@dest)
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

    private

    # Resolve the destination to a skills/okf leaf, so the skill always sits in its
    # own folder under whatever the user pointed at. A destination already named
    # okf is the skill dir itself (idempotent); one named skills only needs okf/.
    def resolve(dest)
      case File.basename(dest)
      when NAME then dest
      when SKILLS_DIR then File.join(dest, NAME)
      else File.join(dest, SKILLS_DIR, NAME)
      end
    end
  end
end
