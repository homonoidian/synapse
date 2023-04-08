require "uuid"
require "crsfml"

require "./ext"

require "./line"
require "./buffer"
require "./buffer_editor"
require "./input_field"

FONT        = SF::Font.from_memory({{read_file("./fonts/code/scientifica.otb")}}.to_slice)
FONT_BOLD   = SF::Font.from_memory({{read_file("./fonts/code/scientificaBold.otb")}}.to_slice)
FONT_ITALIC = SF::Font.from_memory({{read_file("./fonts/code/scientificaItalic.otb")}}.to_slice)

FONT_UI        = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Regular.ttf")}}.to_slice)
FONT_UI_MEDIUM = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Medium.ttf")}}.to_slice)
FONT_UI_BOLD   = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Bold.ttf")}}.to_slice)

FONT.get_texture(11).smooth = false
FONT_BOLD.get_texture(11).smooth = false
FONT_ITALIC.get_texture(11).smooth = false

window = SF::RenderWindow.new(SF::VideoMode.new(800, 600), title: "Protocol Editor")
window.framerate_limit = 60

def keyword_input(position)
  # TODO: use InputField child instead of exposing state, view
  state = InputFieldState.new

  view = InputFieldView.new
  view.position = position

  {InputField.new(state, view), view, state}
end

def param_input(position)
  # TODO: use InputField child instead of exposing state, view
  state = InputFieldState.new

  view = InputFieldView.new
  view.position = position

  {InputField.new(state, view), view, state}
end

focused_field = 0

WS_WIDTH = 6 # FIXME: compute from font

origin = SF.vector2f(100, 100)

fields = [
  keyword_input(origin),
  param_input(SF.vector2f(160, 100)),
  param_input(SF.vector2f(200, 100)),
]
fields[focused_field][0].focus

