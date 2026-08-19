# frozen_string_literal: true

module OKF
  module Pro
    # The hook event: the only place this checker parses input it did not write.
    #
    # An event it cannot read is enforcement that did not run, so the failure is
    # recorded rather than swallowed. The first cut rescued the parse error into
    # an empty hash, every guard read an empty path, and the check passed — the
    # same shape as the `jq` hole this checker exists to close, rebuilt in Ruby.
    # Whoever calls it decides what to do with the failure; nobody gets to not
    # know about it.
    class Event
      attr_reader :parse_error

      def self.from_stdin(io = $stdin)
        new(io.read)
      end

      def initialize(raw)
        @data = {}
        @parse_error = nil

        # The same defense Pro.read_text gives files, applied to the one
        # input that arrives as a stream: forced to UTF-8 and scrubbed. Stdin
        # under a bare locale (common in CI and git hooks) arrives tagged
        # US-ASCII, and a clean em dash in an edit's new_string then raised
        # out of the very first string operation — above the dispatch rescue,
        # so ruby exited 1, which the hook protocol reads as NON-BLOCKING.
        # The guard's own input was the bypass.
        text = raw.to_s.dup.force_encoding(Encoding::UTF_8).scrub
        if text.strip.empty?
          @parse_error = "the hook received no event on stdin"
          return
        end

        begin
          parsed = JSON.parse(text)
          if parsed.is_a?(Hash)
            @data = parsed
          else
            @parse_error = "the event was #{parsed.class}, not a JSON object"
          end
        rescue JSON::ParserError => e
          @parse_error = "the event was not parseable JSON (#{e.message.split("\n").first})"
        end
      end

      def parse_error?
        !@parse_error.nil?
      end

      def tool_name
        @data["tool_name"].to_s
      end

      def stop_hook_active?
        @data["stop_hook_active"] == true
      end

      def tool_input
        @data["tool_input"].is_a?(Hash) ? @data["tool_input"] : {}
      end

      def file_path
        tool_input["file_path"].to_s
      end

      # Bash's payload. Named for what it is rather than reached for through
      # tool_input at three call sites.
      def command
        tool_input["command"].to_s
      end

      def cwd
        raw = @data["cwd"].to_s
        raw.empty? ? Dir.pwd : raw
      end

      # Both spellings are read on purpose. Claude Code's Edit/MultiEdit send
      # `new_string`; the shell shims this replaces only ever looked for
      # `new_str`, so the `verified:` guard passed every real edit it was built
      # to stop and only ever refused the synthetic JSON in its own drill. A gate
      # tested exclusively by the shape it was written against is not tested.
      def added_text
        parts = [ tool_input["new_string"], tool_input["new_str"], tool_input["content"] ]
        edits = tool_input["edits"]
        if edits.is_a?(Array)
          parts.concat(edits.map { |e| e.is_a?(Hash) ? [ e["new_string"], e["new_str"] ] : nil })
        end
        parts.flatten.compact.join("\n")
      end
    end
  end
end
