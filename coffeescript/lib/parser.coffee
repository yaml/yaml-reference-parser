###
This is a parser class. It has a parse() method and parsing primitives for the
grammar. It calls methods in the receiver class, when a rule matches:
###

require './prelude'
require './grammar'

TRACE = Boolean ENV.TRACE

global.Parser = class Parser extends Grammar

  constructor: (receiver)->
    super()
    receiver.parser = @
    @receiver = receiver
    @pos = 0
    @end = 0
    @state = []
    @trace_num = 0
    @trace_line = 0
    @trace_on = true
    @trace_off = 0
    @trace_info = ['', '', '']

  parse: (@input)->
    @end = @input.length

    @trace_on = not @trace_start() if TRACE

    try
      ok = @call @TOP
      @trace_flush()
    catch err
      @trace_flush()
      throw err

    throw "Parser failed" if not ok
    throw "Parser finished before end of input" \
      if @pos < @end

    return true

  state_curr: ->
    @state[@state.length - 1] ||
      name: null
      doc: false
      lvl: 0
      beg: 0
      end: 0
      m: null
      t: null

  state_prev: ->
    @state[@state.length - 2]

  state_push: (name)->
    curr = @state_curr()

    @state.push
      name: name
      doc: curr.doc
      lvl: curr.lvl + 1
      beg: @pos
      end: null
      m: curr.m
      t: curr.t

  state_pop: ->
    child = @state.pop()
    curr = @state_curr()
    return unless curr?
    curr.beg = child.beg
    curr.end = @pos

  call: (func, type='boolean')->
    args = []
    [func, args...] = func if isArray func

    if isNumber(func) or isString(func)
      return func

    FAIL "Bad call type '#{typeof_ func}' for '#{func}'" \
      unless isFunction func

    trace = func.trace ?= func.name

    @state_push(trace)

    @trace_num++
    @trace '?', trace, args if TRACE

    if func.name == 'l_bare_document'
      @state_curr().doc = true

    args = args.map (a)=>
      if isArray(a) then @call(a, 'any') else \
      if isFunction(a) then a() else \
      a

    pos = @pos
    @receive func, 'try', pos

    value = func.apply(@, args)
    while isFunction(value) or isArray(value)
      value = @call value

    FAIL "Calling '#{trace}' returned '#{typeof_ value}' instead of '#{type}'" \
      if type != 'any' and typeof_(value) != type

    @trace_num++
    if type != 'boolean'
      @trace '>', value if TRACE
    else
      if value
        @trace '+', trace if TRACE
        @receive func, 'got', pos
      else
        @trace 'x', trace if TRACE
        @receive func, 'not', pos

    @state_pop()
    return value

  receive: (func, type, pos)->
    func.receivers ?= @make_receivers()
    receiver = func.receivers[type]
    return unless receiver

    receiver.call @receiver,
      text: @input[pos...@pos]
      state: @state_curr()
      start: pos

  make_receivers: ->
    i = @state.length
    names = []
    while i > 0 and not((n = @state[--i].name).match /_/)
      if m = n.match /^chr\((.)\)$/
        n = 'x' + hex_char m[1]
      names.unshift n
    name = [n, names...].join '__'

    return
      try: @receiver.constructor.prototype["try__#{name}"]
      got: @receiver.constructor.prototype["got__#{name}"]
      not: @receiver.constructor.prototype["not__#{name}"]



  # Match all subrule methods:
  all: (funcs...)->
    all = ->
      pos = @pos
      for func in funcs
        FAIL '*** Missing function in @all group:', funcs \
          unless func?

        if not @call func
          @pos = pos
          return false

      return true

  # Match any subrule method. Rules are tried in order and stops on first
  # match:
  any: (funcs...)->
    any = ->
      for func in funcs
        if @call func
          return true

      return false

  may: (func)->
    may = ->
      @call func

  # Repeat a rule a certain number of times:
  rep: (min, max, func)->
    FAIL "rep max is < 0 '#{max}'" \
      if max? and max < 0
    rep = ->
      count = 0
      pos = @pos
      pos_start = pos
      while not(max?) or count < max
        break unless @call func
        break if @pos == pos
        count++
        pos = @pos
      if count >= min and (not(max?) or count <= max)
        return true
      @pos = pos_start
      return false
    name_ 'rep', rep, "rep(#{min},#{max})"

  # Call a rule depending on state value:
  case: (var_, map)->
    case_ = ->
      rule = map[var_]
      rule? or
        FAIL "Can't find '#{var_}' in:", map
      @call rule
    name_ 'case', case_, "case(#{var_},#{stringify map})"

  # Call a rule depending on state value:
  flip: (var_, map)->
    value = map[var_]
    value? or
      FAIL "Can't find '#{var_}' in:", map
    return value if isString value
    return @call value, 'number'

  the_end: ->
    return (
      @pos >= @end or (
        @state_curr().doc and
        @start_of_line() and
        @input[@pos..].match /^(?:---|\.\.\.)(?=\s|$)/
      )
    )

  # Match a single char:
  chr: (char)->
    chr = ->
      return false if @the_end()
      if @input[@pos] == char
        @pos++
        return true
      return false
    name_ 'chr', chr, "chr(#{stringify char})"

  # Match a char in a range:
  rng: (low, high)->
    rng = ->
      return false if @the_end()
      if low <= @input[@pos] <= high
        @pos++
        return true
      return false
    name_ 'rng', rng, "rng(#{stringify(low)},#{stringify(high)})"

  # Must match first rule but none of others:
  but: (funcs...)->
    but = ->
      return false if @the_end()
      pos1 = @pos
      return false unless @call funcs[0]
      pos2 = @pos
      @pos = pos1
      for func in funcs[1..]
        if @call func
          @pos = pos1
          return false
      @pos = pos2
      return true

  chk: (type, expr)->
    chk = ->
      pos = @pos
      @pos-- if type == '<='
      ok = @call expr
      @pos = pos
      return if type == '!' then not(ok) else ok
    name_ 'chk', chk, "chk(#{type}, #{stringify expr})"

  set: (var_, expr)->
    set = =>
      value = @call expr, 'any'
      return false if value == -1
      value = @auto_detect() if value == 'auto-detect'
      state = @state_prev()
      state[var_] = value
      if state.name != 'all'
        size = @state.length
        i = 3
        while i < size
          FAIL "failed to traverse state stack in 'set'" \
            if i > size - 2
          state = @state[size - i - 1]
          state[var_] = value
          break if state.name == 's_l_block_scalar'
          i++
      return true
    name_ 'set', set, "set('#{var_}', #{stringify expr})"

  max: (max)->
    max = ->
      return true

  exclude: (rule)->
    exclude = ->
      return true

  add: (x, y)->
    add = =>
      y = @call y, 'number' if isFunction y
      FAIL "y is '#{stringify y}', not number in 'add'" \
        unless isNumber y
      return x + y
    name_ 'add', add, "add(#{x},#{stringify y})"

  sub: (x, y)->
    sub = ->
      return x - y

  # This method does not need to return a function since it is never
  # called in the grammar.
  match: ->
    state = @state
    i = state.length - 1
    while i > 0 && not state[i].end?
      FAIL "Can't find match" if i == 1
      i--

    {beg, end} = state[i]
    return @input[beg...end]

  len: (str)->
    len = ->
      str = @call str, 'string' unless isString str
      return str.length

  ord: (str)->
    ord = ->
      return str.charCodeAt(0) - 48

  if: (test, do_if_true)->
    if_ = ->
      test = @call test, 'boolean' unless isBoolean test
      if test
        @call do_if_true
        return true
      return false
    name_ 'if', if_

  lt: (x, y)->
    lt = ->
      x = @call x, 'number' unless isNumber x
      y = @call y, 'number' unless isNumber y
      return x < y
    name_ 'lt', lt, "lt(#{stringify x},#{stringify y})"

  le: (x, y)->
    le = ->
      x = @call x, 'number' unless isNumber x
      y = @call y, 'number' unless isNumber y
      return x <= y
    name_ 'le', le, "le(#{stringify x},#{stringify y})"

  m: ->
    m = =>
      return @state_curr().m

  t: ->
    t = =>
      return @state_curr().t

