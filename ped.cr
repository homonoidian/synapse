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

def code_input(position)
  view = BufferEditorView.new
  view.position = position

  BufferEditor.new(BufferEditorState.new, view)
end

focused_field = 0
focused_code = false

WS_WIDTH          =  6 # FIXME: compute from font
LINE_HEIGHT       = 14
CODE_INSET_SPACES =  2
CODE_INSET_X      = WS_WIDTH * CODE_INSET_SPACES
CODE_MARGIN_Y     = 16

origin = SF.vector2f(100, 100)

fields = [
  keyword_input(origin),
]
fields[focused_field][0].focus

code_field = code_input(origin + SF.vector2f(CODE_INSET_X, LINE_HEIGHT + CODE_MARGIN_Y))
code_field.blur

while window.open?
  while event = window.poll_event
    case event
    when SF::Event::Closed then window.close
    when SF::Event::KeyPressed
      if focused_code
        case event.code
        when .up?
          if code_field.@state.at_first_line?
            # move up to fields
            next unless (from = code_field).can_blur?

            # compute column in code
            code_col = code_field.@state.column + CODE_INSET_SPACES

            # go thru fields until all of them are exhausted or
            # code column is found
            #
            # the following assumes fields are single-line!
            field_idx = 0
            field_inner_idx = nil
            to_index = fields.size - 1
            fields.each_with_index do |(field, _, state), index|
              next_field_idx = field_idx + state.size + 1 # plus whitespace between field
              if next_field_idx > code_col
                to_index = index
                field_inner_idx = code_col - field_idx
                break
              end
              field_idx = next_field_idx
            end

            next unless (to = fields[to_index][0]).can_focus?

            if field_inner_idx
              to.@state.seek(field_inner_idx)
            else
              to.@state.to_end_index
            end

            from.blur
            to.focus

            focused_code = false
            focused_field = to_index
            next
          end
        end
        # continue to default handler
      else
        case event.code
        when .down?
          # FIXME: use default handler (see below) instead of nexting over it
          next unless (from = fields[focused_field][0]).can_blur?
          next unless (to = code_field).can_focus?

          # Compute column in fields

          col = 0
          fields.each_with_index do |(_, _, state), index|
            break if index >= focused_field
            col += state.size + 1
          end

          col += fields[focused_field][0].@state.column
          col -= CODE_INSET_SPACES

          col = Math.min(to.@state.line.size, col)
          to.@state.to_column(col)

          from.blur
          to.focus

          focused_code = true
          next
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

            if prev
              from.@state.to_start_index
              to.@state.to_end_index
            else
              from.@state.to_end_index
              to.@state.to_start_index
            end

            from.blur
            to.focus
            focused_field = to_index

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
    end

    if focused_code
      code_field.handle(event)
    else
      fields[focused_field][0].handle(event)
      fields.each_cons_pair do |(a, av), (b, bv)|
        av_corner = av.position + av.size
        bv.position = SF.vector2f(av_corner.x + WS_WIDTH, bv.position.y)
      end
    end
  end

  window.clear(SF::Color.new(0x21, 0x21, 0x21))

  padding = SF.vector2f(8, 3)
  min_code_size = SF.vector2f(128, 64)

  # draw bgrect

  bgrect = SF::RectangleShape.new
  bgrect.position = origin - padding

  computed_size = SF.vector2f(
    Math.max(fields.sum(&.[1].size.x) + WS_WIDTH * fields.size, code_field.@view.size.x + WS_WIDTH * CODE_INSET_SPACES*2),
    fields.max_of(&.[1].size.y) + LINE_HEIGHT + CODE_MARGIN_Y + code_field.@view.size.y
  ) + padding*2
  bgrect.outline_thickness = 1
  bgrect.outline_color = SF::Color.new(0x61, 0x61, 0x61)
  bgrect.size = SF.vector2f(
    Math.max(computed_size.x, min_code_size.x),
    Math.max(computed_size.y, min_code_size.y),
  )

  bgrect.fill_color = SF::Color.new(0x32, 0x32, 0x32)
  window.draw(bgrect)

  fields.each do |field, _|
    window.draw(field)
  end

  # draw code field rect
  code_bgrect = SF::RectangleShape.new
  code_bgrect.position = SF.vector2f(origin.x - padding.x, code_field.@view.position.y - CODE_MARGIN_Y//2)
  code_bgrect.fill_color = SF::Color.new(0x32, 0x32, 0x32)
  code_bgrect.size = bgrect.size - SF.vector2f(0, fields.max_of(&.[1].size.y) + CODE_MARGIN_Y + 5)
  window.draw(code_bgrect)

  sep = SF::RectangleShape.new
  sep.position = code_bgrect.position - SF.vector2f(0, 2)
  sep.size = SF.vector2f(bgrect.size.x, 1)
  sep.fill_color = SF::Color.new(0x61, 0x61, 0x61)
  window.draw(sep)

  window.draw(code_field)

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
# TODO: show underline only under the active field [x]
# TODO: start with only the keyword field [x]
# TODO: add source code buffer editor below [x]
# TODO: pressing down moves into the buffer editor [x]
# TODO: pressing up at the first line of the buffer editor moves into fields [x]
# TODO: pressing up moves to field "over" the cursor [x]
# TODO: pressing down moves to character "under" the field + cursor [x]
#
# TODO: draw gray-ish (lifted) background rect outline [x]
# TODO: draw background rect under buffer with outline (2 x lifted) [x]
# TODO: draw accept/reject buttons to the left of the background [ ]
# TODO: alternatively (via a flag), draw green rect to the left of the background [ ]
# TODO: do not draw buffer if it is empty and the user didn't navigate into it yet [ ]
#
# TODO: extract component RuleEditor, KeywordRuleEditor, HeartbeatRuleEditor etc. [ ]
#       make them take and talk to and edit corresponding rule objects
# TODO: highlight keyword in different color even when unfocused [ ]
# TODO: support validation of input fields with red highlight and pointy error [ ]
#   keyword -- anything
#   params -- letters followed by symbols
#   heartbeat time -- digits followed by s or ms
#
# TODO: draw multiple RuleEditors in a row [ ]
# TODO: when Up is pressed at start in ruleeditor, move to the ruleeditor above [ ]
# TODO: when Down is pressed at end in ruleeditor, move to the ruleeditor below [ ]
# TODO: there is always an empty rule at the bottom.when it is filled a new empty
# rule is created below [ ]
# TODO: extract component ProtocolEditor [ ]
# TODO: make ProtocolEditor take and talk to and edit Protocol [ ]
#
# TODO: merge into app.cr ProtocolEditor (rename what's currently there to CellEditor)[ ]
# TODO: design considerations [ ]
