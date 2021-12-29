###
This is a parser class. It has a parse() method and parsing primitives for the
grammar. It calls methods in the receiver class, when a rule matches:
###

require './prelude'
require './grammar'

DEBUG = Boolean ENV.DEBUG
TRACE = Boolean ENV.TRACE
STATS = Boolean ENV.STATS

global.Parser = class Parser extends Grammar

  stats:
    calls: {}

  constructor: (receiver)->
    super()
    receiver.parser = @
    @receiver = receiver
    @pos = 0
    @end = 0
    @state = []

    if DEBUG or TRACE or STATS
      @call = @call_debug
      @trace_num = 0
      @trace_line = 0
      @trace_on = true
      @trace_off = 0
      @trace_info = ['', '', '']

  parse: (@input)->
    @input += "\n" unless \
      @input.length == 0 or
      @input.endsWith("\n")

    @end = @input.length

    if TRACE
      @trace_on = not @trace_start()

    try
      ok = @call @TOP
      if TRACE
        @trace_flush()
    catch err
      if TRACE
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
    if (curr = @state_curr())?
      curr.beg = child.beg
      curr.end = @pos

  # This is the dispatch function that calls all the grammar functions.
  # It should be as fast as possible.
  call: (func)->
    if func instanceof Array
      [func, args...] = func
    else
      args = []

    @state_push(func.name)

    args = args.map (a)->
      if typeof(a) == 'function'
        a()
      else
        a

    value = func.apply(@, args)
    while typeof(value) == 'function' or value instanceof Array
      value = @call value

    @state_pop()

    return value

  # To make the 'call' method as fast as possible, a debugging version of it
  # is here.
  call_debug: (func)->
    if func instanceof Array
      [func, args...] = func
    else
      args = []

    do =>
      FAIL "Bad call type '#{typeof_ func}' for '#{func}'" \
        unless isFunction func

    @state_push(func.name)

    trace = func.trace ?= func.name
    if STATS
      @stats.calls[trace] ?= 0
      @stats.calls[trace]++

    if TRACE
      @trace_num++
      @trace '?', trace, args

    args = args.map (a)->
      if typeof(a) == 'function'
        a()
      else
        a

    if DEBUG && func.name.match /_\w/
      debug_rule func.name, args...

    value = func.apply(@, args)
    while typeof(value) == 'function' or value instanceof Array
      value = @call value

    if TRACE
      @trace_num++
      if value
        @trace '+', trace
      else
        @trace 'x', trace

    @state_pop()

    return value

  got: (rule, {name, try_, got_, not_} = {})->
    name ?= ((new Error().stack).match(/at Parser.(\w+?_\w+) \(/))[1]
    try_ ?= false
    not_ ?= false
    got_ ?= !not_

    if try_
      try_func = @receiver.constructor.prototype["try_#{name}"] or
        die "@receiver.try_#{name} not defined"
    if got_
      got_func = @receiver.constructor.prototype["got_#{name}"] or
        die "@receiver.got_#{name} not defined"
    if not_
      not_func = @receiver.constructor.prototype["not_#{name}"] or
        die "@receiver.not_#{name} not defined"

    =>
      pos = @pos

      context =
        text: @input[pos...@pos]
        state: @state_curr()
        start: pos

      if try_
        try_func.call(@receiver, context)

      value = @call(rule)

      context.text = @input[pos...@pos]

      if value
        if got_
          got_func.call(@receiver, context)
      else
        if not_
          not_func.call(@receiver, context)

      return value



  # Match all subrule methods:
  all: (funcs...)->
    all = ->
      pos = @pos
      for func in funcs
        FAIL "*** Missing function in @all group: #{func}" \
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

  # Repeat a rule a certain number of times:
  rep: (quant, func)->
    switch quant
      when '*' then [min, max] = [0, Infinity]
      when '?' then [min, max] = [0, 1]
      when '+' then [min, max] = [1, Infinity]

    rep = ->
      count = 0
      pos = @pos
      pos_start = pos
      while count < max
        break unless @call func
        break if @pos == pos
        count++
        pos = @pos
      if count >= min and count <= max
        return true
      @pos = pos_start
      return false
    name_ 'rep', rep, "rep(#{quant})"

  # Check for end for doc or stream:
  the_end: ->
    return (
      @pos >= @end or (
        @state_curr().doc and (
          @pos == 0 or
          @input[@pos - 1] == "\n"
        ) and
        @input[@pos..].match /^(?:---|\.\.\.)(?=\s|$)/
      )
    )

  make = memoize (regex)->
    on_end = !! regex.match(/\)[\?\*]\/[muy]*$/)
    die_ regex if regex.match(/y$/)
    regex = regex[0..-2] if regex.endsWith('u')
    regex = regex
      .replace(/\(([:!=]|<=)/g, '(?$1')
    regex = String(regex)[1..-2]
      .replace(/\((?!\?)/g, '(?:')
    regex = /// (?: #{regex} ) ///yum
    return [regex, on_end]

  # Match a regex:
  rgx: (regex, debug=false)->
    regex = /// #{regex} ///u unless isRegex regex
    regex = String(regex)
    [regex, on_end] = make(regex)

    rgx = ->
      return on_end if @the_end()
      regex.lastIndex = @pos
      if m = @input.match(regex)
        @pos += m[0].length
        return true
      return false
    name_ 'rgx', rgx, "rgx(#{stringify regex})"

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
      if @input[@pos..].match(new RegExp "^[#{low}-#{high}]", 'u')
        @pos++ if @input[@pos..].codePointAt(0) > 65535
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
      if isString expr
        value = expr
      else
        value = @call expr
      return false if value == -1
      state = @state_prev()
      state[var_] = value
      if state.name != 'all'
        size = @state.length
        i = 3
        while i < size
          FAIL "failed to traverse state stack in 'set'" \
            if i > size - 1
          state = @state[size - i++ - 1]
          state[var_] = value
          break if state.name == 'block_scalar'
      return true
    name_ 'set', set, "set('#{var_}', #{stringify expr})"

#   max: (max)->
#     max = ->
#       return true

  exclude: (rule)->
    exclude = -> true

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
      str = @call str unless isString str
      return str.length

  ord: (str)->
    ord = ->
      str = @call str unless isString str
      return str.charCodeAt(0) - 48

  if: (test, do_if_true, do_if_false)->
    if_ = ->
      test = @call test unless isBoolean test
      if test
        @call do_if_true
        return true
      return false
    name_ 'if', if_

  lt: (x, y)->
    lt = ->
      x = @call x unless isNumber x
      y = @call y unless isNumber y
      return x < y
    name_ 'lt', lt, "lt(#{stringify x},#{stringify y})"

  le: (x, y)->
    le = ->
      x = @call x unless isNumber x
      y = @call y unless isNumber y
      return x <= y
    name_ 'le', le, "le(#{stringify x},#{stringify y})"

  m: (n=0)->
    m = =>
      return @state_curr().m + n

  t: ->
    t = =>
      return @state_curr().t

#------------------------------------------------------------------------------
# Special grammar rules
#------------------------------------------------------------------------------
  empty: -> true

  auto_detect_indent: (n)->
    pos = @pos
    in_seq = (pos > 0 and @input[pos - 1].match /^[\-\?\:]$/)
    match = @input[pos..].match ///^
      (
        (?:
          \ *
          (?:\#.*)?
          \n
        )*
      )
      (\ *)
    /// or FAIL "auto_detect_indent"
    pre = match[1]
    m = match[2].length
    if in_seq and not pre.length
      m++ if n == -1
    else
      m -= n
    m = 0 if m < 0
    return m

  auto_detect: (n)->
    match = @input[@pos..].match ///
      ^.*\n
      (
        (?:\ *\n)*
      )
      (\ *)
      (.?)
    ///
    pre = match[1]
    if match[3].length
      m = match[2].length - n
    else
      m = 0
      while pre.match ///\ {#{m}}///
        m++
      m = m - n - 1
    die "Spaces found after indent in auto-detect (5LLU)" \
      if m > 0 && pre.match ///^.{#{m}}\ ///m
    return if m == 0 then 1 else m

#------------------------------------------------------------------------------
# Trace debugging
#------------------------------------------------------------------------------
  trace_start: ->
    '' || ENV.TRACE_START

  trace_quiet: ->
    return [] if DEBUG

    small = [
      'b_as_line_feed',
      's_indent',
      'non_break_character',
    ]

    noisy = [
      'document_start_indicator',
      'block_folded_scalar',
      'block_literal_scalar',
      'c_ns_alias_node',
      'c_ns_anchor_property',
      'c_ns_tag_property',
      'directives_and_document',
      'document_prefix',
      'flow_content',
      'ns_plain',
      'comment_lines',
      'separation_characters',
    ]
    return ((ENV.TRACE_QUIET || '').split ',')
      .concat(noisy)

  trace: (type, call, args=[])->
    call = String(call) unless isString call  # XXX
    call = "'#{call}'" if call.match /^($| |.* $)/

    return unless @trace_on or call == @trace_start()

    if call.startsWith 'rgx'
      call = call
        .replace(/\n/g, "\\n")
        .replace(/\r/g, "\\r")

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

    if DEBUG
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
