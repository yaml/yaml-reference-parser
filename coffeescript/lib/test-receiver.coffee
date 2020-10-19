require './prelude'
require './receiver'

event_map =
  stream_start: '+STR'
  stream_end: '-STR'
  document_start: '+DOC'
  document_end: '-DOC'
  mapping_start: '+MAP'
  mapping_end: '-MAP'
  sequence_start: '+SEQ'
  sequence_end: '-SEQ'
  scalar: '=VAL'
  alias: '=ALI'

style_map =
  plain: ':'
  single: "'"
  double: '"'
  literal: '|'
  folded: '>'

global.TestReceiver = class TestReceiver extends Receiver

  output: ->
    list = @event.map (e)->
      type = event_map[e.event]
      event = [type]
      event.push '---' if type == '+DOC' and e.explicit
      event.push '...' if type == '-DOC' and e.explicit
      event.push '{}' if type == '+MAP' and e.flow
      event.push '[]' if type == '+SEQ' and e.flow
      event.push "&#{e.anchor}" if e.anchor
      event.push "<#{e.tag}>" if e.tag
      event.push "*#{e.name}" if e.name
      if e.value?
        style = style_map[e.style]
        value = e.value
          .replace(/\\/g, '\\\\')
          .replace(/\n/g, '\\n')
          .replace(/\t/g, '\\t')
          .replace(/\ $/g, '<SPC>')
        event.push "#{style}#{value}"
      event.join(' ') + "\n"
    list.join ''

# vim: sw=2:
