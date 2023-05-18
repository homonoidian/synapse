abstract class AgentEditor
  # Returns the title of this editor: normally this is the
  # name of the rule/protocol.
  def title? : String?
  end

  # Fills this editor with the captured content of the given *source* editor.
  abstract def drain(source : self)
end