while window.open?
  while event = window.poll_event
    case event
    when SF::Event::Closed then window.close
    when SF::Event::KeyPressed
      case event.code
      when .tab?
        to_index = (focused_field + (event.shift ? -1 : 1))
        next if to_index < 0 # NOTE: but this shouldn't use the default handler!

        if to_index >= fields.size
          field = fields[focused_field][1]
          corner = field.position + field.size
          fields << param_input(SF.vector2f(corner.x + WS_WIDTH, field.position.y))
          to_index = fields.size - 1 # clamp
        end

        # FIXME: use default handler (see below) instead of nexting over it
        next unless (from = fields[focused_field][0]).can_blur?
        next unless (to = fields[to_index][0]).can_focus?

        from.blur
        to.focus
        focused_field = to_index

        if event.shift
          from.@state.to_start_index
          to.@state.to_end_index
        else
          from.@state.to_end_index
          to.@state.to_start_index
        end

        next # NOTE: but this shouldn't use the default handler!
      when .backspace?
        field = fields[focused_field]

        if focused_field > 0 && field[2].at_start_index? # this & previous must be parameter
          to_index = focused_field - 1

          # first check whether it wants to unfocus and previous
          # wants to focus
          next unless (from = fields[focused_field][0]).can_blur? # FIXME: use default handler
          next unless (to = fields[to_index][0]).can_focus?       # FIXME: use default handler

          f, _, state = field

          # buffer stores with newline at the end (always), use
          # rchop to omit it
          curr_string = state.string

          # Clear existing field
          f.clear
          f.blur

          # Remove it
          fields.delete_at(focused_field)

          focused_field = to_index

          # Append
          prev_state = fields[focused_field][2]
          prev_state.update! { prev_state.string + curr_string }

          to.focus

          next
        end
      when .delete?
        field = fields[focused_field]

        if 0 <= focused_field < fields.size - 1 && field[2].at_end_index? # this & next must be parameter
          next_index = focused_field + 1

          # first check whether it wants to unfocus and next
          # wants to focus
          next unless (from = fields[next_index][0]).can_blur? # FIXME: use default handler

          nxt, _, next_state = fields[next_index]

          # buffer stores with newline at the end (always), use
          # rchop to omit it
          next_string = next_state.string

          # Clear next field
          nxt.clear
          nxt.blur

          # Remove it
          fields.delete_at(next_index)

          # focused field is already = next_index then

          # Prepend
          curr_state = fields[focused_field][2]
          # buffer stores with newline at the end (always), use
          # rchop to omit it
          curr_state.update! { curr_state.string + next_string }

          fields[focused_field][0].refresh

          next
        end
      when .left?, .right?
        prev = event.code.left?

        if (prev && fields[focused_field][2].at_start_index?) || (!prev && fields[focused_field][2].at_end_index?)
          # NOTE: almost the same as TAb/shift-tab but doesn't create anything
          to_index = (focused_field + (prev ? -1 : 1))
          # FIXME: use default handler (see below) instead of nexting over it
          next unless to_index.in?(0...fields.size)
          next unless (from = fields[focused_field][0]).can_blur?
          next unless (to = fields[to_index][0]).can_focus?

          from.blur
          to.focus
          focused_field = to_index

          if prev
            from.@state.to_start_index
            to.@state.to_end_index
          else
            from.@state.to_end_index
            to.@state.to_start_index
          end

          next # NOTE: but this shouldn't use the default handler!
        end
      when .enter?
        unless focused_field == 0 && event.shift # can't insert before keyword
          ins_index = focused_field + (event.shift ? 0 : 1)

          # FIXME: use default handler (see below) instead of nexting over it
          next unless (from = fields[focused_field][0]).can_blur?

          from_state = fields[focused_field][2]

          field = fields[focused_field][1]
          corner = field.position + field.size
          # insert with dummy position
          fields.insert(ins_index, to = param_input(SF.vector2f(0, 0)))
          # recompute positions
          fields.each_cons_pair do |(a, av), (b, bv)|
            av_corner = av.position + av.size
            bv.position = SF.vector2f(av_corner.x + WS_WIDTH, av.position.y)
          end

          to, _, to_state = to

          if event.shift
            # shift-enter: move before cursor in from_buf to to_buf
            to_state.update! { from_state.before_cursor }
            from_state.delete_before_cursor
          else
            # enter: move after cursor in from_buf to to_buf
            to_state.update! { from_state.after_cursor }
            from_state.delete_after_cursor
          end

          from.blur
          focused_field = ins_index

          if event.shift
            from.@state.to_start_index
            to.@state.to_end_index
          else
            from.@state.to_end_index
            to.@state.to_start_index
          end
          to.focus

          next # NOTE: but this shouldn't use the default handler!
        end
      when .home?, .end?
        if event.code.home?
          cond = fields[focused_field][2].at_start_index?
          to_index = 0
        else
          cond = fields[focused_field][2].at_end_index?
          to_index = fields.size - 1
        end

        if cond
          # FIXME: use default handler (see below) instead of nexting over it
          next unless (from = fields[focused_field][0]).can_blur?
          next unless (to = fields[to_index][0]).can_focus?

          from.blur
          to.focus
          focused_field = to_index
        end
      end
    end

    fields[focused_field][0].handle(event)
    fields.each_cons_pair do |(a, av), (b, bv)|
      av_corner = av.position + av.size
      bv.position = SF.vector2f(av_corner.x + WS_WIDTH, bv.position.y)
    end
  end

  window.clear(SF::Color.new(0x21, 0x21, 0x21))
  fields.each do |field, _|
    window.draw(field)
  end
  window.display
end

# TODO: highlight current field in blue [x]
# TODO: tab at the end inserts a field [x]
# TODO: backspace at start of field deletes the field and appends its content into previous field [x]
# TODO: delete at end of field deletes the field and prepends its content into next field [x]
# TODO: pressing left at start moves into the field to the left [x]
# TODO: pressing right at end moves into the field to the right [x]
# TODO: enter inserts a field after the current field with moved content after cursor of current [x]
# TODO: shift-enter inserts a field before the current field with moved content before cursor of current [x]
# TODO: home at start moves to first field [x]
# TODO: end at end moves to last field [x]
#
# TODO: add big source code buffer editor below [ ]
# TODO: pressing down moves into the buffer editor [ ]
# TODO: pressing up at the first line of the buffer editor moves to field "over" the cursor [ ]
# TODO: start with only the keyword field [ ]
# TODO: draw gray-ish (lifted) background rect with focused/blurred gray outline [ ]
# TODO: draw background rect under buffer editor with sync (ok blue/error red) outline (2 x lifted) [ ]
# TODO: extract component KeywordRuleEditor, HeartbeatRuleEditor etc.
# TODO: support validation of input fields with red highlight and pointy error [ ]
#   keyword -- anything
#   params -- letters followed by symbols
#   heartbeat time -- digits followed by s or ms
#
