# A time-ordered snapshot of `MenuState`.
#
# Allows clients to implement an undo/redo system independent
# of `MenuState`.
#
# Also allows clients to peek into `MenuState` at discrete time
# steps for change-awareness.
class MenuInstant < DimensionInstant(MenuItemInstant)
end

# Logic and state for a menu: a list of menu items where one item
# can be selected.
class MenuState < DimensionState(MenuItemState)
  def append(caption : String)
    item = append
    item.update(caption)
    item
  end

  def capture : MenuInstant
    MenuInstant.new(Time.local.to_unix, @states.map(&.capture), @selected)
  end

  def new_substate_for(index : Int) : MenuItemState
    MenuItemState.new
  end
end

# View for a menu: a vertical list of menu items where one item can
# be selected.
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

# Controller for a vertical menu: a list of items where an item can be
# selected by clicking on it, or by using Up/Down keys and pressing
# the Enter key.
class Menu
  include IController

  def initialize(@state : MenuState, @view : MenuView)
    @focused = @view.active?
    @listeners = [] of MenuItemInstant ->

    refresh
  end

  # Notifies the listeners that the given item *instant* was accepted.
  private def on_accepted(instant : MenuItemInstant)
    @listeners.each &.call(instant)
  end

  # Moves this menu to the given *x*, *y* coordinate.
  def move(x : Number, y : Number)
    @view.position = SF.vector2f(x, y).round

    refresh
  end

  # Appends an *item* to this menu, with an optional *icon* character.
  def append(item : String, icon : String?)
    @state.append(item)
    @view.append_icon(icon)
    refresh
  end

  # Registers *callback* for invokation when a menu item is accepted.
  def accepted(&callback : MenuItemInstant ->)
    @listeners << callback
  end

  # Opens this menu at the given *x*, *y* coordinate.
  def open(x : Number, y : Number)
    move(x, y)
    focus
    @view.active = false
    refresh
  end

  # Closes this menu.
  def close
    blur
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
    return unless focused?

    @view.draw(target, states)
  end
end
