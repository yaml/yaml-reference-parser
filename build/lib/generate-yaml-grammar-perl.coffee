require './generate-yaml-grammar'

global.generator_class = \
  class YamlGrammarPerlGenerator \
  extends YamlGrammarGenerator

  gen_grammar_head: (top)->
    name = @rule_name top
    """\
    #{@gen_grammar_info()}
    use v5.12;
    package Grammar;
    use Prelude;

    use constant DEBUG => $ENV{DEBUG};

    rule '000', TOP => sub {
      my ($self) = @_;
      $self->func('#{name}');
    };
    \n\n
    """

  gen_grammar_tail: ->
    """
    1;
    """

  gen_rule_code: (num, comment, rule_name, debug_args, rule_args, rule_body)->
    """\
    #{comment}
    rule '#{num}', #{rule_name} => sub {
      my #{rule_args} = @_;
      debug_rule("#{rule_name}"#{debug_args}) if DEBUG;
    #{rule_body};
    };
    \n\n\n
    """

  gen_rep: (rule, min, max)->
    @gen_method_call('rep', @gen_limit(min), @gen_limit(max), @gen(rule))
      .replace /\(\n  (-?\d+),\n  (undef|-?\d+),/, "($1, $2,"
      .replace /\)\n\)/, '))'

  gen_rule_args: (name)->
    rule = @spec[name] or XXX name
    return '($self)' unless _.isPlainObject rule
    args = rule['(...)']
    return '($self)' unless args?
    delete rule['(...)']
    @args = args
    args = [ args ] unless _.isArray args
    args = _.map args, (a)-> if a? then "$#{a}" else 'undef'
    args.unshift '$self'
    "(#{args.join ', '})"

  gen_debug_args: (name)->
    rule = @spec[name] or XXX name
    return '' unless _.isPlainObject rule
    args = rule['(...)']
    return '' unless args?
    args = [ args ] unless _.isArray args
    args = _.map args, (a)-> if a? then "$#{a}" else 'undef'
    str = ',' + args.join(', ')
      .replace /\ /g, ''
      .replace /^\(\)$/, ''

  gen_hex_code: (hex)-> "\"\\x{#{hex}}\""

  gen_var_value: (var_)-> "$#{var_}"

  gen_limit: (n)->
    if _.isNumber n then n else if n? then "$#{n}" else 'undef'

  gen_pair_sep: -> ' => '

  gen_null: -> 'undef'

  gen_method_call: (method, args...)->
    [args, sep] = @gen_method_call_args args
    "$self->#{method}(#{sep}#{args}#{sep})"

  gen_method_ref: (name)->
    if name == 'auto_detect_indent'
      "[$self->func('#{name}'), $n]"
    else
      "$self->func('#{name}')"

  gen_comment_block: (text)->
    text = text
      .replace /^/mg, '# '
      .replace /\n$/, ''
    """\
    ###
    #{text}
    ###
    """

  fix_group: (text)->
    i = 0
    text.replace /^  \$self->rep/mg, (m...)->
      m[0] + (if i++ then String(i) else '')

# vim: set sw=2:
