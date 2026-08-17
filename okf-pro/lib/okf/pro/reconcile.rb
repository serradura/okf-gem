# frozen_string_literal: true

module OKF
  module Pro
    # Rule 1 — writing is reconciliation.
    #
    # Fires on Write, not Edit: a new concept is the moment a claim enters the
    # corpus, and the moment both it and whatever it collides with are cheapest
    # to hold in one head. Its reach is bounded by the filename's vocabulary,
    # which is exactly the limit the rule states about itself — it catches
    # collisions as well as your search words do, and no better.
    module Reconcile
      module_function

      def search(target, event)
        return [] if target.nil?
        return [] unless event.tool_name == "Write"
        return [] if target.rel.start_with?("journal/")
        return [] if NO_RECONCILE.include?(target.basename)

        hits = terms(target).map { |term| block_for(target, term) }.compact
        return [] if hits.empty?

        [ "RULE 1 — reconciliation. Existing concepts share this new concept's vocabulary. " \
          "Read them now: contradiction, supersession, or duplicate? Deprecate the loser at this " \
          "moment, or file a conflict line on board.md. Do not simply continue.\n#{hits.join("\n")}" ]
      end

      def terms(target)
        File.basename(target.rel, ".md").split("-")
            .reject { |t| t.empty? || STOP_WORDS.include?(t.downcase) }
            .first(4)
      end

      def block_for(target, term)
        rows = matches(target, term)
        return nil if rows.empty?

        statuses = status_index(target.bundle)
        body = rows.map do |r|
          "    #{r[:id]}#{settled(statuses[r[:id]])}  ·  #{r[:type]}  ·  #{r[:title]}\n      #{r[:snippet]}"
        end
        "— '#{term}':\n#{body.join("\n")}"
      end

      # §5.4's `status`, made operative. The skill teaches `status: deprecated`
      # as the machine-readable half of Rule 1's supersession move — correct the
      # loser NOW, and mark it — and this is what makes that teaching worth
      # anything: a collision with a concept that has already been deprecated is
      # a collision somebody already settled, and re-litigating it is the cost
      # the marking exists to avoid.
      #
      # It annotates rather than filters. A deprecated concept is "kept for
      # links and history, no longer current" (§5.4), so it is still a real hit
      # and still worth reading — what changes is what the reader does about it.
      # Filtering it out would hide the evidence that the question was answered.
      def settled(status)
        status == "deprecated" ? "  [deprecated — this collision was already settled]" : ""
      end

      def status_index(bundle)
        bundle.concepts.each_with_object({}) { |concept, index| index[concept.id] = concept.status }
      end

      # The concept being written is excluded (it is not its own collision), and
      # so are the structural files: a hit in README or board.md means they quote
      # a concept, not that they assert against one.
      def matches(target, term)
        ::OKF::Bundle::Search.call(target.bundle, term)
                             .reject { |r| r[:id] == target.id }
                             .reject { |r| NO_RECONCILE.include?("#{File.basename(r[:id])}.md") }
                             .first(5)
      end
    end
  end
end
