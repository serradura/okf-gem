# frozen_string_literal: true

require "mcp"

module OKF
  module MCP
    # Bundles and concepts as MCP resources — the affordance no tool call
    # provides: a host can *attach* a document to the context itself, without
    # the model having to decide to fetch it.
    #
    # Two shapes, for two different costs. A **static resource per bundle**,
    # derived from the registry alone, so listing costs one `stat` per bundle
    # and never a parse. A **template for concepts**, resolved live, because
    # enumerating every concept would mean reading every bundle at boot — which
    # is exactly the eager work the residency layer exists to avoid, and would
    # freeze a list that the fingerprint check is meant to keep honest.
    #
    # A bundle is listed only when it actually has a root `index.md` (the spec
    # makes it optional), so *listed implies readable* — no synthesized stand-in
    # that would put invented prose behind a real URI.
    module Resources
      SCHEME = "okf://"
      TEMPLATE = "#{SCHEME}{bundle}/{id}"
      MIME = "text/markdown"
      ROOT_INDEX = "index.md"

      class << self
        # One resource per served bundle that has a root index — the "start
        # here" document, and the only bundle-level file whose meaning is fixed
        # by the spec.
        def list(registry)
          registry.entries.select { |entry| root_index?(entry.root) }.map do |entry|
            ::MCP::Resource.new(
              uri: SCHEME + entry.slug,
              name: entry.slug,
              title: entry.title,
              description: "The #{entry.slug} bundle's root index — its map, read live from disk.",
              mime_type: MIME
            )
          end
        end

        # Published for discovery only. The SDK binds `{id}` to `[^/]+`, and
        # every OKF id below the root carries a slash, so this template can
        # advertise the shape but must never be the thing that parses it — see
        # #read, which owns the parsing.
        def templates
          [
            ::MCP::ResourceTemplate.new(
              uri_template: TEMPLATE,
              name: "okf-concept",
              title: "OKF concept",
              description: "One concept's markdown, verbatim and live from disk. " \
                           "`bundle` is a slug from list_bundles; `id` is a concept id " \
                           "(e.g. runbooks/billing-restart) and may contain slashes.",
              mime_type: MIME
            )
          ]
        end

        # The whole read surface, for both shapes. Returns the `contents` array
        # the SDK puts straight into the response.
        def read(context, uri)
          slug, id = parse(uri)
          not_found(uri) if slug.nil?

          # Raises the kernel's own refusal for a bundle argv did not serve: a
          # URI is not a path, and the allowlist is the only door.
          root = context.root!(slug)
          text = id ? concept_text(context, slug, id, uri) : root_index_text(root, uri)
          [ ::MCP::Resource::TextContents.new(uri: uri, mime_type: MIME, text: text).to_h ]
        rescue Error, OKF::Error => e
          invalid_params(e.message, uri)
        rescue SystemCallError
          not_found(uri)
        end

        # Argument completion for the template above — the half that makes a
        # template browsable instead of a shape you have to already know. Only
        # the template's own two arguments answer; our prompts take none.
        #
        # Never an error and never a partial leak: an unserved bundle, an
        # unknown argument and a missing context all complete to nothing, so a
        # completion request cannot be used to probe what argv did not serve.
        def complete(context, params)
          ref = params[:ref] || {}
          return [] unless ref[:type] == "ref/resource" && ref[:uri] == TEMPLATE

          argument = params[:argument] || {}
          value = argument[:value].to_s
          case argument[:name].to_s
          when "bundle" then prefixed(context.registry.slugs, value)
          when "id" then prefixed(concept_ids(context, params.dig(:context, :arguments)), value)
          else []
          end
        end

        private

        # Case-folded, like every other name comparison in this gem.
        def prefixed(values, value)
          return values if OKF.blank?(value)

          needle = value.downcase
          values.select { |candidate| candidate.downcase.start_with?(needle) }
        end

        # The ids of the bundle the caller has already filled in. With no
        # bundle there is no set to complete from, and answering across every
        # served bundle would offer ids from one nobody named.
        def concept_ids(context, arguments)
          slug = arguments && (arguments[:bundle] || arguments["bundle"])
          return [] if OKF.blank?(slug)

          root = context.root!(slug)
          context.engine.catalog(root, {}).map { |row| row[:id].to_s }.sort
        rescue Error, OKF::Error, SystemCallError
          []
        end

        # `okf://<slug>` or `okf://<slug>/<id>`, where the id keeps every slash
        # after the first. Returns [ nil, nil ] for anything else rather than
        # guessing — a scheme this server does not own is not its business.
        def parse(uri)
          return [ nil, nil ] unless uri.is_a?(String) && uri.start_with?(SCHEME)

          slug, id = uri[SCHEME.length..].split("/", 2)
          return [ nil, nil ] if OKF.blank?(slug)

          [ slug, OKF.blank?(id) ? nil : id ]
        end

        # The root index, read directly — the one bundle file that does not come
        # through paths_by_id, so it carries no containment on its own. A
        # symlinked index.md whose target sits outside the root is refused here
        # rather than followed: the kernel's read guards protect every concept,
        # and this is the matching guard for the one file that bypasses them.
        def root_index_text(root, uri)
          OKF::SafeRead.read!(root, ::File.join(root, ROOT_INDEX))
        rescue OKF::Path::Error
          not_found(uri)
        end

        def concept_text(context, slug, id, uri)
          handle = context.folder(slug).concept(id)
          not_found(uri) unless handle

          # The file's own bytes, exactly as read_concept takes them, through the
          # same guarded read: handle.read resolves the real path and refuses a
          # symlink escaping the root, so no request string reaches the filesystem
          # as a path and no swapped-in link leaks an outside file.
          handle.read
        end

        # Listed implies readable, so a bundle whose index.md is a symlink out of
        # the root is not listed at all — the same escape #root_index_text refuses
        # on read, applied one step earlier so the URI is never advertised.
        def root_index?(root)
          path = ::File.join(root, ROOT_INDEX)
          return false unless ::File.file?(path)

          OKF::SafeRead.contained_path!(root, path)
          true
        rescue OKF::Path::Error, SystemCallError
          false
        end

        def not_found(uri)
          raise ::MCP::Server::ResourceNotFoundError, uri
        end

        # The kernel's sentence, kept rather than flattened into "Invalid
        # params" — the same rule the tools follow when they turn a refusal into
        # an isError response. Passing the code explicitly is what preserves the
        # message; error_type alone would replace it with the generic string.
        def invalid_params(message, uri)
          raise ::MCP::Server::RequestHandlerError.new(
            message, nil,
            error_type: :invalid_params,
            error_code: ::JsonRpcHandler::ErrorCode::INVALID_PARAMS,
            error_data: { uri: uri }
          )
        end
      end
    end
  end
end
