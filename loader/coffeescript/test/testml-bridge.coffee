require '../../../test/testml/src/coffee/lib/testml/bridge'
{loader} = require 'yaml-reference'

class TestMLBridge extends TestML.Bridge

  load: (yaml, schema)->
    schema = @get_schema(schema)

    data = loader.load(string:yaml, schema:schema)

  json: (o)->
    JSON.stringify(o, null, 2) + "\n"

  get_schema: (name)->
    if name == 'json'
      {Schema} = require 'schema/json'
      return new Schema

    if name == 'card'
      {Schema} = require 'schema/json'
      return new Schema

    throw "Can't get schema '#{name}'"

module.exports = TestMLBridge
