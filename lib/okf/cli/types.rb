# frozen_string_literal: true

module OKF
  class CLI
    # The type index: which types exist, how often, and on what.
    class Types < Command
      def self.id
        :types
      end

      def self.group
        :read
      end

      def self.help_rows
        [
          [ "types     <dir|@slug> [--json] [filters]", "list types with their concepts, by count" ]
        ]
      end

      def call(argv)
        options = { json: false }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf types <dir|@slug> [--area A] [--tag T] [--json]"
          json_flags(o, options, "emit the type index as JSON")
          filter_flags(o, options, :area, :tag)
          help_flag(o)
        end
        dir = positional_dir(parser, argv) or return 2

        print_inverted_index(dir, "Types", :type, "types", options)
      end
    end

    register(Types)
  end
end
