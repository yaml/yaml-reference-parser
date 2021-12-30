class Reader
  constructor: ->

  open: ({file, string})->
    if string?
      @buffer = string
    else if file?
      @buffer = file_read(file)
    else if arguments.length == 1 and arguments[0]?
      @buffer = String(arguments[0])
    else
      die "Loader::load_dom() invalid arguments"
    return @

  read: ->
    return @buffer

  close: ->

module.exports = {Reader}
