{Schema: SchemaBase} = require 'schema/base13'

root = null

class SchemaJson extends SchemaBase

  types: ->
    '+node': (node)=>
      @any('+object', '+array', '+scalar')

    '+object': =>

    '+boolean': =>

module.exports =
  Schema: SchemaJson



'''
base: yaml/1.3

+node: !any +object +array +value

+object:
  tkey: +string
  kval: +node
  ytag: map

+array:
  type: +node
  list: true

+value: !any +number +boolean +null +string

+number: / {dash}? {digit}+ ( {dot} {digit}* )? /

+boolean: / true | false / => !!bool

+null: / null / => !!null

+string: else => !!str
'''

