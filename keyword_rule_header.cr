# Keyword rule header state. Allows the user to enter the keyword
# and parameters of a `KeywordSignature`.
class KeywordRuleHeaderState < RuleHeaderState
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
