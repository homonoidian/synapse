require "crsfml"
require "lch"

require "./ext"

require "./line"
require "./buffer"
require "./controller"
require "./view"
require "./draggable"
require "./dimension"
require "./icon_view"
require "./buffer_editor"
require "./buffer_editor_row"
require "./buffer_editor_column"
require "./input_field"
require "./input_field_row"
require "./keyword_input"
require "./param_input"
require "./rule_header"
require "./rule_code_row"
require "./rule_editor"
require "./keyword_rule_header"
require "./keyword_rule_editor"
require "./birth_rule_editor"
require "./period_input"
require "./heartbeat_input"
require "./heartbeat_rule_header"
require "./heartbeat_rule_editor"
require "./protocol_name_editor"
require "./protocol_editor"

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

class LabelInstant
  getter timestamp : Int64
  getter caption : String

  def initialize(@timestamp, @caption)
  end
end

class LabelState
  property caption = ""

  def capture
    LabelInstant.new(Time.local.to_unix, @caption)
  end
end

class LabelView
  include IView

  property position = SF.vector2f(0, 0)
  property? active = false

  def initialize
    @text = SF::Text.new("", font, font_size)
  end

  def font
    FONT
  end

  def font_size
    11
  end

  def padding
    SF.vector2f(0, 0)
  end

  def origin
    position + padding
  end

  def size
    @text.size + padding*2
  end

  def text_color
    SF::Color::White
  end

  def background_color
    SF::Color::Transparent
  end

  def update(instant : LabelInstant)
    @text.string = instant.caption
  end

  def draw(target, states)
    unless background_color.a.zero?
      bgrect = SF::RectangleShape.new
      bgrect.fill_color = background_color
      bgrect.position = position
      bgrect.size = size
      bgrect.draw(target, states)
    end

    @text.position = origin
    @text.fill_color = text_color
    @text.draw(target, states)
  end
end

class MenuItemInstant < LabelInstant
  def initialize(instant : LabelInstant)
    initialize(instant.timestamp, instant.caption)
  end
end

class MenuItemState < LabelState
  def capture
    MenuItemInstant.new(super)
  end
end

class MenuItemView < LabelView
  include IRemixIconView

  # Holds the character used as the icon.
  property icon = Icon::GenericAdd

  def padding
    SF.vector2f(10, 3)
  end

  def origin
    super + SF.vector2f(icon_span_x, icon_font_size // 4)
  end

  def size
    super + SF.vector2f(icon_span_x, icon_font_size // 4)
  end

  def icon_color
    text_color
  end

  def text_color
    active? ? SF::Color.new(0xbb, 0xd3, 0xff) : SF::Color.new(0xCC, 0xCC, 0xCC)
  end

  def draw(target, states)
    super

    icon = icon_text
    icon.position = position + padding
    icon.draw(target, states)
  end
end

class MenuInstant < DimensionInstant(MenuItemInstant)
end

class MenuState < DimensionState(MenuItemState)
  def append(caption : String)
    item = append
    item.caption = caption
    item
  end

  def capture : MenuInstant
    MenuInstant.new(Time.local.to_unix, @states.map(&.capture), @selected)
  end

  def new_substate_for(index : Int) : MenuItemState
    MenuItemState.new
  end
end

class MenuView < DimensionView(MenuItemView, MenuInstant, MenuItemInstant)
  def initialize
    super

    @icons = [] of String
  end

  def append_icon(icon : String)
    @icons << icon
  end

  def ord_at(point : SF::Vector2)
    @views.each_with_index do |view, index|
      return index if view.includes?(point)
    end
  end

  def new_subview_for(index : Int) : MenuItemView
    item = MenuItemView.new
    if icon = @icons[index]?
      item.icon = icon
    end
    item
  end

  def wsheight
    0
  end

  def arrange_cons_pair(left : MenuItemView, right : MenuItemView)
    right.position = SF.vector2f(
      left.position.x,
      left.position.y + left.size.y + wsheight
    )
  end

  # Specifies snap grid step for size.
  def snapstep
    SF.vector2f(0, 0)
  end

  def size : SF::Vector2f
    return snapstep if @views.empty?

    SF.vector2f(
      @views.max_of(&.size.x),
      @views.sum(&.size.y) + wsheight * (@views.size - 1)
    ).snap(snapstep)
  end

  # Specifies the background color of this editor as a whole.
  def background_color
    SF::Color.new(0x31, 0x31, 0x31)
  end

  # Specifies the color of the outline of this editor.
  def outline_color
    active? ? SF::Color.new(0x43, 0x51, 0x80) : SF::Color.new(0x3f, 0x3f, 0x3f)
  end

  def active_item_background
    SF::Color.new(0x33, 0x42, 0x70)
  end

  def draw(target, states)
    bg_rect = SF::RectangleShape.new
    bg_rect.position = position
    bg_rect.size = size
    bg_rect.fill_color = background_color
    bg_rect.outline_thickness = 2
    bg_rect.outline_color = outline_color
    bg_rect.draw(target, states)

    @views.each do |item|
      if item.active?
        item_bg_rect = SF::RectangleShape.new
        item_bg_rect.position = item.position
        item_bg_rect.size = SF.vector2f(size.x, item.size.y)
        item_bg_rect.fill_color = active_item_background
        item_bg_rect.draw(target, states)
      end

      item.draw(target, states)
    end
  end
end

class Menu
  include IController

  def initialize(@state : MenuState, @view : MenuView)
    @focused = @view.active?

    refresh
  end

  def append(item : String, icon : String?)
    @state.append(item)
    @view.append_icon(icon)
    refresh
  end

  def on_accepted(item : MenuItemState)
    puts "Clicked: #{item.capture.inspect}"
  end

  def includes?(point : SF::Vector2)
    @view.includes?(point)
  end

  def handle!(event : SF::Event::MouseMoved)
    if ord = @view.ord_at(SF.vector2f(event.x, event.y))
      @view.active = true
      @state.to_nth(ord)
    else
      @view.active = false
    end

    refresh
  end

  def handle!(event : SF::Event::KeyPressed)
    case event.code
    when .up?    then @state.to_prev(circular: true)
    when .down?  then @state.to_next(circular: true)
    when .home?  then @state.to_first
    when .end?   then @state.to_last
    when .enter? then on_accepted(@state.selected)
    else
      return
    end

    refresh
  end

  def handle!(event : SF::Event::MouseButtonPressed)
    unless ord = @view.ord_at(SF.vector2f(event.x, event.y))
      blur
      return
    end

    @state.to_nth(ord)
    refresh

    on_accepted(@state.selected)
  end

  def focus
    @view.active = true

    super
  end

  def blur
    @view.active = false

    super
  end

  def refresh
    @view.update(@state.capture)
  end

  def clear
  end

  def handle!(event : SF::Event)
  end

  def draw(target, states)
    @view.draw(target, states)
  end
end

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
# [x] BirthRuleEditor
# [x] HeartbeatRuleEditor
# [x] extract RuleEditor
# [x] ProtocolEditor
# [ ] Assign each new RuleEditor view a custom color ???
# [ ] Use variation of this color for e.g. active outline ???
# [ ] Have a little circle on top left of RuleEditors with this color ???
#
# "Rule world" is a world of itself (like Tank). You can drag rules
# around, create new ones using double-click and a menu, etc.
#
# Implement simple menu with the following items:
# # [x] The "protocol" pane allows to specify the name of the protocol
#     or leave it unnamed.
# [x] "Birth rule"
#     creates a birth rule onclick [ ]
# [x] "Heartbeat rule"
#     creates a heartbeat rule onclick [ ]
# [x] "Keyword rule"
#     creates a keyword rule onclick [ ]
# [x] "Protocol"
#     creates a protocol pane onclick [ ]
# [ ] GraphState, GraphView to record & display connections
#     between rules & protocols
# [ ] CellEditorState, CellEditorView, CellEditor
#   [ ] Open menu on double click
#   [ ] When the user starts typing with nothing selected, create
#       a new keyword rule and redirect input there
#   [ ] When dragging *from* this little circle, draw an arrow pointing
#       at where the cursor is. The arrow is of the custom color
#   [ ] When cursor is released over empty space, create a
#      "protocol" pane there which will have the arrow connected
#       to it.
#   [ ] If the cursor is over an existing protocol pane, draw a halo
#       around it.
#   [ ] If the cursor is released over an existing protocol pane,
#       connect the arrow to it.
#
# [ ] Fill a ProtocolCollection from UI, set UI from a ProtocolCollection
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
# [ ] When clicking on a cell in app, instead of showing code
#     editor show a zoomed out "window" into this rule world.
#     On click, expand it and redirect events there.
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

ked_state = KeywordRuleEditorState.new
ked_view = KeywordRuleEditorView.new
ked_view.position = SF.vector2f(100, 200)
ked = KeywordRuleEditor.new(ked_state, ked_view)

bed_state = BirthRuleEditorState.new
bed_view = BirthRuleEditorView.new
bed_view.position = SF.vector2f(100, 300)
bed = BirthRuleEditor.new(bed_state, bed_view)

hed_state = HeartbeatRuleEditorState.new
hed_view = HeartbeatRuleEditorView.new
hed_view.position = SF.vector2f(100, 400)
hed = HeartbeatRuleEditor.new(hed_state, hed_view)

ped_state = ProtocolEditorState.new
ped_view = ProtocolEditorView.new
ped_view.position = SF.vector2f(10, 10)
ped = ProtocolEditor.new(ped_state, ped_view)

menu_state = MenuState.new

menu_view = MenuView.new
menu_view.position = SF.vector2f(300, 10)
menu = Menu.new(menu_state, menu_view)
menu.append("New birth rule", Icon::BirthRule)
menu.append("New keyword rule", Icon::KeywordRule)
menu.append("New heartbeat rule", Icon::HeartbeatRule)
menu.append("New protocol", Icon::Protocol)

window = SF::RenderWindow.new(SF::VideoMode.new(800, 600), title: "App", settings: SF::ContextSettings.new(depth: 24, antialiasing: 8))
window.framerate_limit = 60

focus = nil

while window.open?
  if focus && !focus.focused? # element blurred itself
    focus = nil
  end

  while event = window.poll_event
    case event
    when SF::Event::Closed then window.close
    when SF::Event::MouseButtonPressed
      case SF.vector2f(event.x, event.y)
      when .in?(ked)
        if !focus.same?(ked) && ((focus.nil? || focus.can_blur?) && ked.can_focus?)
          focus.try &.blur
          ked.focus
          focus = ked
        end
      when .in?(bed)
        if !focus.same?(bed) && ((focus.nil? || focus.can_blur?) && bed.can_focus?)
          focus.try &.blur
          bed.focus
          focus = bed
        end
      when .in?(hed)
        if !focus.same?(hed) && ((focus.nil? || focus.can_blur?) && hed.can_focus?)
          focus.try &.blur
          hed.focus
          focus = hed
        end
      when .in?(ped)
        if !focus.same?(ped) && ((focus.nil? || focus.can_blur?) && ped.can_focus?)
          focus.try &.blur
          ped.focus
          focus = ped
        end
      when .in?(menu)
        if !focus.same?(menu) && ((focus.nil? || focus.can_blur?) && menu.can_focus?)
          focus.try &.blur
          menu.focus
          focus = menu
        end
      else
        focus.try &.blur
        focus = nil
      end
    end
    focus.try &.handle(event)
  end
  window.clear(SF::Color.new(0x21, 0x21, 0x21))
  window.draw(ked)
  window.draw(bed)
  window.draw(hed)
  window.draw(ped)
  window.draw(menu)
  window.display
end
