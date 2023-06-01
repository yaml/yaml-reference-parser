YAML 1.2 Reference Parsers
==========================

Generate YAML 1.2 Reference Parsers from the Spec

[![Travis Test Status](
https://travis-ci.org/yaml/yaml-reference-parser.svg?branch=master)](
https://travis-ci.org/yaml/yaml-reference-parser)
[![Actions Status: Test](
https://github.com/yaml/yaml-reference-parser/workflows/Test/badge.svg)](
https://github.com/yaml/yaml-reference-parser/actions?query=workflow%3A"Test")

# Synopsis

You can see all the generated YAML parsers in action by running:
```
make test
```

# Description

Here we generate 100% compliant YAML 1.2 parsers, in multiple programming
languages, from the YAML 1.2 specification.

We start with the [YAML 1.2 Spec](
https://yaml.org/spec/1.2/spec.html#id2770814) converted to the [YAML 1.2 Spec
as YAML](
https://github.com/yaml/yaml-grammar/blob/master/yaml-spec-1.2-patch.yaml).
Next we apply some minimal local patches for various problems that have been
identified in the spec.
Then we convert that YAML into a machine generated YAML 1.2 parser/grammar
module in every programming language.

At the moment we have YAML 1.2 reference parsers in these languages:
  * [CoffeeScript](
    https://github.com/yaml/yaml-reference-parser/blob/main/parser-1.2/coffeescript/lib/grammar.coffee)
  * [JavaScript](
    https://github.com/yaml/yaml-reference-parser/blob/main/parser-1.2/javascript/lib/grammar.js)
  * [Perl](
    https://github.com/yaml/yaml-reference-parser/blob/main/parser-1.2/perl/lib/Grammar.pm)

The parsers pass 100% of the [YAML Test Suite](
https://github.com/yaml/yaml-test-suite/)!

# Next Steps

* Generate equivalent grammar/parsers in as many modern languages as possible
  * The logic and primitives are purposefully as simple as possible
  * Generating a perfect parser in a new language should take a day or 2
  * Contributors welcome!
* Start refactoring the grammar to be simpler
  * While always passing the tests
* Generate more optimized / performant parsers
  * The goal of simplicity and sticking exactly to the spec made slow parsers
* Create a new YAML 1.3 grammar
  * Start with 1.2 grammar
  * Apply RFCs as they become accepted
  * Generate and test all the language parsers
