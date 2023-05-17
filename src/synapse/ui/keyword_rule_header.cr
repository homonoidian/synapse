# Keyword rule header state. Allows the user to enter the keyword
# and parameters of a `KeywordSignature`.
class KeywordRuleHeaderState < RuleHeaderState
  # Returns the keyword. May be empty is the user didn't enter it yet.
  def keyword : String
    @states[0].as(KeywordInputState).string
  end

  def to_rule_signature : RuleSignature
    params = @states[1..].map { |state| state.as(ParamInputState).string }

    KeywordRuleSignature.new(keyword, params)
  end

  def new_substate_for(index : Int)
    index == 0 ? KeywordInputState.new : ParamInputState.new
  end
end

# Keyword rule header view.
#
# Simply that: displays the keyword and parameters of the header
# using `KeywordInputView` and `ParamInputView` subviews.
class KeywordRuleHeaderView < RuleHeaderView
  def new_subview_for(index : Int)
    index == 0 ? KeywordInputView.new : ParamInputView.new
  end
end
