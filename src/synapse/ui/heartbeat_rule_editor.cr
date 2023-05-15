# State for a heartbeat rule editor. Almost identical to
# `KeywordRuleEditorState`, hence the subclassing.
class HeartbeatRuleEditorState < KeywordRuleEditorState
  def period?
    header = @states[0].as(HeartbeatRuleHeaderState)
    header.period?
  end

  def to_rule(signature : RuleSignature, code : String) : Rule
    HeartbeatRule.new(signature, code)
  end

  def new_substate_for(index : Int)
    {HeartbeatRuleHeaderState, RuleCodeRowState}[index].new
  end
end

# View for a heartbeat rule editor. Looks almost identical
# to `KeywordRuleEditorView`, hence the subclassing.
class HeartbeatRuleEditorView < KeywordRuleEditorView
  def new_subview_for(index : Int)
    {HeartbeatRuleHeaderView, RuleCodeRowView}[index].new
  end
end

# Heartbeat rule editor allows to create and edit a heartbeat rule.
#
# Heartbeat rules are rules whose expression happens on every tick,
# or after a period if this period is specified.
class HeartbeatRuleEditor < RuleEditor
  include MonoBufferController(HeartbeatRuleEditorState, HeartbeatRuleEditorView)

  include BufferEditorHandler
  include BufferEditorRowHandler
  include KeywordRuleEditorHandler
  include CellEditorEntity
  include RuleEditorHandler

  def title? : String?
    @state.period?
  end

  def to_rule : Rule
    @state.to_rule
  end

  def drain(source : self)
    @state.drain(source.@state.capture)
  end
end
