require './generate-yaml-grammar'

global.generator_class = \
  class YamlGrammarCoffeeScriptGenerator \
  extends YamlGrammarGenerator

  gen_grammar_head: (top)->
    name = @rule_name top
    """\
    #{@gen_grammar_info()}
    global.Grammar = class Grammar

      TOP: -> @#{name}
    \n\n
    """

  gen_setm: (return_false)->
    setm = "m = @call [@auto_detect_indent, n], 'number'"
    if return_false
      setm = "\n  return false unless " + setm
    else
      setm = "\n  " + setm
    return setm

  gen_rule_code: (num, comment, rule_name, debug_args, rule_args, rule_body)->

    @indent """\
    #{comment}
    @::#{rule_name}.num = #{Number @num}
    #{rule_name}: #{rule_args}->#{@setm}
      debug_rule("#{rule_name}"#{debug_args})
    #{rule_body}
    \n\n\n
    """

  gen_rule_args: (name)->
    rule = @spec[name] or XXX name
    return '' unless _.isPlainObject rule
    @args = rule['(...)']
    return '' unless @args?
    delete rule['(...)']
    @args = [ @args ] unless _.isArray @args
    "(#{@args.join ', '})"

  gen_debug_args: (name)->
    rule = @spec[name] or XXX name
    return '' unless _.isPlainObject rule
    args = rule['(...)']
    return '' unless args?
    args = [ args ] unless _.isArray args
    args = _.map args, (a)-> "#{a}"
    str = ',' + args.join(', ')
      .replace /\ /g, ''
      .replace /^\(\)$/, ''

  gen_hex_code: (hex)-> "\"\\u{#{hex}}\""

  gen_pair_sep: -> ': '

  gen_null: -> 'null'

  gen_method_call: (method, args...)->
    [args, sep] = @gen_method_call_args args
    "@#{method}(#{sep}#{args}#{sep})"

  gen_method_ref: (name)->
    if name == 'auto_detect_indent'
      "[@#{name}, n]"
    else
      "@#{name}"

  gen_comment_block: (text)->
    text = text
      .replace /\n$/, ''
    """\
    ###
    #{text}
    ###
    """

  fix_group: (text)->
    i = 0
    text.replace /^  @rep/mg, (m...)->
      m[0] + (if i++ then String(i) else '')

# vim: set sw=2:
