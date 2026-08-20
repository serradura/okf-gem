# frozen_string_literal: true

require "test_helper"

# The dormancy window is stated twice — as `Budget::DORMANCY_DAYS`, which decides
# when the question is asked, and in the skill's Rule 3, which is where a person
# or an agent reads what the rule is. One of those is operative and the other is
# what everybody believes, so they have to be the same number.
#
# The comment over the constant used to claim the window was "tuned in the
# skill's Rule 3". It was not: the skill states it in prose, and an adopter who
# changed it there would see nothing happen while the gate kept asking on the old
# window. The fix was not a knob nobody asked for — it was this test.
class DormancyWindowTest < OKF::Pro::TestCase
  test "the window the skill states is the window the budget enforces" do
    stated = skill_rule("okf-pro-dormancy-window")[/\*\*(\d+) working days\*\*/, 1]

    refute_nil stated, "the skill no longer states the dormancy window in working days — " \
                       "if the wording changed, change this pattern with it rather than deleting the pin"
    assert_equal OKF::Pro::Budget::DORMANCY_DAYS, stated.to_i,
      "the skill teaches a #{stated}-day window and Budget enforces " \
      "#{OKF::Pro::Budget::DORMANCY_DAYS}: the rule people read is not the rule that runs"
  end
end
