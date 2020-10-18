require './prelude'

global.TestReceiver = class TestReceiver
  constructor: ->
    @event = []
    @cache = []

  add: (type, value)->
    event = type: type
    if type?
      if @marker?
        event.marker = @marker
        delete @marker
      if @anchor?
        event.anchor = @anchor
        delete @anchor
      if @tag?
        event.tag = @tag
        delete @tag
    if value?
      event.value = value
    @push event
    return event

  push: (event)->
    if @cache.length
      _.last(@cache).push event
    else
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

  cache_get: (type)->
    last = _.last @cache
    return \
      last &&
      last[0] &&
      last[0].type == type &&
      last[0]

  send: (event)->
    @event.push event

  output: ->
    output = @event.map (e)->
      value = (if e.value? then e.value else '')
        .replace(/\\/g, '\\\\')
        .replace(/\n/g, '\\n')
        .replace(/\t/g, '\\t')
        .replace(/\ $/g, '<SPC>')
      e.type +
        (if e.marker then " #{e.marker}" else '') +
        (if e.anchor then " #{e.anchor}" else '') +
        (if e.tag then " <#{e.tag}>" else '') +
        (if e.value then " #{value}" else '') +
        "\n"
    output.join ''

  try__l_yaml_stream: ->
    @add '+STR'
    @tag_map = {}
  got__l_yaml_stream: -> @add '-STR'

  got__c_tag_handle: (o)->
    @tag_handle = o.text
  got__ns_tag_prefix: (o)->
    @tag_map[@tag_handle] = o.text

  try__l_bare_document: ->
    parser = @parser
    if parser.input[parser.pos..].match /^(\s|\#.*\n?)*\S/
      @add '+DOC'
  got__l_bare_document: -> @cache_up '-DOC'
  got__c_directives_end: -> @marker = '---'
  got__c_document_end: ->
    if event = @cache_get '-DOC'
      event.marker = '...'
      @cache_down()
  not__c_document_end: ->
    if @cache_get '-DOC'
      @cache_down()

  got__c_flow_mapping__all__x7b: -> @add '+MAP {}'
  got__c_flow_mapping__all__x7d: -> @add '-MAP'

  got__c_flow_sequence__all__x5b: -> @add '+SEQ []'
  got__c_flow_sequence__all__x5d: -> @add '-SEQ'

  try__l_block_mapping: -> @cache_up '+MAP'
  got__l_block_mapping: -> @cache_down '-MAP'
  not__l_block_mapping: -> @cache_drop()

  try__l_block_sequence: -> @cache_up '+SEQ'
  got__l_block_sequence: -> @cache_down '-SEQ'
  not__l_block_sequence: ->
    event = @cache_drop()[0]
    @anchor = event.anchor
    @tag = event.tag

  try__ns_l_compact_mapping: -> @cache_up '+MAP'
  got__ns_l_compact_mapping: -> @cache_down '-MAP'
  not__ns_l_compact_mapping: -> @cache_drop()

  try__ns_l_compact_sequence: -> @cache_up '+SEQ'
  got__ns_l_compact_sequence: -> @cache_down '-SEQ'
  not__ns_l_compact_sequence: -> @cache_drop()

  try__ns_flow_pair: -> @cache_up('+MAP {}')
  got__ns_flow_pair: -> @cache_down('-MAP')
  not__ns_flow_pair: -> @cache_drop()

  try__ns_l_block_map_implicit_entry: -> @cache_up()
  got__ns_l_block_map_implicit_entry: -> @cache_down()
  not__ns_l_block_map_implicit_entry: -> @cache_drop()

  try__c_l_block_map_explicit_entry: -> @cache_up()
  got__c_l_block_map_explicit_entry: -> @cache_down()
  not__c_l_block_map_explicit_entry: -> @cache_drop()

  not__s_l_block_collection__all__rep__all: ->
    delete @anchor
    delete @tag

  try__c_ns_flow_map_empty_key_entry: -> @cache_up()
  got__c_ns_flow_map_empty_key_entry: -> FAIL 'got__c_ns_flow_map_empty_key_entry'
  not__c_ns_flow_map_empty_key_entry: -> @cache_drop()

  got__ns_plain: (o)->
    text = o.text
      .replace(/(?:[\ \t]*\r?\n[\ \t]*)/g, "\n")
      .replace(/(\n)(\n*)/g, (m...)-> if m[2].length then m[2] else ' ')
    @add '=VAL', ":#{text}"

  got__c_single_quoted: (o)->
    text = o.text[1...-1]
      .replace(/(?:[\ \t]*\r?\n[\ \t]*)/g, "\n")
      .replace(/(\n)(\n*)/g, (m...)-> if m[2].length then m[2] else ' ')
      .replace(/''/g, "'")
    @add '=VAL', "'#{text}"

  got__c_double_quoted: (o)->
    text = o.text[1...-1]
      .replace(/(?:[\ \t]*\r?\n[\ \t]*)/g, "\n")
      .replace(/\\\n[\ \t]*/g, '')
      .replace(/(\n)(\n*)/g, (m...)-> if m[2].length then m[2] else ' ')
      .replace(/\\(["\/])/g, "$1")
      .replace(/\\ /g, ' ')
      .replace(/\\t/g, "\t")
      .replace(/\\n/g, "\n")
      .replace(/\\\\/g, '\\')
    @add '=VAL', "\"#{text}"

  got__l_empty: ->
    @add null, '' if @in_scalar
  got__l_nb_literal_text__all__rep2: (o)->
    @add null, o.text
  try__c_l_literal: ->
    @in_scalar = true
    @cache_up()
  got__c_l_literal: ->
    delete @in_scalar
    lines = @cache_drop()
    lines = lines.map (l)-> "#{l.value}\n"
    text = lines.join ''
    t = @parser.state_curr().t
    if t == 'clip'
      text = text.replace /\n+$/, "\n"
    else if t == 'strip'
      text = text.replace /\n+$/, ""
    @add '=VAL', "|#{text}"
  not__c_l_literal: ->
    delete @in_scalar
    @cache_drop()

  got__ns_char: (o)->
    @ns_char = o.text if @in_scalar
  got__s_nb_folded_text__all__rep: (o)->
    @add null, "#{@ns_char}#{o.text}"
  try__c_l_folded: ->
    @in_scalar = true
    @cache_up()
  got__c_l_folded: ->
    delete @in_scalar
    lines = @cache_drop()
    lines = lines.map (l)-> "#{l.value}\n"
    text = lines.join ''
    text = text.replace /([^\n])(\n+)(?=.)/g, (m...)->
      len = m[2].length - 1
      return m[1] + (if len then _.repeat("\n", len) else ' ')
    t = @parser.state_curr().t
    if t == 'clip'
      text = text.replace /\n+$/, "\n"
    else if t == 'strip'
      text = text.replace /\n+$/, ""
    @add '=VAL', ">#{text}"
  not__c_l_folded: ->
    delete @in_scalar
    @cache_drop()

  got__e_scalar: -> @add '=VAL', ':'

  got__c_ns_anchor_property: (o)-> @anchor = o.text

  got__c_ns_tag_property: (o)->
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
    else if (prefix = @tag_map['!'])?
      @tag = prefix + tag[1..]
    else
      @tag = tag
    @tag = @tag.replace /%([0-9a-fA-F]{2})/g, (m...)->
      String.fromCharCode parseInt m[1], 16

  got__c_ns_alias_node: (o)-> @add '=ALI', o.text

# vim: sw=2:
