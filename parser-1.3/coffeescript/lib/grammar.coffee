global.Grammar = class Grammar
  # Helper functions:

  # Generate required regular expression and string variants:
  make = (rgx)->
    str = String(rgx)

    # XXX Can remove when stable:
    if str.match(/>>\d+<</)
      die_ "Bad regex '#{rgx}'"
    if str.match(/\/mu?y?$/)
      die_ "make(#{str}) expression should not use 'm' flag"

    str = str[0..-2] if str.endsWith('u')
    str = String(str)[1..-2]
    chars = str[1..-2]
    str = str
      .replace(/\(([:!=]|<=)/g, '(?$1')
    return [ str, chars ]

  start_of_line = '^'
  end_of_input = '(?!.|\\n)'

  inits = []
  init = (func, pos)->
    line = (new Error()).stack.split("\n")[2].split(':')[1]
    line =">>#{line}<<"

    if pos?
      inits.splice(pos, 0, func)
    else
      inits.push(func)
      return [line, line]

  try_got_not = try_: true, got_: true, not_: true


  # Grammar rules:

  TOP: -> @yaml_stream

  # [001]
  # yaml-stream ::=
  #   document-prefix*
  #   any-document?
  #   (
  #       (
  #         document-suffix+
  #         document-prefix*
  #         any-document?
  #       )
  #     | byte-order-mark
  #     | comment-line
  #     | start-indicator-and-document
  #   )*

  yaml_stream: ->
    @got(
      @all(
        @rep('*', @document_prefix)
        @rep('?', @any_document)
        @rep('*',
          @any(
            @all(
              @rep('+', @document_suffix)
              @rep('*', @document_prefix)
              @rep('?', @any_document)
            )
            @rgx(///(:
                #{byte_order_mark}
              | #{comment_line}
            )///u, 'BOM or comment line')
            @start_indicator_and_document
          )
        )
      )
      try_: true
      got_: true
    )



  # [002]
  # document-prefix ::=
  #   byte-order-mark?
  #   blanks-and-comment-line*

  [  document_prefix] = init ->
    [document_prefix] = make ///
      #{byte_order_mark}?
      #{blanks_and_comment_line}*
    ///u

  document_prefix: ->
    @rgx(document_prefix)



  # [003]
  # document-suffix ::=
  #   document-end-indicator
  #   comment-lines

  document_suffix: ->
    @all(
      @document_end_indicator
      @comment_lines
    )



  # [004]
  # document-start-indicator ::=
  #   "---"

  [  document_start_indicator] = init ->
    [document_start_indicator] = make ///
      ---
      #{ws_lookahead}
    ///

  document_start_indicator: ->
    @got(
      @rgx(document_start_indicator)
    )



  # [005]
  # document-end-indicator ::=
  #   "..."                             # Not followed by non-ws char

  [document_end_indicator] = make ///
    \.\.\.
  ///

  document_end_indicator: ->
    @got(
      @rgx(document_end_indicator)
    )



  # [006]
  # any-document ::=
  #     directives-and-document
  #   | start-indicator-and-document
  #   | bare-document

  any_document: ->
    @any(
      @directives_and_document
      @start_indicator_and_document
      @bare_document
    )



  # [007]
  # directives-and-document ::=
  #   directive-line+
  #   start-indicator-and-document

  directives_and_document: ->
    @all(
      @rep('+', @directive_line)
      @start_indicator_and_document
    )



  # [008]
  # start-indicator-and-document ::=
  #   document-start-indicator
  #   (
  #       bare-document
  #     | (
  #         empty-node
  #         comment-lines
  #       )
  #   )

  start_indicator_and_document: ->
    @all(
      @document_start_indicator
      @any(
        @bare_document
        @all(
          @empty_node
          @comment_lines
        )
      )
    )



  # [009]
  # bare-document ::=
  #   block-node(-1,BLOCK-IN)
  #   /* Excluding forbidden-content */

  bare_document: ->
    @state_curr().doc = true
    @all(
      @exclude(@forbidden_content)
      @block_node(-1, "BLOCK-IN")
    )



  # [010]
  # directive-line ::=
  #   '%'
  #   (
  #       yaml-directive-line
  #     | tag-directive-line
  #     | reserved-directive-line
  #   )
  #   comment-lines

  directive_line: ->
    @all(
      @chr('%')
      @any(
        @yaml_directive_line
        @tag_directive_line
        @reserved_directive_line
      )
      @comment_lines
    )



  # [011]
  # forbidden-content ::=
  #   <start-of-line>
  #   (
  #       document-start-indicator
  #     | document-end-indicator
  #   )
  #   (
  #       line-ending
  #     | blank-character
  #   )

  # XXX This is never called!
  forbidden_content: ->
    @rgx(///
      #{start_of_line}
      (
        #{document_start_indicator}
      | #{document_end_indicator}
      )
      (       # XXX slightly different than 1.3 spec
        [
          \x0A
          \x0D
        ]
      | #{blank_character}
      | #{end_of_input}
      )
    ///)



  # [012]
  # block-node(n,c) ::=
  #     block-node-in-a-block-node(n,c)
  #   | flow-node-in-a-block-node(n)

  block_node: (n, c)->
    @any(
      @block_node_in_a_block_node(n, c)
      @flow_node_in_a_block_node(n)
    )



  # [013]
  # block-node-in-a-block-node(n,c) ::=
  #     block-scalar(n,c)
  #   | block-collection(n,c)

  block_node_in_a_block_node: (n, c)->
    @any(
      @block_scalar(n, c)
      @block_collection(n, c)
    )



  # [014]
  # flow-node-in-a-block-node(n) ::=
  #   separation-characters(n+1,FLOW-OUT)
  #   flow-node(n+1,FLOW-OUT)
  #   comment-lines

  flow_node_in_a_block_node: (n)->
    @all(
      @separation_characters(n + 1, "FLOW-OUT")
      @flow_node(n + 1, "FLOW-OUT")
      @comment_lines
    )



  # [015]
  # block-collection(n,c) ::=
  #   (
  #     separation-characters(n+1,c)
  #     node-properties(n+1,c)
  #   )?
  #   comment-lines
  #   (
  #       block-sequence-context(n,c)
  #     | block-mapping(n)
  #   )

  block_collection: (n, c)->
    @all(
      @rep('?',
        @all(
          @separation_characters(n + 1, c)
          @check_node_properties
          @any(
            @got(
              @all(
                @node_properties(n + 1, c)
                @comment_lines
              )
              name: 'block_collection_properties'
              not_: true
            )

            @got(
              @all(
                @tag_property
                @comment_lines
              )
              name: 'block_collection_tag'
              not_: true
            )

            @got(
              @all(
                @anchor_property
                @comment_lines
              )
              name: 'block_collection_anchor'
              not_: true
            )
          )
        )
      )
      @comment_lines
      @any(
        @block_sequence_context(n, c)
        => @block_mapping(n)
      )
    )



  # [016]
  # block-sequence-context(n,BLOCK-OUT) ::= block-sequence(n-1)
  # block-sequence-context(n,BLOCK-IN)  ::= block-sequence(n)

  block_sequence_context: (n, c)->
    @got(
      =>
        switch c
          when 'BLOCK-OUT' then @block_sequence(n - 1)
          when 'BLOCK-IN'  then @block_sequence(n)
      try_got_not
    )



  # [017]
  # block-scalar(n,c) ::=
  #   separation-characters(n+1,c)
  #   (
  #     node-properties(n+1,c)
  #     separation-characters(n+1,c)
  #   )?
  #   (
  #       block-literal-scalar(n)
  #     | block-folded-scalar(n)
  #   )

  block_scalar: (n, c)->
    @all(
      @separation_characters(n + 1, c)
      @rep('?',
        @all(
          @node_properties(n + 1, c)
          @separation_characters(n + 1, c)
        )
      )
      @any(
        @block_literal_scalar(n)
        @block_folded_scalar(n)
      )
    )



  # [018]
  # block-mapping(n) ::=
  #   (
  #     indentation-spaces(n+1+m)
  #     block-mapping-entry(n+1+m)
  #   )+

  block_mapping: (n)->
    return false unless m = @call [@auto_detect_indent, n], 'number'
    @got(
      @all(
        @rep('+',
          @all(
            @indentation_spaces_n(n + m)
            @block_mapping_entry(n + m)
          )
        )
      )
      try_got_not
    )



  # [019]
  # block-mapping-entry(n) ::=
  #     block-mapping-explicit-entry(n)
  #   | block-mapping-implicit-entry(n)

  block_mapping_entry: (n)->
    @any(
      @block_mapping_explicit_entry(n)
      @block_mapping_implicit_entry(n)
    )



  # [020]
  # block-mapping-explicit-entry(n) ::=
  #   block-mapping-explicit-key(n)
  #   (
  #       block-mapping-explicit-value(n)
  #     | empty-node
  #   )

  block_mapping_explicit_entry: (n)->
    @got(
      @all(
        @block_mapping_explicit_key(n)
        @any(
          @block_mapping_explicit_value(n)
          @empty_node
        )
      )
      try_got_not
    )



  # [021]
  # block-mapping-explicit-key(n) ::=
  #   '?'                               # Not followed by non-ws char
  #   block-indented-node(n,BLOCK-OUT)

  block_mapping_explicit_key: (n)->
    @all(
      @rgx(///
        \?
        #{ws_lookahead}
      ///)
      => @block_indented_node(n, "BLOCK-OUT")
    )



  # [022]
  # block-mapping-explicit-value(n) ::=
  #   indentation-spaces(n)
  #   ':'                               # Not followed by non-ws char
  #   block-indented-node(n,BLOCK-OUT)

  block_mapping_explicit_value: (n)->
    @all(
      @indentation_spaces_n(n)
      @rgx(///
        :
        #{ws_lookahead}
      ///)
      => @block_indented_node(n, "BLOCK-OUT")
    )



  # [023]
  # block-mapping-implicit-entry(n) ::=
  #   (
  #       block-mapping-implicit-key
  #     | empty-node
  #   )
  #   block-mapping-implicit-value(n)

  block_mapping_implicit_entry: (n)->
    @got(
      @all(
        @any(
          @block_mapping_implicit_key
          @empty_node
        )
        @block_mapping_implicit_value(n)
      )
      try_got_not
    )



  # XXX Can fold into 023
  # [024]
  # block-mapping-implicit-key ::=
  #     implicit-json-key(BLOCK-KEY)
  #   | implicit-yaml-key(BLOCK-KEY)

  block_mapping_implicit_key: ->
    @any(
      @implicit_json_key("BLOCK-KEY")
      @implicit_yaml_key("BLOCK-KEY")
    )



  # [025]
  # block-mapping-implicit-value(n) ::=
  #   ':'                               # Not followed by non-ws char
  #   (
  #       block-node(n,BLOCK-OUT)
  #     | (
  #         empty-node
  #         comment-lines
  #       )
  #   )

  block_mapping_implicit_value: (n)->
    @all(
      @rgx(///
        :
        #{ws_lookahead}
      ///)
      @any(
        @block_node(n, "BLOCK-OUT")
        @all(
          @empty_node
          @comment_lines
        )
      )
    )



  # [026]
  # compact-mapping(n) ::=
  #   block-mapping-entry(n)
  #   (
  #     indentation-spaces(n)
  #     block-mapping-entry(n)
  #   )*

  compact_mapping: (n)->
    @got(
      @all(
        @block_mapping_entry(n)
        @rep('*',
          @all(
            @indentation_spaces_n(n)
            @block_mapping_entry(n)
          )
        )
      )
      try_got_not
    )



  # [027]
  # block-sequence(n) ::=
  #   (
  #     indentation-spaces(n+1+m)
  #     block-sequence-entry(n+1+m)
  #   )+

  block_sequence: (n)->
    return false unless m = @auto_detect_indent(n)
    @all(
      @rep('+',
        @all(
          @indentation_spaces_n(n + m)
          @block_sequence_entry(n + m)
        )
      )
    )



  # [028]
  # block-sequence-entry(n) ::=
  #   '-'
  #   [ lookahead ≠ non-space-character ]
  #   block-indented-node(n,BLOCK-IN)

  block_sequence_entry: (n)->
    @all(
      @rgx(///
        -
        #{ws_lookahead}
        (! #{non_space_character} )
      ///u)
      => @block_indented_node(n, "BLOCK-IN")
    )



  # [029]
  # block-indented-node(n,c) ::=
  #     (
  #       indentation-spaces(m)
  #       (
  #           compact-sequence(n+1+m)
  #         | compact-mapping(n+1+m)
  #       )
  #     )
  #   | block-node(n,c)
  #   | (
  #       empty-node
  #       comment-lines
  #     )

  block_indented_node: (n, c)->
    m = @auto_detect_indent(n)
    @any(
      @all(
        @indentation_spaces_n(m)
        @any(
          @compact_sequence(n + 1 + m)
          @compact_mapping(n + 1 + m)
        )
      )
      @block_node(n, c)
      @all(
        @empty_node
        @comment_lines
      )
    )



  # [030]
  # compact-sequence(n) ::=
  #   block-sequence-entry(n)
  #   (
  #     indentation-spaces(n)
  #     block-sequence-entry(n)
  #   )*

  compact_sequence: (n)->
    @got(
      @all(
        @block_sequence_entry(n)
        @rep('*',
          @all(
            @indentation_spaces_n(n)
            @block_sequence_entry(n)
          )
        )
      )
      try_got_not
    )



  # [031]
  # block-literal-scalar(n) ::=
  #   '|'
  #   block-scalar-indicators(t)
  #   literal-scalar-content(n+m,t)

  block_literal_scalar: (n)->
    @got(
      @all(
        @chr('|')
        @block_scalar_indicators(n)
        @literal_scalar_content(@m(n), @t())
      )
      try_got_not
    )



  # [032]
  # literal-scalar-content(n,t) ::=
  #   (
  #     literal-scalar-line-content(n)
  #     literal-scalar-next-line(n)*
  #     block-scalar-chomp-last(t)
  #   )?
  #   block-scalar-chomp-empty(n,t)

  literal_scalar_content: (n, t)->
    @all(
      @rep('?',
        @all(
          [ @literal_scalar_line_content, n ]
          @rep('*', [ @literal_scalar_next_line, n ])
          @rgx(line_ending)
        )
      )
      [ @block_scalar_chomp_empty, n, t ]
    )



  # [033]
  # literal-scalar-line-content(n) ::=
  #   empty-line(n,BLOCK-IN)*
  #   indentation-spaces(n)
  #   non-break-character+

  literal_scalar_line_content: (n)->
    @all(
      @rep('*', @empty_line(n, "BLOCK-IN"))
      @indentation_spaces_n(n)
      @got(
        @rgx(/// #{non_break_character}+ ///u)
      )
    )



  # [034]
  # literal-scalar-next-line(n) ::=
  #   break-as-line-feed
  #   literal-scalar-line-content(n)

  literal_scalar_next_line: (n)->
    @all(
      @rgx(break_as_line_feed)
      @literal_scalar_line_content(n)
    )



  # [035]
  # block-folded-scalar(n) ::=
  #   '>'
  #   block-scalar-indicators(t)
  #   folded-scalar-content(n+m,t)

  block_folded_scalar: (n)->
    @got(
      @all(
        @chr('>')
        @block_scalar_indicators(n)
        @folded_scalar_content(@m(n), @t())
      )
      try_got_not
    )



  # [036]
  # folded-scalar-content(n,t) ::=
  #   (
  #     folded-scalar-lines-different-indentation(n)
  #     block-scalar-chomp-last(t)
  #   )?
  #   block-scalar-chomp-empty(n,t)

  folded_scalar_content: (n, t)->
    @all(
      @rep('?',
        @all(
          @folded_scalar_lines_different_indentation(n)
          @rgx(line_ending)
        )
      )
      [ @block_scalar_chomp_empty, n, t ]
    )



  # [037]
  # folded-scalar-lines-different-indentation(n) ::=
  #   folded-scalar-lines-same-indentation(n)
  #   (
  #     break-as-line-feed
  #     folded-scalar-lines-same-indentation(n)
  #   )*

  folded_scalar_lines_different_indentation: (n)->
    @all(
      @folded_scalar_lines_same_indentation(n)
      @rep('*',
        @all(
          @rgx(break_as_line_feed)
          @folded_scalar_lines_same_indentation(n)
        )
      )
    )



  # [038]
  # folded-scalar-lines-same-indentation(n) ::=
  #   empty-line(n,BLOCK-IN)*
  #   (
  #       folded-scalar-lines(n)
  #     | folded-scalar-spaced-lines(n)
  #   )

  folded_scalar_lines_same_indentation: (n)->
    @all(
      @rep('*', @empty_line(n, "BLOCK-IN"))
      @any(
        [ @folded_scalar_lines, n ]
        [ @folded_scalar_spaced_lines, n ]
      )
    )



  # [039]
  # folded-scalar-lines(n) ::=
  #   folded-scalar-text(n)
  #   (
  #     folded-whitespace(n,BLOCK-IN)
  #     folded-scalar-text(n)
  #   )*

  folded_scalar_lines: (n)->
    @all(
      [ @folded_scalar_text, n ]
      @rep('*',
        @all(
          [ @folded_whitespace, n, "BLOCK-IN" ]
          [ @folded_scalar_text, n ]
        )
      )
    )



  # [040]
  # folded-scalar-spaced-lines(n) ::=
  #   folded-scalar-spaced-text(n)
  #   (
  #     line-break-and-empty-lines(n)
  #     folded-scalar-spaced-text(n)
  #   )*

  folded_scalar_spaced_lines: (n)->
    @all(
      @folded_scalar_spaced_text(n)
      @rep('*',
        @all(
          @line_break_and_empty_lines(n)
          @folded_scalar_spaced_text(n)
        )
      )
    )



  # [041]
  # folded-scalar-text(n) ::=
  #   indentation-spaces(n)
  #   non-space-character
  #   non-break-character*

  folded_scalar_text: (n)->
    @all(
      @indentation_spaces_n(n)
      @got(
        @rgx(///
          #{non_space_character}+
          #{non_break_character}*
        ///u)
      )
    )



  # [042]
  # line-break-and-empty-lines(n) ::=
  #   break-as-line-feed
  #   empty-line(n,BLOCK-IN)*

  line_break_and_empty_lines: (n)->
    @all(
      @rgx(break_as_line_feed)
      @rep('*', @empty_line(n, "BLOCK-IN"))
    )



  # [043]
  # folded-scalar-spaced-text(n) ::=
  #   indentation-spaces(n)
  #   blank-character
  #   non-break-character*

  folded_scalar_spaced_text: (n)->
    @all(
      @indentation_spaces_n(n)
      @got(
        @rgx(///
          #{blank_character}
          #{non_break_character}*
        ///u)
      )
    )



  # [044]
  # block-scalar-indicators(t) ::=
  #   (
  #       (
  #         block-scalar-indentation-indicator
  #         block-scalar-chomping-indicator(t)
  #       )
  #     | (
  #         block-scalar-chomping-indicator(t)
  #         block-scalar-indentation-indicator
  #       )
  #   )
  #   comment-line

  block_scalar_indicators: (n)->
    @all(
      @any(
        @all(
          => @block_scalar_indentation_indicator(n)
          @block_scalar_chomping_indicator
          @ws_lookahead     # TODO This might be needed in spec
        )
        @all(
          @block_scalar_chomping_indicator
          => @block_scalar_indentation_indicator(n)
        )
      )
      @comment_line
    )



  # [045]
  # block-scalar-indentation-indicator ::=
  #   decimal-digit-1-9

  block_scalar_indentation_indicator: (n)->
    @any(
      @if(@rgx(decimal_digit_1_9), @set('m', @ord(@match)))
      @if(@empty, @set('m', => @auto_detect(n)))
    )



  # [046]
  # block-scalar-chomping-indicator(STRIP) ::= '-'
  # block-scalar-chomping-indicator(KEEP)  ::= '+'
  # block-scalar-chomping-indicator(CLIP)  ::= ""

  block_scalar_chomping_indicator: ->
    @any(
      @if(@chr('-'), @set('t', "STRIP"))
      @if(@chr('+'), @set('t', "KEEP"))
      @if(@empty, @set('t', "CLIP"))
    )



# TODO This production can be removed from the spec:
#   # [047]
#   # block-scalar-chomp-last(STRIP) ::= line-break | <end-of-input>
#   # block-scalar-chomp-last(CLIP)  ::= break-as-line-feed | <end-of-input>
#   # block-scalar-chomp-last(KEEP)  ::= break-as-line-feed | <end-of-input>
#
#   block_scalar_chomp_last: (t)->
#     @rgx(line_ending)



  #   [048]
  #   block-scalar-chomp-empty(n,STRIP) ::= line-strip-empty(n)
  #   block-scalar-chomp-empty(n,CLIP)  ::= line-strip-empty(n)
  #   block-scalar-chomp-empty(n,KEEP)  ::= line-keep-empty(n)

  block_scalar_chomp_empty: (n, t)->
    switch t
      when 'STRIP' then @line_strip_empty(n)
      when 'CLIP'  then @line_strip_empty(n)
      when 'KEEP'  then @line_keep_empty(n)



  # [049]
  # line-strip-empty(n) ::=
  #   (
  #     indentation-spaces-less-or-equal(n)
  #     line-break
  #   )*
  #   line-trail-comments(n)?

  line_strip_empty: (n)->
    @all(
      @rep('*',
        @all(
          @indentation_spaces_less_or_equal(n)
          @rgx(line_break)
        )
      )
      @rep('?', @line_trail_comments(n))
    )



  # [050]
  # line-keep-empty(n) ::=
  #   empty-line(n,BLOCK-IN)*
  #   line-trail-comments(n)?

  line_keep_empty: (n)->
    @all(
      @rep('*', @empty_line(n, "BLOCK-IN"))
      @rep('?', @line_trail_comments(n))
    )



  # [051]
  # line-trail-comments(n) ::=
  #   indentation-spaces-less-than(n)
  #   comment-content
  #   line-ending
  #   comment-line*

  line_trail_comments: (n)->
    @all(
      @indentation_spaces_less_than(n)
      @rgx(line_trail_comments)
      @rep('*', @comment_line)
    )

  [  line_trail_comments] = init ->
    [line_trail_comments] = make ///
      #{comment_content}
      #{line_ending}
    ///u



  # [052]
  # flow-node(n,c) ::=
  #     alias-node
  #   | flow-content(n,c)
  #   | (
  #       node-properties(n,c)
  #       (
  #         (
  #           separation-characters(n,c)
  #           flow-content(n,c)
  #         )
  #         | empty-node
  #       )
  #     )

  flow_node: (n, c)->
    @any(
      @alias_node
      @flow_content(n, c)
      @all(
        @node_properties(n, c)
        @any(
          @all(
            @separation_characters(n, c)
            @flow_content(n, c)
          )
          @empty_node
        )
      )
    )



  # [053]
  # flow-content(n,c) ::=
  #     flow-yaml-content(n,c)
  #   | flow-json-content(n,c)

  flow_content: (n, c)->
    @any(
      @flow_yaml_content(n, c)
      @flow_json_content(n, c)
    )



  # [054]
  # flow-yaml-content(n,c) ::=
  #   flow-plain-scalar(n,c)

  flow_yaml_content: (n, c)->
    @flow_plain_scalar(n, c)



  # [055]
  # flow-json-content(n,c) ::=
  #     flow-sequence(n,c)
  #   | flow-mapping(n,c)
  #   | single-quoted-scalar(n,c)
  #   | double-quoted-scalar(n,c)

  [check_flow_json_content] = make ///
    (= [ \[ { " ' ] )
  ///

  flow_json_content: (n, c)->
    @all(
      @rgx(check_flow_json_content)
      @any(
        @flow_sequence(n, c)
        @flow_mapping(n, c)
        @single_quoted_scalar(n, c)
        @double_quoted_scalar(n, c)
      )
    )



  # [056]
  # flow-mapping(n,c) ::=
  #   '{'
  #   separation-characters(n,c)?
  #   flow-mapping-context(n,c)?
  #   '}'

  flow_mapping: (n, c)->
    @all(
      @got(
        @chr('{')
        name: 'flow_mapping_start'
      )
      @rep('?', @separation_characters(n, c))
      @rep('?', @flow_mapping_context(n, c))
      @got(
        @chr('}')
        name: 'flow_mapping_end'
      )
    )



  # [057]
  # flow-mapping-entries(n,c) ::=
  #   flow-mapping-entry(n,c)
  #   separation-characters(n,c)?
  #   (
  #     ','
  #     separation-characters(n,c)?
  #     flow-mapping-entries(n,c)?
  #   )?

  flow_mapping_entries: (n, c)->
    @all(
      @flow_mapping_entry(n, c)
      @rep('?', @separation_characters(n, c))
      @rep('?',
        @all(
          @chr(',')
          @rep('?', @separation_characters(n, c))
          => @rep('?', @flow_mapping_entries(n, c ))
        )
      )
    )



  # [058]
  # flow-mapping-entry(n,c) ::=
  #     (
  #       '?'                           # Not followed by non-ws char
  #       separation-characters(n,c)
  #       flow-mapping-explicit-entry(n,c)
  #     )
  #   | flow-mapping-implicit-entry(n,c)

  flow_mapping_entry: (n, c)->
    @any(
      @all(
        @rgx(///
          \?
          #{ws_lookahead}
        ///)
        [ @separation_characters, n, c ]
        [ @flow_mapping_explicit_entry, n, c ]
      )
      [ @flow_mapping_implicit_entry, n, c ]
    )



  # [059]
  # flow-mapping-explicit-entry(n,c) ::=
  #     flow-mapping-implicit-entry(n,c)
  #   | (
  #       empty-node
  #       empty-node
  #     )

  flow_mapping_explicit_entry: (n, c)->
    @any(
      [ @flow_mapping_implicit_entry, n, c ]
      @all(
        @empty_node
        @empty_node
      )
    )



  # [060]
  # flow-mapping-implicit-entry(n,c) ::=
  #     flow-mapping-yaml-key-entry(n,c)
  #   | flow-mapping-empty-key-entry(n,c)
  #   | flow-mapping-json-key-entry(n,c)

  flow_mapping_implicit_entry: (n, c)->
    @any(
      [ @flow_mapping_yaml_key_entry, n, c ]
      [ @flow_mapping_empty_key_entry, n, c ]
      [ @flow_mapping_json_key_entry, n, c ]
    )



  # [061]
  # flow-mapping-yaml-key-entry(n,c) ::=
  #   flow-yaml-node(n,c)
  #   (
  #       (
  #         separation-characters(n,c)?
  #         flow-mapping-separate-value(n,c)
  #       )
  #     | empty-node
  #   )

  flow_mapping_yaml_key_entry: (n, c)->
    @all(
      [ @flow_yaml_node, n, c ]
      @any(
        @all(
          @rep('?', [ @separation_characters, n, c ])
          [ @flow_mapping_separate_value, n, c ]
        )
        @empty_node
      )
    )



  # [062]
  # flow-mapping-empty-key-entry(n,c) ::=
  #   empty-node
  #   flow-mapping-separate-value(n,c)

  flow_mapping_empty_key_entry: (n, c)->
    @got(
      @all(
        @empty_node
        [ @flow_mapping_separate_value, n, c ]
      )
      try_got_not
    )



  # [063]
  # flow-mapping-separate-value(n,c) ::=
  #   ':'
  #   [ lookahead ≠ non-space-plain-scalar-character(c) ]
  #   (
  #       (
  #         separation-characters(n,c)
  #         flow-node(n,c)
  #       )
  #     | empty-node
  #   )

  flow_mapping_separate_value: (n, c)->
    @all(
      @rgx(///
        (:
          :
          (! #{@non_space_plain_scalar_character(c)} )
        )
      ///u)
      @any(
        @all(
          [ @separation_characters, n, c ]
          [ @flow_node, n, c ]
        )
        @empty_node
      )
    )



  # [064]
  # flow-mapping-json-key-entry(n,c) ::=
  #   flow-json-node(n,c)
  #   (
  #       (
  #         separation-characters(n,c)?
  #         flow-mapping-adjacent-value(n,c)
  #       )
  #     | empty-node
  #   )

  flow_mapping_json_key_entry: (n, c)->
    @all(
      [ @flow_json_node, n, c ]
      @any(
        @all(
          @rep('?', [ @separation_characters, n, c ])
          [ @flow_mapping_adjacent_value, n, c ]
        )
        @empty_node
      )
    )



  # [065]
  # flow-mapping-adjacent-value(n,c) ::=
  #   ':'
  #   (
  #       (
  #         separation-characters(n,c)?
  #         flow-node(n,c)
  #       )
  #     | empty-node
  #   )

  flow_mapping_adjacent_value: (n, c)->
    @all(
      @chr(':')
      @any(
        @all(
          @rep('?', [ @separation_characters, n, c ])
          [ @flow_node, n, c ]
        )
        @empty_node
      )
    )



  # [066]
  # flow-pair(n,c) ::=
  #     (
  #       '?'                           # Not followed by non-ws char
  #       separation-characters(n,c)
  #       flow-mapping-explicit-entry(n,c)
  #     )
  #   | flow-pair-entry(n,c)

  flow_pair: (n, c)->
    @got(
      @any(
        @all(
          @rgx(///
            \?
            #{ws_lookahead}
          ///)
          [ @separation_characters, n, c ]
          [ @flow_mapping_explicit_entry, n, c ]
        )
        [ @flow_pair_entry, n, c ]
      )
      try_got_not
    )



  # [067]
  # flow-pair-entry(n,c) ::=
  #     flow-pair-yaml-key-entry(n,c)
  #   | flow-mapping-empty-key-entry(n,c)
  #   | flow-pair-json-key-entry(n,c)

  flow_pair_entry: (n, c)->
    @any(
      [ @flow_pair_yaml_key_entry, n, c ]
      [ @flow_mapping_empty_key_entry, n, c ]
      [ @flow_pair_json_key_entry, n, c ]
    )



  # [068]
  # flow-pair-yaml-key-entry(n,c) ::=
  #   implicit-yaml-key(FLOW-KEY)
  #   flow-mapping-separate-value(n,c)

  flow_pair_yaml_key_entry: (n, c)->
    @all(
      [ @implicit_yaml_key, "FLOW-KEY" ]
      [ @flow_mapping_separate_value, n, c ]
    )



  # [069]
  # flow-pair-json-key-entry(n,c) ::=
  #   implicit-json-key(FLOW-KEY)
  #   flow-mapping-adjacent-value(n,c)

  flow_pair_json_key_entry: (n, c)->
    @all(
      [ @implicit_json_key, "FLOW-KEY" ]
      [ @flow_mapping_adjacent_value, n, c ]
    )



  # [070]
  # implicit-yaml-key(c) ::=
  #   flow-yaml-node(0,c)
  #   separation-blanks?
  #   /* At most 1024 characters altogether */

  implicit_yaml_key: (c)->
    @all(
      # @max(1024)
      [ @flow_yaml_node, null, c ]
      @rep('?', @separation_blanks)
    )



  # [071]
  # implicit-json-key(c) ::=
  #   flow-json-node(0,c)
  #   separation-blanks?
  #   /* At most 1024 characters altogether */

  implicit_json_key: (c)->
    @all(
      # @max(1024)
      [ @flow_json_node, null, c ]
      @rep('?', @separation_blanks)
    )



  # [072]
  # flow-yaml-node(n,c) ::=
  #     alias-node
  #   | flow-yaml-content(n,c)
  #   | (
  #       node-properties(n,c)
  #       (
  #           (
  #             separation-characters(n,c)
  #             flow-yaml-content(n,c)
  #           )
  #         | empty-node
  #       )
  #     )

  flow_yaml_node: (n, c)->
    @any(
      @alias_node
      [ @flow_yaml_content, n, c ]
      @all(
        [ @node_properties, n, c ]
        @any(
          @all(
            [ @separation_characters, n, c ]
            [ @flow_content, n, c ]
          )
          @empty_node
        )
      )
    )



  # [073]
  # flow-json-node(n,c) ::=
  #   (
  #     node-properties(n,c)
  #     separation-characters(n,c)
  #   )?
  #   flow-json-content(n,c)

  flow_json_node: (n, c)->
    @all(
      @rep('?',
        @all(
          [ @node_properties, n, c ]
          [ @separation_characters, n, c ]
        )
      )
      [ @flow_json_content, n, c ]
    )



  # [074]
  # flow-sequence(n,c) ::=
  #   '['
  #   separation-characters(n,c)?
  #   flow-sequence-context(n,c)?
  #   ']'

  flow_sequence: (n, c)->
    @all(
      @got(
        @chr('[')
        name: 'flow_sequence_start'
      )
      @rep('?', [ @separation_characters, n, c ])
      @rep('?', [ @flow_sequence_context, n, c ])
      @got(
        @chr(']')
        name: 'flow_sequence_end'
      )
    )



  # [075]
  # flow-sequence-entries(n,c) ::=
  #   flow-sequence-entry(n,c)
  #   separation-characters(n,c)?
  #   (
  #     ','
  #     separation-characters(n,c)?
  #     flow-sequence-entries(n,c)?
  #   )?

  flow_sequence_entries: (n, c)->
    @all(
      [ @flow_sequence_entry, n, c ]
      @rep('?', [ @separation_characters, n, c ])
      @rep('?',
        @all(
          @chr(',')
          @rep('?', [ @separation_characters, n, c ])
          @rep('?', [ @flow_sequence_entries, n, c ])
        )
      )
    )



  # [076]
  # flow-sequence-entry(n,c) ::=
  #     flow-pair(n,c)
  #   | flow-node(n,c)

  flow_sequence_entry: (n, c)->
    @any(
      [ @flow_pair, n, c ]
      [ @flow_node, n, c ]
    )



  # [077]
  # double-quoted-scalar(n,c) ::=
  #   '"'
  #   double-quoted-text(n,c)
  #   '"'

  double_quoted_scalar: (n, c)->
    @got(
      @all(
        @chr('"')
        [ @double_quoted_text, n, c ]
        @chr('"')
      )
    )



  # [078]
  # double-quoted-text(n,BLOCK-KEY) ::= double-quoted-one-line
  # double-quoted-text(n,FLOW-KEY)  ::= double-quoted-one-line
  # double-quoted-text(n,FLOW-OUT)  ::= double-quoted-multi-line(n)
  # double-quoted-text(n,FLOW-IN)   ::= double-quoted-multi-line(n)

  double_quoted_text: (n, c)->
    switch c
      when 'BLOCK-KEY' then @double_quoted_one_line
      when 'FLOW-KEY'  then @double_quoted_one_line
      when 'FLOW-OUT'  then @double_quoted_multi_line(n)
      when 'FLOW-IN'   then @double_quoted_multi_line(n)



  # [079]
  # double-quoted-multi-line(n) ::=
  #   double-quoted-first-line
  #   (
  #       double-quoted-next-line(n)
  #     | blank-character*
  #   )

  double_quoted_multi_line: (n)->
    @all(
      @double_quoted_first_line
      @any(
        [ @double_quoted_next_line, n ]
        @rgx(/// #{blank_character}* ///)
      )
    )



  # [080]
  # double-quoted-one-line ::=
  #   non-break-double-quoted-character*

  double_quoted_one_line: ->
    @rgx(///
      #{non_break_double_quoted_character}*
    ///u)



  # [081]
  # double-quoted-first-line ::=
  #   (
  #     blank-character*
  #     non-space-double-quoted-character
  #   )*

  double_quoted_first_line: ->
    @rgx(///
      (:
        #{blank_character}*
        #{non_space_double_quoted_character}
      )*
    ///u)



  # [082]
  # double-quoted-next-line(n) ::=
  #   (
  #       double-quoted-line-continuation(n)
  #     | flow-folded-whitespace(n)
  #   )
  #   (
  #     non-space-double-quoted-character
  #     double-quoted-first-line
  #     (
  #         double-quoted-next-line(n)
  #       | blank-character*
  #     )
  #   )?

  double_quoted_next_line: (n)->
    @all(
      @any(
        [ @double_quoted_line_continuation, n ]
        [ @flow_folded_whitespace, n ]
      )
      @rep('?',
        @all(
          @non_space_double_quoted_character
          @double_quoted_first_line
          @any(
            [ @double_quoted_next_line, n ]
            @rgx(/// #{blank_character}* ///)
          )
        )
      )
    )



  # [083]
  # non-space-double-quoted-character ::=
  #     non-break-double-quoted-character
  #   - blank-character

  non_space_double_quoted_character: ->
    @rgx(non_space_double_quoted_character)

  [  non_space_double_quoted_character] = init ->
    [non_space_double_quoted_character] = make ///
      (! #{blank_character})
      #{non_break_double_quoted_character}
    ///



  # [084]
  # non-break-double-quoted-character ::=
  #     double-quoted-scalar-escape-character
  #   | (
  #         json-character
  #       - '\'
  #       - '"'
  #     )

  [  non_break_double_quoted_character] = init ->
    [non_break_double_quoted_character] = make ///
      (:
        #{double_quoted_scalar_escape_character}
      |
        (! [ \\ " ])
        #{json_character}
      )
    ///



  # [085]
  # double-quoted-line-continuation(n) ::=
  #   blank-character*
  #   '\'
  #   line-break
  #   empty-line(n,FLOW-IN)*
  #   indentation-spaces-plus-maybe-more(n)

  double_quoted_line_continuation: (n)->
    @all(
      @rgx( ///
        #{blank_character}*
        \\
        #{line_break}
      ///)
      @rep('*', [ @empty_line, n, "FLOW-IN" ])
      [ @indentation_spaces_plus_maybe_more, n ]
    )



  # [086]  # XXX fix typo in 1.3.0 spec
  # flow-mapping-context(n,FLOW-OUT)  ::= flow-sequence-entries(n,FLOW-IN)
  # flow-mapping-context(n,FLOW-IN)   ::= flow-sequence-entries(n,FLOW-IN)
  # flow-mapping-context(n,BLOCK-KEY) ::= flow-sequence-entries(n,FLOW-KEY)
  # flow-mapping-context(n,FLOW-KEY)  ::= flow-sequence-entries(n,FLOW-KEY)

  flow_mapping_context: (n, c)->
    switch c
      when 'FLOW-OUT'  then @flow_mapping_entries(n, "FLOW-IN")
      when 'FLOW-IN'   then @flow_mapping_entries(n, "FLOW-IN")
      when 'BLOCK-KEY' then @flow_mapping_entries(n, "FLOW-KEY")
      when 'FLOW-KEY'  then @flow_mapping_entries(n, "FLOW-KEY")



  # [087]
  # flow-sequence-context(n,FLOW-OUT)  ::= flow-sequence-entries(n,FLOW-IN)
  # flow-sequence-context(n,FLOW-IN)   ::= flow-sequence-entries(n,FLOW-IN)
  # flow-sequence-context(n,BLOCK-KEY) ::= flow-sequence-entries(n,FLOW-KEY)
  # flow-sequence-context(n,FLOW-KEY)  ::= flow-sequence-entries(n,FLOW-KEY)

  flow_sequence_context: (n, c)->
    switch c
      when 'FLOW-OUT'  then @flow_sequence_entries(n, "FLOW-IN")
      when 'FLOW-IN'   then @flow_sequence_entries(n, "FLOW-IN")
      when 'BLOCK-KEY' then @flow_sequence_entries(n, "FLOW-KEY")
      when 'FLOW-KEY'  then @flow_sequence_entries(n, "FLOW-KEY")



  # [088]
  # single-quoted-scalar(n,c) ::=
  #   "'"
  #   single-quoted-text(n,c)
  #   "'"

  single_quoted_scalar: (n, c)->
    @got(
      @all(
        @chr("'")
        [ @single_quoted_text, n, c ]
        @chr("'")
      )
    )



  # [089]
  # single-quoted-text(BLOCK-KEY) ::= single-quoted-one-line
  # single-quoted-text(FLOW-KEY)  ::= single-quoted-one-line
  # single-quoted-text(FLOW-OUT)  ::= single-quoted-multi-line(n)
  # single-quoted-text(FLOW-IN)   ::= single-quoted-multi-line(n)

  single_quoted_text: (n, c)->
    switch c
      when 'BLOCK-KEY' then @rgx(single_quoted_one_line)
      when 'FLOW-KEY'  then @rgx(single_quoted_one_line)
      when 'FLOW-OUT'  then @single_quoted_multi_line(n)
      when 'FLOW-IN'   then @single_quoted_multi_line(n)



  # [090]
  # single-quoted-multi-line(n) ::=
  #   single-quoted-first-line
  #   (
  #       single-quoted-next-line(n)
  #     | blank-character*
  #   )

  single_quoted_multi_line: (n)->
    @all(
      @rgx(single_quoted_first_line)
      @any(
        [ @single_quoted_next_line, n ]
        @rgx(/// #{blank_character}* ///)
      )
    )



  # [091]
  # single-quoted-one-line ::=
  #   non-break-single-quoted-character*

  [  single_quoted_one_line] = init ->
    [single_quoted_one_line] = make ///
      #{non_break_single_quoted_character}*
    ///



  # [092]
  # single-quoted-first-line ::=
  #   (
  #     blank-character*
  #     non-space-single-quoted-character
  #   )*

  [  single_quoted_first_line] = init ->
    [single_quoted_first_line] = make ///
      (:
        #{blank_character}*
        #{non_space_single_quoted_character}
      )*
    ///



  # [093]
  # single-quoted-next-line(n) ::=
  #   flow-folded-whitespace(n)
  #   (
  #     non-space-single-quoted-character
  #     single-quoted-first-line
  #     (
  #         single-quoted-next-line(n)
  #       | blank-character*
  #     )
  #   )?

  [  single_quoted_next_line] = init ->
    [single_quoted_next_line] = make ///
      #{non_space_single_quoted_character}
      #{single_quoted_first_line}
    ///
  , -1

  single_quoted_next_line: (n)->
    @all(
      [ @flow_folded_whitespace, n ]
      @rep('?',
        @all(
          @rgx(single_quoted_next_line)
          @any(
            [ @single_quoted_next_line, n ]
            @rgx(/// #{blank_character}* ///)
          )
        )
      )
    )



  # [094]
  # non-space-single-quoted-character ::=
  #     non-break-single-quoted-character
  #   - blank-character

  [  non_space_single_quoted_character] = init ->
    [non_space_single_quoted_character] = make ///
      (:
        (! #{blank_character})
        #{non_break_single_quoted_character}
      )
    ///



  # [095]
  # non-break-single-quoted-character ::=
  #     single-quoted-escaped-single-quote
  #   | (
  #         json-character
  #       - "'"
  #     )

  [  non_break_single_quoted_character] = init ->
    [non_break_single_quoted_character] = make ///
      (:
        #{single_quoted_escaped_single_quote}
      | (:
          (! ')
          #{json_character}
        )
      )
    ///



  # [096]
  # single-quoted-escaped-single-quote ::=
  #   "''"

  [single_quoted_escaped_single_quote] = make ///
    '
    '
  ///



  # [097]
  # flow-plain-scalar(n,FLOW-OUT)  ::= plain-scalar-multi-line(n,FLOW-OUT)
  # flow-plain-scalar(n,FLOW-IN)   ::= plain-scalar-multi-line(n,FLOW-IN)
  # flow-plain-scalar(n,BLOCK-KEY) ::= plain-scalar-single-line(BLOCK-KEY)
  # flow-plain-scalar(n,FLOW-KEY)  ::= plain-scalar-single-line(FLOW-KEY)

  flow_plain_scalar: (n, c)->
    @got(
      =>
        switch c
          when 'FLOW-OUT'  then [ @plain_scalar_multi_line, n, c ]
          when 'FLOW-IN'   then [ @plain_scalar_multi_line, n, c ]
          when 'BLOCK-KEY' then [ @plain_scalar_single_line, c ]
          when 'FLOW-KEY'  then [ @plain_scalar_single_line, c ]
    )



  # [098]
  # plain-scalar-multi-line(n,c) ::=
  #   plain-scalar-single-line(c)
  #   plain-scalar-next-line(n,c)*

  plain_scalar_multi_line: (n, c)->
    @all(
      @plain_scalar_single_line(c)
      @rep('*', @plain_scalar_next_line(n, c))
    )



  # [099]
  # plain-scalar-single-line(c) ::=
  #   plain-scalar-first-character(c)
  #   plain-scalar-line-characters(c)

  plain_scalar_single_line: (c)->
    @all(
      @plain_scalar_first_character(c)
      @plain_scalar_line_characters(c)
    )



  # [100]
  # plain-scalar-next-line(n,c) ::=
  #   flow-folded-whitespace(n)
  #   plain-scalar-characters(c)
  #   plain-scalar-line-characters(c)

  plain_scalar_next_line: (n, c)->
    @all(
      @flow_folded_whitespace(n)
      @plain_scalar_characters(c)
      @plain_scalar_line_characters(c)
    )



  # [101]
  # plain-scalar-line-characters(c) ::=
  #   (
  #     blank-character*
  #     plain-scalar-characters(c)
  #   )*

  plain_scalar_line_characters: (c)->
    @rgx(///
      (:
        #{blank_character}*
        #{@plain_scalar_characters_re(c)}
      )*
    ///u)



  # [102]
  # plain-scalar-first-character(c) ::=
  #     (
  #         non-space-character
  #       - '?'                         # Mapping key
  #       - ':'                         # Mapping value
  #       - '-'                         # Sequence entry
  #       - '{'                         # Mapping start
  #       - '}'                         # Mapping end
  #       - '['                         # Sequence start
  #       - ']'                         # Sequence end
  #       - ','                         # Entry separator
  #       - '#'                         # Comment
  #       - '&'                         # Anchor
  #       - '*'                         # Alias
  #       - '!'                         # Tag
  #       - '|'                         # Literal scalar
  #       - '>'                         # Folded scalar
  #       - "'"                         # Single quote
  #       - '"'                         # Double quote
  #       - '%'                         # Directive
  #       - '@'                         # Reserved
  #       - '`'                         # Reserved
  #     )
  #   | (
  #       ( '?' | ':' | '-' )
  #       [ lookahead = non-space-plain-scalar-character(c) ]
  #     )

  plain_scalar_first_character: (c)->
    @rgx(///
      (:
        (!
          [
            -
            ?
            :
            ,
            [
            \]
            {
            }
            \x23     # '#'
            &
            *
            !
            |
            >
            '
            "
            %
            @
            `
          ]
        )
        #{non_space_character}
      | (:
          [
            ?
            :
            -
          ]
          (= #{@non_space_plain_scalar_character(c)} )
        )
      )
    ///u)



  # [103]
  # plain-scalar-characters(c) ::=
  #     (
  #         non-space-plain-scalar-character(c)
  #       - ':'
  #       - '#'
  #     )
  #   | (
  #       [ lookbehind = non-space-character ]
  #       '#'
  #     )
  #   | (
  #       ':'
  #       [ lookahead = non-space-plain-scalar-character(c) ]
  #     )

  plain_scalar_characters_re: (c)->
    non_space_plain_scalar_character = @non_space_plain_scalar_character(c)
    [plain_scalar_characters] = make ///
      (:
        (:
          (! [ : \x23 ] )
          #{non_space_plain_scalar_character}
        )
      | (:
          (<= #{non_space_character} )
          \x23
        )
      | (:
          :
          (= #{non_space_plain_scalar_character} )
        )
      )
    ///u
    plain_scalar_characters

  plain_scalar_characters: (c)->
    @rgx(/// #{@plain_scalar_characters_re(c)} ///u)



  # [104]
  # non-space-plain-scalar-character(FLOW-OUT)  ::= block-plain-scalar-character
  # non-space-plain-scalar-character(FLOW-IN)   ::= flow-plain-scalar-character
  # non-space-plain-scalar-character(BLOCK-KEY) ::= block-plain-scalar-character
  # non-space-plain-scalar-character(FLOW-KEY)  ::= flow-plain-scalar-character

  non_space_plain_scalar_character: (c)->
    switch c
      when 'FLOW-OUT'  then @block_plain_scalar_character()
      when 'FLOW-IN'   then @flow_plain_scalar_character()
      when 'BLOCK-KEY' then @block_plain_scalar_character()
      when 'FLOW-KEY'  then @flow_plain_scalar_character()



  # [105]
  # block-plain-scalar-character ::=
  #   non-space-character

  block_plain_scalar_character: ->
    [re] = make ///
      (: #{non_space_character} )
    ///u
    re



  # [106]
  # flow-plain-scalar-character ::=
  #     non-space-characters
  #   - flow-collection-indicators

  flow_plain_scalar_character: ->
    [re] = make ///
      (:
        (!
          #{flow_collection_indicator}
        )
        #{non_space_character}
      )
    ///u
    re



  # [107]
  # alias-node ::=
  #   '*'
  #   anchor-name

  alias_node: ->
    @got(
      @rgx(///
        \*
        #{anchor_name}
      ///u)
    )



  # [108]
  # empty-node ::=
  #   ""

  empty_node: ->
    @got(
      @empty
    )



  # [109]
  # indentation-spaces(0) ::=
  #   ""

  indentation_spaces: ->
    @rgx(/// #{space_character}* ///)

  # indentation-spaces(n+1) ::=
  #   space-character
  #   indentation-spaces(n)

  # When n≥0

  indentation_spaces_n = memoize (n)->
    String(/// (: #{space_character}{#{n}} ) ///y)[1..-3]

  indentation_spaces_n: (n)->
    @rgx(/// #{space_character}{#{n}} ///)



  # [110]
  # indentation-spaces-less-than(1) ::=
  #   ""

  # # When n≥1

  indentation_spaces_less_than: (n)->
    @all(
      @indentation_spaces()
      @lt(@len(@match), n)
    )



  # [111]
  # indentation-spaces-less-or-equal(0) ::=
  #   ""

  # # When n≥0

  indentation_spaces_less_or_equal: (n)->
    @all(
      @indentation_spaces()
      @le(@len(@match), n)
    )



  # [112]
  # line-prefix-spaces(n,BLOCK-OUT) ::= indentation-spaces-exact(n)
  # line-prefix-spaces(n,BLOCK-IN)  ::= indentation-spaces-exact(n)
  # line-prefix-spaces(n,FLOW-OUT)  ::= indentation-spaces-plus-maybe-more(n)
  # line-prefix-spaces(n,FLOW-IN)   ::= indentation-spaces-plus-maybe-more(n)

  line_prefix_spaces: (n, c)->
    switch c
      when 'BLOCK-OUT' then @indentation_spaces_exact(n)
      when 'BLOCK-IN'  then @indentation_spaces_exact(n)
      when 'FLOW-OUT'  then @indentation_spaces_plus_maybe_more(n)
      when 'FLOW-IN'   then @indentation_spaces_plus_maybe_more(n)



  # [113]
  # indentation-spaces-exact(n) ::=
  #   indentation-spaces(n)

  indentation_spaces_exact: (n)->
    @indentation_spaces_n(n)



  # [114]
  # indentation-spaces-plus-maybe-more(n) ::=
  #   indentation-spaces(n)
  #   separation-blanks?

  indentation_spaces_plus_maybe_more = memoize (n)->
    [re] = make ///
      #{indentation_spaces_n(n)}
      #{separation_blanks}?
    ///
    re

  indentation_spaces_plus_maybe_more: (n)->
    @rgx(indentation_spaces_plus_maybe_more(n))



  # [115]
  # flow-folded-whitespace(n) ::=
  #   separation-blanks?
  #   folded-whitespace(n,FLOW-IN)
  #   indentation-spaces-plus-maybe-more(n)

  flow_folded_whitespace: (n)->
    @all(
      @rgx(/// #{separation_blanks}? ///)
      @folded_whitespace(n, "FLOW-IN")
      @indentation_spaces_plus_maybe_more(n)
    )



  # [116]
  # folded-whitespace(n,c) ::=
  #     (
  #       line-break
  #       empty-line(n,c)+
  #     )
  #   | break-as-space

  folded_whitespace: (n, c)->
    @any(
      @all(
        @rgx(line_break)
        @rep('+', @empty_line(n, c))
      )
      @rgx(break_as_space)
    )



  # [117]
  # comment-lines ::=
  #   (
  #     comment-line
  #   | <start-of-line>
  #   blanks-and-comment-line*
  #   )

  comment_lines: ->
    @rgx(comment_lines)

  [   comment_lines] = init ->
     [comment_lines] = make ///
       (:
         #{comment_line}
       | #{start_of_line}
       )
       #{blanks_and_comment_line}*
     ///u



  # [118]
  # comment-line ::=
  #   (
  #     separation-blanks
  #     comment-content?
  #   )?
  #   line-ending

  comment_line: ->
    @rgx(comment_line)

  [   comment_line] = init ->
     [comment_line] = make ///
       (:
         (:
           #{separation_blanks}
           #{comment_content}?
         )?
         #{line_ending}
       )
     ///u



  # [118b]          # TODO Renumber after spec updated
  # blanks-and-comment-line ::=
  #   separation-blanks
  #   comment-content?
  #   line-ending

  blanks_and_comment_line: ->
    @rgx(blanks_and_comment_line)

  [  blanks_and_comment_line] = init ->
    [blanks_and_comment_line] = make ///
      (:
        #{separation_blanks}
        #{comment_content}?
        #{line_ending}
      )
    ///u



  # [119]
  # comment-content ::=
  #   '#'
  #   non-break-character*

  [  comment_content] = init ->
    [comment_content] = make ///
      (:
        \x23
        #{non_break_character}*
      )
    ///u




  # [120]
  # empty-line(n,c) ::=
  #   (
  #       line-prefix-spaces(n,c)
  #     | indentation-spaces-less-than(n)
  #   )
  #   break-as-line-feed

  empty_line: (n, c)->
    @got(
      @all(
        @any(
          [ @line_prefix_spaces, n, c ]
          @indentation_spaces_less_than(n)
        )
        @rgx(break_as_line_feed)
      )
    )



  # [121]
  # separation-characters(n,BLOCK-OUT) ::= separation-lines(n)
  # separation-characters(n,BLOCK-IN)  ::= separation-lines(n)
  # separation-characters(n,FLOW-OUT)  ::= separation-lines(n)
  # separation-characters(n,FLOW-IN)   ::= separation-lines(n)
  # separation-characters(n,BLOCK-KEY) ::= separation-blanks
  # separation-characters(n,FLOW-KEY)  ::= separation-blanks

  separation_characters: (n, c)->
    switch c
      when 'BLOCK-OUT' then @separation_lines(n)
      when 'BLOCK-IN'  then @separation_lines(n)
      when 'FLOW-OUT'  then @separation_lines(n)
      when 'FLOW-IN'   then @separation_lines(n)
      when 'BLOCK-KEY' then @separation_blanks()
      when 'FLOW-KEY'  then @separation_blanks()



  # [122]
  # separation-lines(n) ::=
  #     (
  #       comment-lines
  #       indentation-spaces-plus-maybe-more(n)
  #     )
  #   | separation-blanks

  separation_lines: (n)->
    @rgx(///
      (:
        (:
          #{comment_lines}
          #{indentation_spaces_plus_maybe_more(n)}
        )
      | #{separation_blanks}
      )
    ///u)



  # [123]
  # separation-blanks ::=
  #     blank-character+
  #   | <start-of-line>

  [  separation_blanks] = init ->
    [separation_blanks] = make ///(:
        #{blank_character}+
      | #{start_of_line}
    )///

  separation_blanks: ->
    @rgx(separation_blanks)



  # [124]
  # yaml-directive-line ::=
  #   "YAML"
  #   separation-blanks
  #   yaml-version-number

  yaml_directive_line: ->
    @all(
      @rgx(///
        (:
          Y A M L
          #{separation_blanks}
        )
      ///)
      @yaml_version_number
    )



  # [125]
  # yaml-version-number ::=
  #   decimal-digit+
  #   '.'
  #   decimal-digit+

  yaml_version_number: ->
    @got(
      @rgx(///
        #{decimal_digit}+
        \.
        #{decimal_digit}+
      ///)
    )



  # [126]
  # reserved-directive-line ::=
  #   directive-name
  #   (
  #     separation-blanks
  #     directive-parameter
  #   )*

  reserved_directive_line: ->
    @rgx(///
      #{directive_name}
      (:
        #{separation_blanks}
        #{directive_parameter}
      )*
    ///u)



  # [127]
  # directive-name ::=
  #   non-space-character+

  [  directive_name] = init ->
    [directive_name] = make ///
      #{non_space_character}+
    ///u



  # [128]
  # directive-parameter ::=
  #   non-space-character+

  [  directive_parameter] = init ->
    [directive_parameter] = make ///
      #{non_space_character}+
    ///u



  # [129]
  # tag-directive-line ::=
  #   "TAG"
  #   separation-blanks
  #   tag-handle
  #   separation-blanks
  #   tag-prefix

  tag_directive_line: ->
    @all(
      @rgx(///
        T A G
        #{separation_blanks}
      ///)
      @tag_handle
      @separation_blanks
      @tag_prefix
    )



  # [130]
  # tag-handle ::=
  #     named-tag-handle
  #   | secondary-tag-handle
  #   | primary-tag-handle

  [  tag_handle] = init ->
    [tag_handle] = make ///
      (:
        #{named_tag_handle}
      | #{secondary_tag_handle}
      | #{primary_tag_handle}
      )
    ///

  tag_handle: ->
    @got(
      @rgx(tag_handle)
    )



  # [131]
  # named-tag-handle ::=
  #   '!'
  #   word-character+
  #   '!'

  [  named_tag_handle] = init ->
    [named_tag_handle] = make ///
      !
      #{word_character}+
      !
    ///



  # [132]
  # secondary-tag-handle ::=
  #   "!!"

  secondary_tag_handle  = "!!"



  # [133]
  # primary-tag-handle ::=
  #   '!'

  primary_tag_handle  = "!"



  # [134]
  # tag-prefix ::=
  #     local-tag-prefix
  #   | global-tag-prefix

  tag_prefix: ->
    @got(
      @rgx(///
        (:
          #{local_tag_prefix}
        | #{global_tag_prefix}
        )
      ///)
    )



  # [135]
  # local-tag-prefix ::=
  #   '!'
  #   uri-character*

  [  local_tag_prefix] = init ->
    [local_tag_prefix] = make ///
      !
      #{uri_character}*
    ///



  # [136]
  # global-tag-prefix ::=
  #   tag-character
  #   uri-character*

  [  global_tag_prefix] = init ->
    [global_tag_prefix] = make ///
      #{tag_character}
      #{uri_character}*
    ///



  # [137]
  # node-properties(n,c) ::=
  #     (
  #       anchor-property
  #       (
  #         separation-characters(n,c)
  #         tag-property
  #       )?
  #     )
  #   | (
  #       tag-property
  #       (
  #         separation-characters(n,c)
  #         anchor-property
  #       )?
  #     )

  [check_node_properties] = make ///
    (= [ ! & ] )
  ///

  check_node_properties: ->
    @rgx(check_node_properties)

  node_properties: (n, c)->
    @all(
      @check_node_properties
      @any(
        @all(
          @tag_property
          @rep('?',
            @all(
              @separation_characters(n, c)
              @anchor_property
            )
          )
        )
        @all(
          @anchor_property
          @rep('?',
            @all(
              @separation_characters(n, c)
              @tag_property
            )
          )
        )
      )
    )



  # [138]
  # anchor-property ::=
  #   '&'
  #   anchor-name

  anchor_property: ->
    @got(
      @rgx(///
        &
        #{anchor_name}
      ///u)
    )



  # [139]
  # anchor-name ::=
  #   anchor-character+

  [  anchor_name] = init ->
    [anchor_name] = make ///
      (:
        #{anchor_character}
      )+
    ///u
  , -4



  # [140]
  # anchor-character ::=
  #     non-space-character
  #   - flow-collection-indicators

  [  anchor_character] = init ->
    [anchor_character] = make ///
      (:
        (!
          #{flow_collection_indicator}
        )
        #{non_space_character}
      )+
    ///u
  , -4



  # [141]
  # tag-property ::=
  #     verbatim-tag
  #   | shorthand-tag
  #   | non-specific-tag

  tag_property: ->
    @got(
      @rgx(///
          #{verbatim_tag}
        | #{shorthand_tag}
        | #{non_specific_tag}
      ///)
    )



  # [142]
  # verbatim-tag ::=
  #   "!<"
  #   uri-character+
  #   '>'

  [  verbatim_tag] = init ->
    [verbatim_tag] = make ///
      ! <
        #{uri_character}+
      >
    ///
  , -4



  # [143]
  # shorthand-tag ::=
  #   tag-handle
  #   tag-character+

  [  shorthand_tag] = init ->
    [shorthand_tag] = make ///
      #{tag_handle}
      #{tag_character}+
    ///
  , -4



  # [144]
  # non-specific-tag ::=
  #   '!'

  non_specific_tag = "!"



  # [145]
  # byte-order-mark ::=
  #   xFEFF

  byte_order_mark  = "\u{FEFF}"



  # [146]
  # yaml-character ::=
  #                                     # 8 bit
  #     x09                             # Tab
  #   | x0A                             # Line feed
  #   | x0D                             # Carriage return
  #   | [x20-x7E]                       # Printable ASCII
  #                                     # 16 bit
  #   | x85                             # Next line (NEL)
  #   | [xA0-xD7FF]                     # Basic multilingual plane (BMP)
  #   | [xE000-xFFFD]                   # Additional unicode areas
  #   | [x010000-x10FFFF]               # 32 bit

  [yaml_character] = make ///
    [
      \x09
      \x0A
      \x0D
      \x20-\x7E
      \x85
      \xA0-\uD7FF
      \uE000-\uFFFD
      \u{10000}-\u{10FFFF}
    ]
  ///u



  # [147]
  # json-character ::=
  #     x09                             # Tab
  #   | [x20-x10FFFF]                   # Non-C0-control characters

  [json_character] = make ///
    [
      \x09
      \x20-\u{10FFFF}
    ]
  ///u



  # [148]
  # non-space-character ::=
  #     non-break-character
  #   - blank-character

  [  non_space_character] = init ->
    [non_space_character] = make ///
      (:
        (!
          #{blank_character}
        )
        #{non_break_character}
      )
    ///u



  # [149]
  # non-break-character ::=
  #     yaml-character
  #   - x0A
  #   - x0D
  #   - byte-order-mark

  [non_break_character] = make ///
    (:
      (!
        [
          \x0A
          \x0D
          #{byte_order_mark}
        ]
      )
      #{yaml_character}
    )
  ///u



  # [150]
  # blank-character ::=
  #     x20                             # Space
  #   | x09                             # Tab

  [  blank_character, ws_lookahead] = init ->
    [blank_character] = make ///
      [
        #{space_character}
        \t
      ]
    ///

    [ws_lookahead] = make ///
      (=
        #{end_of_input}
      | #{blank_character}
      | #{line_break}
      )
    ///

  ws_lookahead: ->
    @rgx(ws_lookahead)



  # [151]
  # space-character ::=
  #   x20

  space_character  = "\x20"



  # [152]
  # line-ending ::=
  #     line-break
  #   | <end-of-input>

  [  line_ending] = init ->
    [line_ending] = make ///
      (:
        #{line_break}
      | #{end_of_input}
      )
    ///



  # [153]
  # break-as-space ::=
  #   line-break

  [ break_as_space] = init ->
    break_as_space  = line_break



  # [154]
  # break-as-line-feed ::=
  #   line-break

  [ break_as_line_feed] = init ->
    break_as_line_feed  = line_break



  # [155]
  # line-break ::=
  #     (
  #       x0D                           # Carriage return
  #       x0A                           # Line feed
  #     )
  #   | x0D
  #   | x0A

  [line_break] = make ///
    (:
      (:
        \x0D
        \x0A
      )
    | \x0D
    | \x0A
    )
  ///



  # XXX Rename to flow-collection-indicator
  # [156]
  # flow-collection-indicators ::=
  #     '{'                             # Flow mapping start
  #   | '}'                             # Flow mapping end
  #   | '['                             # Flow sequence start
  #   | ']'                             # Flow sequence end

  # [156] 023
  # c-flow-indicator ::=
  #   ',' | '[' | ']' | '{' | '}'

  [flow_collection_indicator, flow_collection_indicator_s] = make ///
    [
      ,
      [
      \]
      {
      }
    ]
  ///



  # [157]
  # double-quoted-scalar-escape-character ::=
  #   '\'
  #   (
  #       '0'
  #     | 'a'
  #     | 'b'
  #     | 't' | x09
  #     | 'n'
  #     | 'v'
  #     | 'f'
  #     | 'rgx'
  #     | 'e'
  #     | x20
  #     | '"'
  #     | '/'
  #     | '\'
  #     | 'N'
  #     | '_'
  #     | 'L'
  #     | 'P'
  #     | ( 'x' hexadecimal-digit{2} )
  #     | ( 'u' hexadecimal-digit{4} )
  #     | ( 'U' hexadecimal-digit{8} )
  #   )

  [  double_quoted_scalar_escape_character] = init ->
    [double_quoted_scalar_escape_character] = make ///
      \\
      (:
        [
          0
          a
          b
          t
          \t
          n
          v
          f
          rgx
          e
          \x20
          "
          /
          \\
          N
          _
          L
          P
        ]
      | x #{hexadecimal_digit}{2}
      | u #{hexadecimal_digit}{4}
      | U #{hexadecimal_digit}{8}
      )
    ///



  # [158]
  # tag-character ::=
  #     uri-character
  #   - '!'
  #   - flow-collection-indicators

  [  tag_character] = init ->
    [tag_character] = make ///
      (:
        (!
          [
            !
            #{flow_collection_indicator_s}
          ]
        )
        #{uri_character}
      )
    ///



  # [159]
  # uri-character ::=
  #     (
  #       '%'
  #       hexadecimal-digit{2}
  #     )
  #   | word-character
  #   | '#'
  #   | ';'
  #   | '/'
  #   | '?'
  #   | ':'
  #   | '@'
  #   | '&'
  #   | '='
  #   | '+'
  #   | '$'
  #   | ','
  #   | '_'
  #   | '.'
  #   | '!'
  #   | '~'
  #   | '*'
  #   | "'"
  #   | '('
  #   | ')'
  #   | '['
  #   | ']'

  [  uri_character] = init ->
    [uri_character] = make ///
      (:
        % #{hexadecimal_digit}{2}
      | [
          #{word_character_s}
          \x23
          ;
          /
          ?
          :
          @
          &
          =
          +
          $
          ,
          _
          .
          !
          ~
          *
          '
          (
          )
          [
          \]
        ]
      )
    ///



  # [160]
  # word-character ::=
  #     decimal-digit
  #   | ascii-alpha-character
  #   | '-'

  [  word_character, word_character_s] = init ->
    [word_character, word_character_s] = make ///
      [
        #{decimal_digit_s}
        #{ascii_alpha_character_s}
        \-
      ]
    ///



  # [161]
  # hexadecimal-digit ::=
  #     decimal-digit
  #   | [x41-x46]                       # A-F
  #   | [x61-x66]                       # a-f

  [  hexadecimal_digit] = init ->
    [hexadecimal_digit] = make ///
      [
        #{decimal_digit_s}
        A - F
        a - f
      ]
    ///



  # [162]
  # decimal-digit ::=
  #   [x30-x39]                         # 0-9

  [decimal_digit, decimal_digit_s] = make ///
    [
      0 - 9
    ]
  ///



  # [163]
  # decimal-digit-1-9 ::=
  #   [x31-x39]                         # 0-9

  [decimal_digit_1_9] = make ///
    [
      0 - 9
    ]
  ///



  # [164]
  # ascii-alpha-character ::=
  #     [x41-x5A]                       # A-Z
  #   | [x61-x7A]                       # a-z

  [, ascii_alpha_character_s] = make ///
    [
      A - Z
      a - z
    ]
  ///


  # Call the variable initialization functions in the order needed for
  # JavaScript to be correct.
  init() for init in inits.reverse()

