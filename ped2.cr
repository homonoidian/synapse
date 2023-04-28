require "crsfml"
require "lch"
require "./ext"
require "./stream"

module CellEditorEntity # FIXME: ???
  delegate :position, :position=, to: @view

  def size
    @view.size
  end

  def move(position : SF::Vector2)
    @view.position = position

    refresh
  end

  def lift
  end

  def drop
  end
end

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
    @listeners = [] of MenuItemInstant ->

    refresh
  end

  delegate :active=, :active?, to: @view

  def move(x : Number, y : Number)
    @view.position = SF.vector2f(x, y)

    refresh
  end

  def append(item : String, icon : String?)
    @state.append(item)
    @view.append_icon(icon)
    refresh
  end

  def accepted(&callback : MenuItemInstant ->)
    @listeners << callback
  end

  def on_accepted(instant : MenuItemInstant)
    @listeners.each &.call(instant)
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
    when .enter? then on_accepted(@state.selected.capture)
    else
      return
    end

    refresh
  end

  def handle!(event : SF::Event::MouseButtonReleased)
    return unless ord = @view.ord_at(SF.vector2f(event.x, event.y))

    @state.to_nth(ord)
    refresh

    on_accepted(@state.selected.capture)
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

class CellEditor
  include SF::Drawable

  @menu : Menu
  @selected : Int32?

  def initialize
    @mouse = SF.vector2f(0, 0)
    @menu = new_menu
    @entities = [] of CellEditorEntity
    @vertices = [] of {ProtocolEditor, RuleEditor}
    @dragging = Stream({CellEditorEntity, DragEvent}).new
    @dragging.each { |subject, event| on_motion(subject, event) }
  end

  def append(entity : CellEditorEntity)
    @entities << entity
  end

  def connect(protocol : ProtocolEditor, rule : RuleEditor)
    @vertices << {protocol, rule}
  end

  def can_connect?(entity, subject, point)
    point.in?(entity) && !@vertices.any?({entity, subject})
  end

  def on_motion(subject, event : DragEvent::Grabbed)
  end

  def on_motion(subject, event : DragEvent::Dragged)
    subject.lift

    if subject.is_a?(ProtocolEditor)
      subject.halo = false
      return
    end

    @entities.each do |entity|
      # Halo the protocol editor below the moved entity (if any).
      next unless entity.is_a?(ProtocolEditor)

      entity.halo = can_connect?(entity, subject, @mouse)
    end
  end

  def on_motion(subject, event : DragEvent::Dropped)
    subject.drop

    if subject.is_a?(ProtocolEditor)
      subject.halo = false
      return
    end

    return unless subject.is_a?(RuleEditor)

    connected = false
    subject_index = @entities.size - 1

    @entities.each_with_index do |entity, index|
      if entity.same?(subject)
        subject_index = index
      end

      next unless entity.is_a?(ProtocolEditor)

      if can_connect?(entity, subject, @mouse)
        connect(entity, subject)
        connected = true
      end

      entity.halo = false
    end

    return unless connected

    # Pick up again
    lift(subject_index, grab: true)
  end

  def new_menu
    menu = Menu.new(MenuState.new, MenuView.new)
    menu.append("New birth rule", Icon::BirthRule)
    menu.append("New keyword rule", Icon::KeywordRule)
    menu.append("New heartbeat rule", Icon::HeartbeatRule)
    menu.append("New protocol", Icon::Protocol)
    menu.accepted(&->on_menu_item_accepted(MenuItemInstant))
    menu
  end

  def new_birth_rule
    view = BirthRuleEditorView.new
    rule = BirthRuleEditor.new(BirthRuleEditorState.new, view)
    rule
  end

  def new_keyword_rule
    view = KeywordRuleEditorView.new
    rule = KeywordRuleEditor.new(KeywordRuleEditorState.new, view)
    rule
  end

  def new_heartbeat_rule
    view = HeartbeatRuleEditorView.new

    rule = HeartbeatRuleEditor.new(HeartbeatRuleEditorState.new, view)
    rule
  end

  def new_protocol
    view = ProtocolEditorView.new

    rule = ProtocolEditor.new(ProtocolEditorState.new, view)
    rule
  end

  def empty?
    @entities.empty?
  end

  def selected?
    @menu.focused? ? @menu : @selected.try { |index| @entities[index] }
  end

  def activate(index : Int32)
    focus = selected?
    entity = @entities[index]

    return unless focus.nil? || focus.can_blur?
    return unless entity.can_focus?

    focus.try &.blur
    entity.focus

    # Swap top and selected indices.
    @entities.swap(index, @entities.size - 1)

    @selected = @entities.size - 1
  end

  def activate(index : Nil)
    focus = selected?
    return unless focus.nil? || focus.can_blur?

    focus.try &.blur
    @selected = nil
  end

  # Activate the entity at *index* and grabs it by the midpoint.
  def lift(index : Int, grab = false)
    subject = @entities[index]

    activate(index)

    if grab
      subject.move(@mouse - subject.size/2)
      subject.grab(@mouse)
      subject.refresh
    else
      subject.move(@mouse)
    end
  end

  def forward(event : SF::Event)
    return unless entity = selected?

    entity.handle(event)
  end

  def put_editor(editor : CellEditorEntity, grab = true)
    @entities << editor

    # Forward dragging of the editor to the common dragging stream.
    editor.dragging
      .map { |event| {editor.as(CellEditorEntity), event} }
      .notifies(@dragging)

    lift(@entities.size - 1, grab)
  end

  def on_menu_item_accepted(instant : MenuItemInstant)
    case instant.caption
    when "New birth rule"
      editor = new_birth_rule
    when "New keyword rule"
      editor = new_keyword_rule
    when "New heartbeat rule"
      editor = new_heartbeat_rule
    when "New protocol"
      editor = new_protocol
    else
      return
    end

    # Blur the menu and add the editor to the list of entities.
    # Note that order matters here!
    @menu.blur

    put_editor(editor)
  end

  def handle(event : SF::Event::MouseButtonPressed)
    focus = selected?
    @mouse = mouse = SF.vector2f(event.x, event.y)

    if focus && mouse.in?(focus)
      forward(event)
      return
    end

    case event.button
    when .left?
      @menu.blur

      (0...@entities.size).reverse_each do |index|
        entity = @entities.unsafe_fetch(index)

        next unless mouse.in?(entity)

        activate(index)
        forward(event)
        return
      end

      activate(nil)
    when .right?
      @menu.move(mouse.x + 5, mouse.y + 5)
      @menu.focus
      @menu.active = false
      @menu.refresh
    end
  end

  def handle(event : SF::Event::TextEntered)
    if selected?
      forward(event)
      return
    end

    chr = event.unicode.chr
    return unless chr.printable?

    editor = new_keyword_rule

    put_editor(editor, grab: false)

    forward(event)
  end

  def handle(event : SF::Event::MouseMoved)
    @mouse = SF.vector2f(event.x, event.y)

    forward(event)
  end

  def handle(event : SF::Event)
    forward(event)
  end

  def to_protocol_collection
    collection = ProtocolCollection.new

    @vertices.each do |from, to| # FIXME: this ignores empty protocols
      from.append(to.to_rule, to: collection)
    end

    collection
  end

  def append(collection : ProtocolCollection)
    collection.append(into: self)
  end

  def draw(target, states)
    vertices = SF::VertexArray.new(SF::Lines, 2 * @vertices.size)

    @vertices.each do |from, to|
      vertices.append SF::Vertex.new(from.position + from.size/2, SF::Color.new(0x43, 0x51, 0x80))
      vertices.append SF::Vertex.new(to.position + to.size/2, SF::Color.new(0x43, 0x51, 0x80))
    end

    vertices.draw(target, states)

    @entities.each &.draw(target, states)

    if @menu.focused?
      @menu.draw(target, states)
    end
  end
