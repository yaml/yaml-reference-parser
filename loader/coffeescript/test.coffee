{Loader, Schema, StdLib} = require 'yaml-reference'

loader = new Loader
#   schema: new Schema
#     file: './json.yes'
#   lib: StdLib

dom = loader.load_dom(file: 'C4HZ.yaml')

# native = loader.load(file: 'C4HZ.yaml')

XXX dom.document
