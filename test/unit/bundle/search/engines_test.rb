# frozen_string_literal: true

require_relative "engine_conformance"

# One class per registered engine, each running the same contract. The file is
# deliberately thin: the assertions live in EngineConformance so that adding an
# engine is adding a class, not copying a suite.
#
# The registry itself is asserted here too — a built-in that stopped registering
# would otherwise keep passing conformance while no longer being reachable.

class IndexEngineTest < SearchCase
  def self.engine_under_test
    OKF::Bundle::Search::Index
  end
  include EngineConformance
end

class ScanEngineTest < SearchCase
  def self.engine_under_test
    OKF::Bundle::Search::Scan
  end
  include EngineConformance
end

class RegisteredEnginesConformTest < SearchCase
  COVERED = [ IndexEngineTest, ScanEngineTest ].map(&:engine_under_test).freeze

  test "every registered engine has a conformance class — registering is not enough" do
    assert_equal OKF::Bundle::Search.engines.sort_by(&:id), COVERED.sort_by(&:id),
      "an engine in the registry with no conformance class is how two engines start disagreeing about what a match is"
  end

  test "every registered engine answers the whole duck type" do
    OKF::Bundle::Search.engines.each do |engine|
      assert_kind_of Symbol, engine.id
      assert_kind_of Array, engine.capabilities
      assert_empty engine.capabilities - OKF::Bundle::Search::CAPABILITIES,
        "#{engine.id} declares a capability outside the vocabulary, so nothing can route on it"
      assert_includes [ true, false ], engine.available?
    end
  end

  test "the built-ins between them cover every capability the vocabulary names" do
    offered = OKF::Bundle::Search.engines.flat_map(&:capabilities).uniq

    assert_empty OKF::Bundle::Search::CAPABILITIES - offered,
      "a capability no built-in offers is a promise the base gem cannot keep on its own"
  end
end
