# Represents a row of input field states.
class InputFieldRowState < BufferEditorRowState
  def new_substate_for(index : Int)
    InputFieldState.new
  end
end

# Represents a row of input field views.
class InputFieldRowView < BufferEditorRowView
  def new_subview_for(index : Int)
    InputFieldView.new
  end
end
