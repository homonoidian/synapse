record EntityDragEvent, entity : CellEditorEntity, event : DragEvent

class CellEditor
  include SF::Drawable

  @menu : Menu
  @selected : Int32?

  def initialize
    @mouse = SF.vector2f(0, 0)
    @menu = new_menu
    @entities = [] of CellEditorEntity
    @links = [] of {ProtocolEditor, RuleEditor}
    @dragging = Stream(EntityDragEvent).new
    @dragging.each { |event| on_motion(event.entity, event.event) }
    @view = SF::View.new
    @view.reset(SF.float_rect(0, 0, size.x.to_i, size.y.to_i))
  end

  def mouse
    delta = @view.center - size/2

    mouse = @mouse
    mouse.x += delta.x.to_i
    mouse.y += delta.y.to_i
    mouse
  end

  def size
    SF.vector2f(600, 400)
  end

  def append(entity : CellEditorEntity)
    @entities << entity
  end

  def connect(protocol : ProtocolEditor, rule : RuleEditor)
    @links << {protocol, rule}
  end

  def can_connect?(entity, subject, point)
    point.in?(entity) && !@links.any?({entity, subject})
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

      entity.halo = can_connect?(entity, subject, mouse)
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

      if can_connect?(entity, subject, mouse)
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
      subject.move(mouse - subject.size/2)
      subject.grab(mouse)
      subject.refresh
    else
      subject.move(mouse)
    end
  end

  def forward(event : SF::Event::MouseMoveEvent | SF::Event::MouseButtonEvent)
    return unless entity = selected?

    delta = @view.center - size/2
    event.x += delta.x.to_i
    event.y += delta.y.to_i

    entity.handle(event)
  end

  def forward(event : SF::Event)
    return unless entity = selected?

    entity.handle(event)
  end

  def put_editor(editor : CellEditorEntity, grab = true)
    @entities << editor

    # Forward dragging of the editor to the common dragging stream.
    editor.dragging
      .map { |event| EntityDragEvent.new(editor, event) }
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

  @lmb : SF::Vector2f?

  def handle(event : SF::Event::MouseButtonPressed)
    focus = selected?
    @mouse = SF.vector2f(event.x, event.y)

    if focus && mouse.in?(focus)
      forward(event)
      return
    end

    case event.button
    when .left?
      @menu.close

      (0...@entities.size).reverse_each do |index|
        entity = @entities.unsafe_fetch(index)

        next unless mouse.in?(entity)

        activate(index)
        forward(event)
        return
      end

      activate(nil)

      @lmb = mouse
    when .right?
      @menu.open(mouse.x + 5, mouse.y + 5)
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

    unless lmb = @lmb
      forward(event)
      return
    end

    view = @view
    view.move((lmb - mouse).to_i)
    @lmb = mouse
  end

  def handle(event : SF::Event::MouseButtonReleased)
    unless @lmb
      forward(event)
      return
    end

    @lmb = nil
  end

  def handle(event : SF::Event)
    forward(event)
  end

  def to_protocol_collection
    collection = ProtocolCollection.new

    @links.each do |from, to| # FIXME: this ignores empty protocols
      from.append(to.to_rule, to: collection)
    end

    collection
  end

  def append(collection : ProtocolCollection)
    collection.append(into: self)
  end

  def draw(target, states)
    target.view = @view

    links = SF::VertexArray.new(SF::Lines, 2 * @links.size)

    @links.each do |from, to|
      links.append SF::Vertex.new(from.position + from.size/2, SF::Color.new(0x43, 0x51, 0x80))
      links.append SF::Vertex.new(to.position + to.size/2, SF::Color.new(0x43, 0x51, 0x80))
    end

    links.draw(target, states)

    @entities.each &.draw(target, states)

    @menu.draw(target, states)
  end
end

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
# [x] When clicking on a cell in app, instead of showing code
#     editor show a "window" into this rule world.
