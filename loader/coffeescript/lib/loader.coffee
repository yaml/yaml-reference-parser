Parser = require 'parser'
{Constructor} = require 'constructor'
{Dom} = require 'dom'

class Loader

  constructor: (args={})->
    {@schema, @lib} = args

  load_dom: ({string, file})->
    if string?
      @input = string
    else if file?
      @input = file_read(file)
    else if arguments.length == 1 and arguments[0]?
      @input = String(arguments[0])
    else
      die "Loader::load_dom() invalid arguments"

    @dom = new Dom
    @parser = new Parser
      receiver: @dom

    try
      @parser.parse(@input)
    catch e
      throw e

    return @dom

module.exports = {Loader}