end

abstract class RuleSignature
end

class HeartbeatRuleSignature < RuleSignature
  def initialize(@period : Time::Span?)
  end

  def append_rule(code : String, into editor : CellEditor)
    state = HeartbeatRuleEditorState.new

    if period = @period
      header = state.selected # Rule header
      header.split(backwards: false)
      header.selected.insert("#{period.milliseconds}ms")
    end

    state.split(backwards: false)
    state.selected.selected.insert(code)

    rule = HeartbeatRuleEditor.new(state, HeartbeatRuleEditorView.new)
    editor.append(rule)

    rule
  end
end

class KeywordRuleSignature < RuleSignature
  def initialize(@keyword : String, @params : Array(String))
  end

  def append_rule(code : String, into editor : CellEditor)
    state = KeywordRuleEditorState.new

    header = state.selected # Rule header
    header.selected.insert(@keyword)

    @params.each do |param|
      header.split(backwards: false)
      header.selected.insert(param)
    end

    state.split(backwards: false)
    state.selected.selected.insert(code)

    rule = KeywordRuleEditor.new(state, KeywordRuleEditorView.new)
    editor.append(rule)

    rule
  end
end

abstract class Rule
  def initialize(@code : String)
  end
end

class BirthRule < Rule
  def append(into editor : CellEditor)
    state = BirthRuleEditorState.new
    state.code?.try &.insert(@code)
    rule = BirthRuleEditor.new(state, BirthRuleEditorView.new)
    editor.append(rule)

    rule
  end
end

class SignatureRule < Rule
  def initialize(@signature : RuleSignature, code)
    super(code)
  end

  def append(into editor : CellEditor)
    @signature.append_rule(@code, into: editor)
  end
end

class Protocol
  def initialize(@uid : UUID, @name : String?)
    @rules = [] of Rule
  end

  def append(rule : Rule)
    @rules << rule
  end

  def append(*, into editor : CellEditor)
    #
    # Create and append a protocol editor.
    #
    state = ProtocolEditorState.new(@uid)
    if name = @name
      state.selected.insert(name)
    end

    protocol = ProtocolEditor.new(state, ProtocolEditorView.new)

    editor.append(protocol)

    #
    # Create and append rule editors.
    #
    @rules.each do |rule|
      appended = rule.append(into: editor)

      editor.connect(protocol, appended)
    end
  end
end

class ProtocolCollection
  def initialize
    @protocols = {} of UUID => Protocol
  end

  def summon(id : UUID, name : String?)
    @protocols[id] ||= Protocol.new(id, name)
  end

  def assign(id : UUID, protocol : Protocol)
    @protocols[id] = protocol
  end

  def append(*, into editor : CellEditor)
    @protocols.each_value &.append(into: editor)
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
#     creates a birth rule onclick [x]
# [x] "Heartbeat rule"
#     creates a heartbeat rule onclick [x]
# [x] "Keyword rule"
#     creates a keyword rule onclick [x]
# [x] "Protocol"
#     creates a protocol pane onclick [x]
# [x] Open menu on RMB
# [x] When the user starts typing with nothing selected, create
#     a new keyword rule and redirect input there
# [x] allow to connect rules to protocols
# [x] fix no shadow after release over protocol
# [ ] allow rectangular select of editors: motion, deletion.
# [ ] allow to undo/redo editor motion, deletion *when nothing is focused*.
# [ ] add a way to display errors in rules
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

window = SF::RenderWindow.new(SF::VideoMode.new(800, 600), title: "App", settings: SF::ContextSettings.new(depth: 24, antialiasing: 8))
window.framerate_limit = 60

protocols = ProtocolCollection.new
foo = protocols.summon(UUID.random, "Greeter")
foo.append(SignatureRule.new(KeywordRuleSignature.new("greet", ["name", "age"]), "print(name)"))

editor = CellEditor.new
editor.append(protocols)

texture = SF::RenderTexture.new(600, 400)

while window.open?
  while event = window.poll_event
    case event
    when SF::Event::Closed then window.close
    when SF::Event::KeyPressed
      if event.code.escape?
        coll = editor.to_protocol_collection
        editor = CellEditor.new
        editor.append(coll)
      end
    end
    editor.handle(event)
  end

  texture.clear(SF::Color.new(0x21, 0x21, 0x21))
  texture.draw(editor)
  texture.display

  window.clear(SF::Color.new(0xff, 0xff, 0xff))
  window.draw(SF::Sprite.new texture.texture)
  window.display
end