#------------------------------------------------------------------------------
# Special grammar rules
#------------------------------------------------------------------------------
  start_of_line: ->
    return @pos == 0 or
      @pos >= @end or
      @input[@pos - 1] == "\n"

  end_of_stream: ->
    return @pos >= @end

  empty: -> true

  auto_detect_indent: (n)->
    m = @input[@pos..].match /^(\ *)/
    indent = m[1].length - n
    return if indent > 0 then indent else -1

  auto_detect: (n)->
    return 3

#------------------------------------------------------------------------------
# Trace debugging
#------------------------------------------------------------------------------
  trace_start: ->
    '' || ENV.TRACE_START

  trace_quiet: ->
    return [] if ENV.DEBUG
    [
      'c_directives_end',
      'c_l_folded',
      'c_l_literal',
      'c_ns_alias_node',
      'c_ns_anchor_property',
      'c_ns_tag_property',
      'l_directive_document',
      'l_document_prefix',
      'ns_flow_content',
      'ns_plain',
      's_l_comments',
      's_separate',
    ].concat((ENV.TRACE_QUIET || '').split ',')

  trace: (type, call, args=[])->
    call = String(call) unless isString call  # XXX
    call = "'#{call}'" if call.match /^($| |.* $)/
    return unless @trace_on or call == @trace_start()

    level = @state_curr().lvl
    indent = _.repeat ' ', level
    if level > 0
      l = "#{level}".length
      indent = "#{level}" + indent[l..]

    input = @input[@pos..]
    input = "#{input[0..30]}…" \
      if input.length > 30
    input = input \
      .replace(/\t/g, '\\t')
      .replace(/\r/g, '\\r')
      .replace(/\n/g, '\\n')

    line = sprintf(
      "%s%s %-40s  %4d '%s'",
      indent,
      type,
      @trace_format_call call, args
      @pos,
      input,
    )

    if ENV.DEBUG
      warn sprintf "%6d %s",
        @trace_num, line
      return

    trace_info = null
    level = "#{level}_#{call}"
    if type == '?' and @trace_off == 0
      trace_info = [type, level, line, @trace_num]
    if call in @trace_quiet()
      @trace_off += if type == '?' then 1 else -1
    if type != '?' and @trace_off == 0
      trace_info = [type, level, line, @trace_num]

    if trace_info?
      [prev_type, prev_level, prev_line, trace_num] =
        @trace_info
      if prev_type == '?' and prev_level == level
        trace_info[1] = ''
        if line.match /^\d*\ *\+/
          prev_line = prev_line.replace /\?/, '='
        else
          prev_line = prev_line.replace /\?/, '!'
      if prev_level
        warn sprintf "%5d %6d %s",
          ++@trace_line, trace_num, prev_line

      @trace_info = trace_info

    if call == @trace_start()
      @trace_on = not @trace_on

  trace_format_call: (call, args)->
    return call unless args.length
    list = args.map (a)->
      stringify a
    list = list.join ','
    return "#{call}(#{list})"

  trace_flush: ->
    [type, level, line, count] = @trace_info
    if line
      warn sprintf "%5d %6d %s",
        ++@trace_line, count, line

# vim: sw=2:
