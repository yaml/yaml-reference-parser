Receiver = require 'receiver'

class Dom extends Receiver

  receive: (event)->
    type = event.event
    switch type
      when 'stream_start'
        @global = {}
        @documents = []
        @stack = []
      when 'document_start'
        @start(new Document(event))
      when 'mapping_start'
        @start(new Mapping(event))
      when 'sequence_start'
        @start(new Sequence(event))
      when 'scalar'
        @set new Scalar(event)
      when 'alias'
        @set new Alias(event)
      when 'stream_end' then @end()
      when 'document_end' then @end()
      when 'mapping_end' then @end()
      when 'sequence_end' then @end()
      else
        XXX ["Unrecognized event", type]

  start: (node)->
    @set(node)
    @stack.push node
    @node = node

  set: (node)->
    if @stack.length
      @node.add(node)
      if (anchor = node.anchor)?
        @document.lookup[anchor] = node
    else
      @document = node
      @documents.push(@document)

  end: ->
    @stack.pop()
    @node = @stack[@stack.length - 1]

class Document
  constructor: (event)->
    @name = 'Document'
    {@explicit, @version} = event
    @node = null
    @lookup = {}

  add: (@node)->

class Mapping
  constructor: (event)->
    @name = 'Mapping'
    {@anchor, @tag, @flow} = event
    @value = []

  add: (node)->
    if @key?
      @value.push(key: @key, val: node)
      delete @key
    else
      @key = node

class Sequence
  constructor: (event)->
    @name = 'Sequence'
    {@anchor, @tag, @flow} = event
    @value = []

  add: (node)->
    @value.push(node)

class Scalar
  constructor: (event)->
    @name = 'Scalar'
    {@anchor, @tag, @style, @value} = event

class Alias
  constructor: (event)->
    @name = 'Alias'
    @value = event.name


module.exports = {
  Dom
  Document
  Mapping
  Sequence
  Scalar
  Alias
}
