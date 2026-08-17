# frozen_string_literal: true

require "test_helper"

class ProTestTop < OKF::Pro::TestCase
  # Date is used in nearly every module but used to arrive only transitively,
  # through the okf gem's yaml load — a dependency reordering its own requires
  # would have turned every Date.today into a NameError in session-context and
  # the CI verbs, which sit outside the dispatch rescue. In a test process the
  # constant is loaded either way, so absence is unobservable at runtime; the
  # pin is a source assertion, deliberately.
  def test_the_library_requires_date_itself
    src = OKF::Pro.read_text(File.expand_path("../../lib/okf/pro.rb", __dir__))

    assert_match(/^require "date"$/, src)
  end

  # "10.0.0" < "2.4" is true lexicographically, so a string compare would
  # refuse every edit on a future Ruby 10 — the floor gate blocking a
  # perfectly capable interpreter, which is its own failure.
  def test_the_ruby_floor_is_compared_as_a_version_not_a_string
    src = OKF::Pro.read_text(File.expand_path("../../lib/okf/pro.rb", __dir__))

    assert_match(/Gem::Version\.new\(RUBY_VERSION\) < Gem::Version\.new\("2\.4"\)/, src)
    refute Gem::Version.new("10.0.0") < Gem::Version.new("2.4")
  end

  # The floor the library refuses under and the floor the gemspec declares are
  # two statements of one fact, in files nothing else joins. They drifted the
  # moment this gem left the prototype: the checker carried 2.7 (inherited from
  # okf-mcp, whose floor comes from a dependency this gem does not have) into a
  # gemspec that says 2.4, so on a 2.5 host every gate would have refused every
  # edit while `gem install` reported the gem supported.
  def test_the_declared_floor_and_the_enforced_floor_are_the_same
    src = OKF::Pro.read_text(File.expand_path("../../lib/okf/pro.rb", __dir__))
    enforced = src[/Gem::Version\.new\(RUBY_VERSION\) < Gem::Version\.new\("([\d.]+)"\)/, 1]
    declared = Dir.chdir(File.expand_path("../..", __dir__)) do
      Gem::Specification.load(File.expand_path("../../okf-pro.gemspec", __dir__))
    end.required_ruby_version

    refute_nil enforced, "lib/okf/pro.rb no longer states a floor at all"
    assert declared.satisfied_by?(Gem::Version.new(enforced)),
      "the gemspec admits Rubies (#{declared}) that the checker refuses to run on (#{enforced}): " \
      "the gem installs and then every gate refuses every edit."
  end
end
