# frozen_string_literal: true

module OKF
  class Bundle
    # Atomically writes a bundle to disk: renders concepts to a temp directory,
    # validates it for §9 conformance (so a malformed bundle is never published),
    # then promotes it into place under a lock. The disk-writing counterpart to
    # Reader.
    class Writer
      class AlreadyExistsError < Error
      end

      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(bundle_path:, concepts:, index_files: {}, log_files: {}, overwrite: false)
        @bundle_path = File.expand_path(bundle_path.to_s)
        @concepts = concepts
        @index_files = index_files
        @log_files = log_files
        @overwrite = overwrite
      end

      def call
        FileUtils.mkdir_p(parent_path)
        with_lock do
          raise AlreadyExistsError, "bundle already exists: #{@bundle_path}" if target_exists? && !@overwrite

          temp_path = build_temp_path
          FileUtils.mkdir_p(temp_path)
          begin
            write_bundle(temp_path)
            result = Validator.call(Reader.read(temp_path))
            raise ValidationErrorFromResult.new(result), "materialized bundle is invalid" unless result.valid?

            promote(temp_path)
          ensure
            FileUtils.rm_rf(temp_path)
          end
        end

        true
      end

      private

      def with_lock
        File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |file|
          begin
            file.flock(File::LOCK_EX)
            yield
          ensure
            file.flock(File::LOCK_UN)
          end
        end
      end

      def write_bundle(root)
        @concepts.each { |concept| write_concept(root, concept) }
        @index_files.each { |path, content| write_plain_file(root, path, content) }
        @log_files.each { |path, content| write_plain_file(root, path, content) }
      end

      # Accepts an OKF::Concept (the currency Bundle::Reader produces) or a plain
      # {path:, frontmatter:, body:} hash, so a bundle can be round-tripped through
      # Reader -> Writer without repacking into hashes.
      def write_concept(root, concept)
        path = safe_markdown_path!(concept_attr(concept, :path))
        frontmatter = concept_attr(concept, :frontmatter)
        body = concept_attr(concept, :body)
        write_plain_file(root, path, Markdown::Frontmatter.dump(frontmatter, body))
      end

      def concept_attr(concept, name)
        concept.is_a?(Concept) ? concept.public_send(name) : concept.fetch(name)
      end

      def write_plain_file(root, path, content)
        safe_path = safe_markdown_path!(path)
        target = Path.join_under!(root, safe_path)
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, content.to_s, encoding: "UTF-8")
      end

      def safe_markdown_path!(path)
        safe_path = Path.normalize_relative!(path)

        raise Path::Error, "path must end in .md" unless safe_path.end_with?(".md")

        safe_path
      end

      def promote(temp_path)
        if @overwrite && File.exist?(@bundle_path)
          backup_path = "#{@bundle_path}.replacing-#{SecureRandom.hex(8)}"
          File.rename(@bundle_path, backup_path)
          begin
            File.rename(temp_path, @bundle_path)
            FileUtils.rm_rf(backup_path)
          rescue StandardError
            File.rename(backup_path, @bundle_path) unless File.exist?(@bundle_path)
            raise
          end
        else
          Dir.rmdir(@bundle_path) if Dir.exist?(@bundle_path) && Dir.entries(@bundle_path).reject { |entry| [ ".", ".." ].include?(entry) }.empty?
          File.rename(temp_path, @bundle_path)
        end
      end

      def target_exists?
        File.exist?(@bundle_path) && (!Dir.exist?(@bundle_path) || Dir.entries(@bundle_path).reject { |entry| [ ".", ".." ].include?(entry) }.any?)
      end

      def parent_path
        File.dirname(@bundle_path)
      end

      def lock_path
        File.join(parent_path, ".#{File.basename(@bundle_path)}.okf.lock")
      end

      def build_temp_path
        File.join(parent_path, ".#{File.basename(@bundle_path)}.tmp-#{Process.pid}-#{Thread.current.object_id}-#{SecureRandom.hex(8)}")
      end

      class ValidationErrorFromResult < Error
        attr_reader :result

        def initialize(result)
          @result = result
          super()
        end
      end
    end
  end
end
