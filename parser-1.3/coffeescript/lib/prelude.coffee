require 'ingy-prelude'

Function::n = (name)->
  Object.defineProperty(@, 'name', value: name)
  return @

Function::w = ->
  warn 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
  return XXX typeof @

global.ENV = process.env

global.memoize = require('moize').maxSize(50)

#------------------------------------------------------------------------------
# Grammar helper functions:
#------------------------------------------------------------------------------

# Generate required regular expression and string variants:
global.make = (rgx)->
  str = String(rgx)

  # XXX Can remove when stable:
  if str.match(/>>\d+<</)
    die_ "Bad regex '#{rgx}'"
  if str.match(/\/mu?y?$/)
    die_ "make(#{str}) expression should not use 'm' flag"

  str = str[0..-2] if str.endsWith('u')
  str = String(str)[1..-2]
  chars = str[1..-2]
  str = str
    .replace(/\(([:!=]|<=)/g, '(?$1')
  return [ str, chars ]

global.start_of_line = '^'
global.end_of_input = '(?!.|\\n)'
global.try_got_not = try_: true, got_: true, not_: true


#------------------------------------------------------------------------------
# Generic helper functions:
#------------------------------------------------------------------------------

global.name_ = (name, func, trace)->
  func.trace = trace || name
  if ENV.DEBUGXXX   # Not working yet
    f = (n, args...)->
      args = args.map (a)-> stringify(a)
      args = args.join ''
      debug "#{name}(#{args})"
      func.apply func
    f.name = name
    f.trace = trace || name
    return f

  func

global.isNull = _.isNull
global.isBoolean = _.isBoolean
global.isNumber = _.isNumber
global.isString = _.isString
global.isRegex = _.isRegExp
global.isFunction = _.isFunction
global.isArray = _.isArray
global.isObject = _.isPlainObject

global.typeof_ = (value)->
  return 'null' if _.isNull value
  return 'boolean' if _.isBoolean value
  return 'number' if _.isNumber value
  return 'string' if _.isString value
  return 'regex' if _.isRegex value
  return 'function' if _.isFunction value
  return 'array' if _.isArray value
  return 'object' if _.isPlainObject value
  xxx [value, typeof(value)]

global.stringify = (o)->
  if o == "\ufeff"
    return "\\uFEFF"
  if isRegex o
    return String(o)
  if isFunction o
    return "@#{o.trace || o.name}"
  if isObject o
    return JSON.stringify _.keys(o)
  if isArray o
    return "[#{(_.map o, (e)-> stringify e).join ','}]"
  return JSON.stringify(o).replace /^"(.*)"$/, '$1'

global.hex_char = (chr)->
  return chr.charCodeAt(0).toString(16)

global.die_ = (msg)->
  die((new Error().stack) + "\n" + msg)

global.debug = (msg)->
  warn ">>> #{msg}"

global.debug_rule = (name, args...)->
  return unless ENV.DEBUG
  args = _.join _.map args, (a)->
    stringify(a)
  , ','
  debug "#{name}(#{args})"

global.dump = (o)->
  require('yaml').stringify o

global.FAIL = (o...)->
  WWW o
  die_ "FAIL '#{o[0] || '???'}'"

global.timer = (start=null)->
  if start?
    time = process.hrtime(start)
    time[0] + time[1] / 1000000000
  else
    process.hrtime()

# vim: sw=2:
