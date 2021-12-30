{Reader} = require 'reader'
{Parser} = require 'parser'
{Dom} = require 'dom'
{StdLib} = require 'stdlib'

class Loader

  constructor: (args={})->
    {@schema, @library} = args

  load: (args)->
    reader = new Reader
    reader.open(args)
    dom = new Dom(args)

    parser = new Parser
      reader: reader
      composer: dom

    parser.parse()

    if (error = parser.error)?
      throw error

    dom.construct()

module.exports = {Loader}
