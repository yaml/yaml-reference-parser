require 'ingy-prelude'

global.print = say
global.dump = DUMP

{Loader} = require('loader')
{Schema} = require('schema')
{StdLib} = require('stdlib')

module.exports =
  Loader: Loader
  Schema: Schema
  StdLib: StdLib
  loader: new Loader
  stdlib: new StdLib
