{loader, stdlib} = require 'yaml-reference'
{Schema} = require 'schema/json'
data = loader.load(file: '229Q.yaml', schema: new Schema)
print dump(data)

# schema = Schema.compile(file: 'json.yes')
