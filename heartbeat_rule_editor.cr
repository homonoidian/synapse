# State for a heartbeat rule editor. Almost identical to
# `KeywordRuleEditorState`, hence the subclassing.
class HeartbeatRuleEditorState < KeywordRuleEditorState
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
class HeartbeatRuleEditor
  include MonoBufferController(HeartbeatRuleEditorState, HeartbeatRuleEditorView)

  include BufferEditorHandler
  include BufferEditorRowHandler
  include KeywordRuleEditorHandler
  include RuleEditorHandler
  include CellEditorEntity
end
