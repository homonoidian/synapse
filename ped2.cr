require "crsfml"

require "./ext"

require "./line"
require "./buffer"
require "./controller"
require "./dimension"
require "./buffer_editor"
require "./buffer_editor_row"
require "./buffer_editor_column"
require "./input_field"
require "./input_field_row"
require "./keyword_input"
require "./param_input"
require "./rule_header"
require "./rule_code_row"
require "./keyword_rule_header"
require "./keyword_rule_editor"

FONT        = SF::Font.from_memory({{read_file("./fonts/code/scientifica.otb")}}.to_slice)
FONT_BOLD   = SF::Font.from_memory({{read_file("./fonts/code/scientificaBold.otb")}}.to_slice)
FONT_ITALIC = SF::Font.from_memory({{read_file("./fonts/code/scientificaItalic.otb")}}.to_slice)

FONT.get_texture(11).smooth = false
FONT_BOLD.get_texture(11).smooth = false
FONT_ITALIC.get_texture(11).smooth = false

FONT_UI        = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Regular.ttf")}}.to_slice)
FONT_UI_MEDIUM = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Medium.ttf")}}.to_slice)
FONT_UI_BOLD   = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Bold.ttf")}}.to_slice)

# ----------------------------------------------------------

# ----------------------------------------------------------

# TODO:
# [ ] Have a column of RuleEditors (RuleEditorColumn) where the
#     last RuleEditor is going to be the "insertion point" -- if
#     you type there a new empty rule editor appears below, and
#     this one is yours to change.
#
# [ ] Backspace in an empty ruleeditor should remove it unless it
#     is the last (insertion point) rule editor.
#
# ------- Alternatively:
#
# [ ] BirthRuleEditor
# [ ] HeartbeatRuleEditor
# [ ] ProtocolEditor
# [ ] Assign each new RuleEditor a custom color
# [ ] Have a little circle on top left of RuleEditors with this color
#
# "Rule world" is a world of itself (like Tank). You can drag rules
# around, create new ones using double-click and a menu, etc.
#
# [ ] Implement simple menu with the following items:
#     "Birth rule" (creates a birth rule onclick)
#     "Heartbeat rule" (creates a heartbeat rule onclick)
#     "Keyword rule" (creates a keyword rule onclick)
#     "Protocol" (creates a protocol pane onclick)
# [ ] Open this menu on double click
# [ ] When the user starts typing with nothing selected, create
#     a new keyword rule and redirect input there
# [ ] When dragging *from* this little circle, draw an arrow pointing
#     at where the cursor is. The arrow is of the custom color
# [ ] When cursor is released over empty space, create a
#     "protocol" pane there which will have the arrow connected
#      to it.
# [ ] The "protocol" pane allows to specify the name of the protocol
#     or leave it unnamed.
# [ ] If the cursor is over an existing protocol pane, draw a halo
#     around it.
# [ ] If the cursor is released over an existing protocol pane,
#     connect the arrow to it.
#
# [ ] Rules can send and receive *targeted*, internal messages. I.e.,
#     rule 'mouse' sends internal message 'foo', a single internal
#     vesicle is emitted, *pathfinds* to message 'foo', triggers it.
#
#
#                           e
#                           l
#                           c
#                           i
# +-------------+           s
# |             |  emit     e
# | Rule 'mouse'| +---->    V  XXXpathfind
# |             |                X
# +-------------+                X
#                                X
#                                X
#                                X         +-------------+
#                                X   trig  |             |
#                                XXX +---> |  Rule 'foo' |
#                                          |             |
#                                          +-------------+
#
#
# -------
#
# [ ] Implement HeartbeatRule, BirthRuleEditor. ??? how to create them?
#
# [ ] RuleEditor can submit its RuleEditorState to an existing
#     Rule object on C-s, can fill its RuleEditorState from an
#     existing Rule object when not focused, when focused can
#     observe an existing RuleObject and show sync/out of sync
#     circle.
#
# [ ] Implement ProtocolEditor which is basically a big-smooth-
#     font editable name (a subset of InputField) followed by
#     RuleEditorColumn.
#
# [ ] ProtocolEditor can submit its ProtocolEditorState to an existing
#     Protocol object on C-s, can observe & fill its ProtocolEditorState
#     from an existing Protocol object when not focused, alternatively
#     (when focused) show sync/out of sync circle.
#
# [ ] Replace the current Protocol/Rule/ProtocolEditor system
#     with this new one.

it_state = KeywordRuleEditorState.new
it_view = KeywordRuleEditorView.new
it_view.active = true
it_view.position = SF.vector2f(100, 200)

it = KeywordRuleEditor.new(it_state, it_view)

window = SF::RenderWindow.new(SF::VideoMode.new(800, 600), title: "App")
window.framerate_limit = 60

###

state1 = BufferEditorRowState.new
state1.append
view1 = BufferEditorRowView.new
view1.position = SF.vector2f(0, 50)
view1.active = true
row1 = BufferEditorRow.new(state1, view1)

while window.open?
  while event = window.poll_event
    case event
    when SF::Event::Closed then window.close
    end
    it.handle(event)
  end
  window.clear(SF::Color.new(0x21, 0x21, 0x21))
  window.draw(it)
  window.display
end
