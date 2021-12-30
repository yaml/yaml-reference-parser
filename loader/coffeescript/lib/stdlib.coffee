class StdLib

  @join: [ 'str', 'str[]', 'str' ]
  join: (a, b)-> b.join(a)

  @words: [ 'str', 'str[]' ]
  words: (a)-> a.split(/\ +/)

module.exports = {StdLib}
