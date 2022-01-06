require './prelude'

stream_start_event = ->
  event: 'stream_start'
stream_end_event = ->
  event: 'stream_end'
document_start_event = (explicit=false)->
  event: 'document_start'
  explicit: explicit
  version: null
document_end_event = (explicit=false)->
  event: 'document_end'
  explicit: explicit
mapping_start_event = (flow=false)->
  event: 'mapping_start'
  flow: flow
mapping_end_event = ->
  event: 'mapping_end'
sequence_start_event = (flow=false)->
  event: 'sequence_start'
  flow: flow
sequence_end_event = ->
  event: 'sequence_end'
scalar_event = (style, value)->
  event: 'scalar'
  style: style
  value: value
alias_event = (name)->
  event: 'alias'
  name: name
cache = (text)->
  text: text

global.Receiver = class Receiver
  constructor: ->
    @event = []
    @cache = []

  send: (event)->
    if @receive
      @receive event
    else
      @event.push event

  add: (event)->
    if event.event?
      if @anchor?
        event.anchor = @anchor
        delete @anchor
      if @tag?
        event.tag = @tag
        delete @tag
    @push event
    return event


  push: (event)->
    if @cache.length
      _.last(@cache).push event
    else
      if event.event.match /(mapping_start|sequence_start|scalar)/
        @check_document_start()
      @send event

  cache_up: (event=null)->
    @cache.push []
    @add event if event?

  cache_down: (event=null)->
    events = @cache.pop() or FAIL 'cache_down'
    @push e for e in events
    @add event if event?

  cache_drop: ->
    events = @cache.pop() or FAIL 'cache_drop'
    return events

  check_document_start: ->
    return unless @document_start
    @send @document_start
    delete @document_start
    @document_end = document_end_event()

  check_document_end: ->
    return unless @document_end
    @send @document_end
    delete @document_end
    @tag_map = {}
    @document_start = document_start_event()

  #----------------------------------------------------------------------------
  try_yaml_stream: ->
    @add stream_start_event()
    @tag_map = {}
    @document_start = document_start_event()
    delete @document_end

  got_yaml_stream: ->
    @check_document_end()
    @add stream_end_event()

  got_yaml_version_number: (o)->
    die "Multiple %YAML directives not allowed" \
      if @document_start.version?
    @document_start.version = o.text

  got_tag_handle: (o)->
    @tag_handle = o.text

  got_tag_prefix: (o)->
    @tag_map[@tag_handle] = o.text

  got_document_start_indicator: ->
    @check_document_end()
    @document_start.explicit = true

  got_document_end_indicator: ->
    if @document_end?
      @document_end.explicit = true
    @check_document_end()

  got_flow_mapping_start: -> @add mapping_start_event true
  got_flow_mapping_end:   -> @add mapping_end_event()

  got_flow_sequence_start: -> @add sequence_start_event true
  got_flow_sequence_end:   -> @add sequence_end_event()

  try_block_mapping: -> @cache_up mapping_start_event()
  got_block_mapping: -> @cache_down mapping_end_event()
  not_block_mapping: -> @cache_drop()

  try_block_sequence_context: -> @cache_up sequence_start_event()
  got_block_sequence_context: -> @cache_down sequence_end_event()
  not_block_sequence_context: ->
    event = @cache_drop()[0]
    @anchor = event.anchor
    @tag = event.tag

  try_compact_mapping: -> @cache_up mapping_start_event()
  got_compact_mapping: -> @cache_down mapping_end_event()
  not_compact_mapping: -> @cache_drop()

  try_compact_sequence: -> @cache_up sequence_start_event()
  got_compact_sequence: -> @cache_down sequence_end_event()
  not_compact_sequence: -> @cache_drop()

  try_flow_pair: -> @cache_up mapping_start_event true
  got_flow_pair: -> @cache_down mapping_end_event()
  not_flow_pair: -> @cache_drop()

  try_block_mapping_implicit_entry: -> @cache_up()
  got_block_mapping_implicit_entry: -> @cache_down()
  not_block_mapping_implicit_entry: -> @cache_drop()

  try_block_mapping_explicit_entry: -> @cache_up()
  got_block_mapping_explicit_entry: -> @cache_down()
  not_block_mapping_explicit_entry: -> @cache_drop()

  try_flow_mapping_empty_key_entry: -> @cache_up()
  got_flow_mapping_empty_key_entry: -> @cache_down()
  not_flow_mapping_empty_key_entry: -> @cache_drop()

  got_flow_plain_scalar: (o)->
    text = o.text
      .replace(/(?:[\ \t]*\r?\n[\ \t]*)/g, "\n")
      .replace(/(\n)(\n*)/g, (m...)-> if m[2].length then m[2] else ' ')
    @add scalar_event 'plain', text

  got_single_quoted_scalar: (o)->
    text = o.text[1...-1]
      .replace(/(?:[\ \t]*\r?\n[\ \t]*)/g, "\n")
      .replace(/(\n)(\n*)/g, (m...)-> if m[2].length then m[2] else ' ')
      .replace(/''/g, "'")
    @add scalar_event 'single', text

  unescapes =
    '\\\\': '\\'
    '\r\n': '\n'
    '\\ ': ' '
    '\\"': '"'
    '\\/': '/'
    '\\b': '\b'
    '\\n': '\n'
    '\\r': '\r'
    '\\t': '\t'
    '\\\t': '\t'

  end1 = String(/// (?: \\ \r?\n[\ \t]* ) ///)[1..-2]
  end2 = String(/// (?: [\ \t]*\r?\n[\ \t]* ) ///)[1..-2]
  hex  = '[0-9a-fA-F]'
  hex2 = String(/// (?: \\x ( #{hex}{2} ) ) ///)[1..-2]
  hex4 = String(/// (?: \\u ( #{hex}{4} ) ) ///)[1..-2]
  hex8 = String(/// (?: \\U ( #{hex}{8} ) ) ///)[1..-2]

  got_double_quoted_scalar: (o)->
    @add scalar_event('double', o.text[1...-1]
      .replace ///
        (?:
          \r\n
        | #{end1}
        | #{end2}+
        | #{hex2}
        | #{hex4}
        | #{hex8}
        | \\\\
        | \\\t
        | \\[\ bnrt"/]
        )
      ///g, (m)->
        if n = m.match ///^ #{hex2} $///
          return String.fromCharCode(parseInt(n[1], 16))
        if n = m.match ///^ #{hex4} $///
          return String.fromCharCode(parseInt(n[1], 16))
        if n = m.match ///^ #{hex8} $///
          return String.fromCharCode(parseInt(n[1], 16))
        if m.match ///^ #{end1} $///
          return ''
        if m.match ///^ #{end2}+ $///
          u = m
            .replace(/// #{end2} ///, '')
            .replace(/// #{end2} ///g, '\n')
          return u || ' '
        if u = unescapes[m]
          return u
        XXX m
    )

  got_empty_line: ->
    @add cache('') if @in_scalar
  got_literal_scalar_line_content: (o)->
    @add cache(o.text)
  try_block_literal_scalar: ->
    @in_scalar = true
    @cache_up()
  got_block_literal_scalar: ->
    delete @in_scalar
    lines = @cache_drop()
    lines.pop() if lines.length > 0 and lines[lines.length - 1].text == ''
    lines = lines.map (l)-> "#{l.text}\n"
    text = lines.join ''
    t = @parser.state_curr().t
    if t == 'CLIP'
      text = text.replace /\n+$/, "\n"
    else if t == 'STRIP'
      text = text.replace /\n+$/, ""
    else if not text.match /\S/
      text = text.replace /\n(\n+)$/, "$1"
    @add scalar_event 'literal', text
  not_block_literal_scalar: ->
    delete @in_scalar
    @cache_drop()

  got_folded_scalar_text: (o)->
    @add cache o.text

  got_folded_scalar_spaced_text: (o)->
    @add cache o.text

  try_block_folded_scalar: ->
    @in_scalar = true
    @cache_up()

  got_block_folded_scalar: ->
    delete @in_scalar
    lines = @cache_drop().map (l)-> l.text
    text = lines.join "\n"
    text = text.replace /^(\S.*)\n(?=\S)/gm, "$1 "
    text = text.replace /^(\S.*)\n(\n+)/gm, "$1$2"
    text = text.replace /^([\ \t]+\S.*)\n(\n+)(?=\S)/gm, "$1$2"
    text += "\n"

    t = @parser.state_curr().t
    if t == 'CLIP'
      text = text.replace /\n+$/, "\n"
      text = '' if text == "\n"
    else if t == 'STRIP'
      text = text.replace /\n+$/, ""
    @add scalar_event 'folded', text

  not_block_folded_scalar: ->
    delete @in_scalar
    @cache_drop()

  got_empty_node: -> @add scalar_event 'plain', ''

  not_block_collection_properties: ->
    delete @tag
    delete @anchor

  not_block_collection_anchor: ->
    delete @anchor

  not_block_collection_tag: ->
    delete @tag

  got_anchor_property: (o)->
    @anchor = o.text[1..]

  got_tag_property: (o)->
    tag = o.text
    if m = tag.match /^!<(.*)>$/
      @tag = m[1]
    else if m = tag.match /^!!(.*)/
      prefix = @tag_map['!!']
      if prefix?
        @tag = prefix + tag[2..]
      else
        @tag = "tag:yaml.org,2002:#{m[1]}"
    else if m = tag.match(/^(!.*?!)/)
      prefix = @tag_map[m[1]]
      if prefix?
        @tag = prefix + tag[(m[1].length)..]
      else
        die "No %TAG entry for '#{prefix}'"
    else if (prefix = @tag_map['!'])?
      @tag = prefix + tag[1..]
    else
      @tag = tag
    @tag = @tag.replace /%([0-9a-fA-F]{2})/g, (m...)->
      String.fromCharCode parseInt m[1], 16

  got_alias_node: (o)-> @add alias_event o.text[1..]

# vim: sw=2:
