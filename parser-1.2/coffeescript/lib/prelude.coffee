require 'ingy-prelude'

global.ENV = process.env

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
global.isFunction = _.isFunction
global.isArray = _.isArray
global.isObject = _.isPlainObject

global.typeof_ = (value)->
  return 'null' if _.isNull value
  return 'boolean' if _.isBoolean value
  return 'number' if _.isNumber value
  return 'string' if _.isString value
  return 'function' if _.isFunction value
  return 'array' if _.isArray value
  return 'object' if _.isPlainObject value
  xxx [value, typeof(value)]

global.stringify = (o)->
  if o == "\ufeff"
    return "\\uFEFF"
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
  die "FAIL '#{o[0] || '???'}'"

global.timer = (start=null)->
  if start?
    time = process.hrtime(start)
    time[0] + time[1] / 1000000000
  else
    process.hrtime()

# vim: sw=2:
