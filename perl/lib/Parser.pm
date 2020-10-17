###
# This is a parser class. It has a parse() method and parsing primitives for
# the grammar. It calls methods in the receiver class, when a rule matches:
###

use v5.12;

package Parser;

use Prelude;
use Grammar;

use base 'Grammar';

use constant TRACE => $ENV{TRACE};

sub new {
  my ($class, $receiver) = @_;

  my $self = bless {
    receiver => $receiver,
    pos => 0,
    end => 0,
    state => [],
    trace_num => 0,
    trace_line => 0,
    trace_on => true,
    trace_off => 0,
    trace_info => ['', '', ''],
  }, $class;

  $receiver->{parser} = $self;

  return $self;
}

sub parse {
  my ($self, $input) = @_;
  $self->{input} = $input;

  $self->{end} = length $self->{input};

  $self->{trace_on} = not $self->trace_start if TRACE;

  my $ok;
  eval {
    $ok = $self->call($self->func('TOP'));
    $self->trace_flush;
  };
  if ($@) {
    $self->trace_flush;
    die $@;
  }

  die "Parser failed" if not $ok;
  die "Parser finished before end of input"
    if $self->{pos} < $self->{end};

  return true;
}

sub state_curr {
  my ($self) = @_;
  $self->{state}[-1] || {
    name => undef,
    doc => false,
    lvl => 0,
    beg => 0,
    end => 0,
    m => undef,
    t => undef,
  };
}

sub state_prev {
  my ($self) = @_;
  $self->{state}[-2]
}

sub state_push {
  my ($self, $name) = @_;

  my $curr = $self->state_curr;

  push @{$self->{state}}, {
    name => $name,
    doc => $curr->{doc},
    lvl => $curr->{lvl} + 1,
    beg => $self->{pos},
    end => undef,
    m => $curr->{m},
    t => $curr->{t},
  };
}

sub state_pop {
  my ($self) = @_;
  my $child = pop @{$self->{state}};
  my $curr = $self->state_curr;
  return unless defined $curr;
  $curr->{beg} = $child->{beg};
  $curr->{end} = $self->{pos};
}

sub call {
  my ($self, $func, $type) = @_;
  $type //= 'boolean';

  my $args = [];
  ($func, @$args) = @$func if isArray $func;

  return $func if isNumber $func or isString $func;

  FAIL "Bad call type '${\ typeof $func}' for '$func'"
    unless isFunction $func;

  my $trace = $func->{trace} //= $func->{name};

  $self->state_push($trace);

  $self->{trace_num}++;
  $self->trace('?', $trace, $args) if TRACE;

  if ($func->{name} eq 'l_bare_document') {
    $self->state_curr->{doc} = true;
  }

  @$args = map {
    isArray($_) ? $self->call($_, 'any') :
    isFunction($_) ? $_->{func}->() :
    $_;
  } @$args;

  my $pos = $self->{pos};
  $self->receive($func, 'try', $pos);

  my $value = $func->{func}->($self, @$args);
  while (isFunction($value) or isArray($value)) {
    $value = $self->call($value);
  }

  FAIL "Calling '$trace' returned '${\ typeof($value)}' instead of '$type'"
    if $type ne 'any' and typeof($value) ne $type;

  $self->{trace_num}++;
  if ($type ne 'boolean') {
    $self->trace('>', $value) if TRACE;
  }
  else {
    if ($value) {
      $self->trace('+', $trace) if TRACE;
      $self->receive($func, 'got', $pos);
    }
    else {
      $self->trace('x', $trace) if TRACE;
      $self->receive($func, 'not', $pos);
    }
  }

  $self->state_pop;
  return $value;
}

sub receive {
  my ($self, $func, $type, $pos) = @_;

  $func->{receivers} //= $self->make_receivers;
  my $receiver = $func->{receivers}{$type};
  return unless $receiver;

  $receiver->($self->{receiver}, {
    text => substr($self->{input}, $pos, $self->{pos}-$pos),
    state => $self->state_curr,
    start => $pos,
  });
}

sub make_receivers {
  my ($self) = @_;
  my $i = @{$self->{state}};
  my $names = [];
  my $n;
  while ($i > 0 and not(($n = $self->{state}[--$i]{name}) =~ /_/)) {
    if ($n =~ /^chr\((.)\)$/) {
      $n = hex_char $1;
    }
    else {
      $n =~ s/\(.*//;
    }
    unshift @$names, $n;
  }
  my $name = join '__', $n, @$names;

  return {
    try => $self->{receiver}->can("try__$name"),
    got => $self->{receiver}->can("got__$name"),
    not => $self->{receiver}->can("not__$name"),
  };
}

# Match all subrule methods:
sub all {
  my ($self, @funcs) = @_;
  name all => sub {
    my $pos = $self->{pos};
    for my $func (@funcs) {
      FAIL '*** Missing function in @all group:', \@funcs
        unless defined $func;

      if (not $self->call($func)) {
        $self->{pos} = $pos;
        return false;
      }
    }

    return true;
  };
}

# Match any subrule method. Rules are tried in order and stops on first match:
sub any {
  my ($self, @funcs) = @_;
  name any => sub {
    for my $func (@funcs) {
      if ($self->call($func)) {
        return true;
      }
    }

    return false;
  };
}

sub may {
  my ($self, $func) = @_;
  name may => sub {
    $self->call($func);
  };
}

# Repeat a rule a certain number of times:
sub rep {
  my ($self, $min, $max, $func) = @_;
  FAIL "rep max is < 0 '$max'"
    if defined $max and $max < 0;
  name rep => sub {
    my $count = 0;
    my $pos = $self->{pos};
    my $pos_start = $pos;
    while (not(defined $max) or $count < $max) {
      last unless $self->call($func);
      last if $self->{pos} == $pos;
      $count++;
      $pos = $self->{pos};
    }
    if ($count >= $min and (not(defined $max) or $count <= $max)) {
      return true;
    }
    $self->{pos} = $pos_start;
    return false;
  }, "rep($min,${\ ($max // 'null')})";
}
sub rep2 {
  my ($self, $min, $max, $func) = @_;
  FAIL "rep2 max is < 0 '$max'"
    if defined $max and $max < 0;
  name rep2 => sub {
    my $count = 0;
    my $pos = $self->{pos};
    my $pos_start = $pos;
    while (not(defined $max) or $count < $max) {
      last unless $self->call($func);
      last if $self->{pos} == $pos;
      $count++;
      $pos = $self->{pos};
    }
    if ($count >= $min and (not(defined $max) or $count <= $max)) {
      return true;
    }
    $self->{pos} = $pos_start;
    return false;
  }, "rep2($min,${\ ($max // 'null')})";
}

# Call a rule depending on state value:
sub case {
  my ($self, $var, $map) = @_;
  name case => sub {
    my $rule = $map->{$var};
    defined $rule or
      FAIL "Can't find '$var' in:", $map;
    $self->call($rule);
  }, "case($var,${\ stringify $map})";
}

# Call a rule depending on state value:
sub flip {
  my ($self, $var, $map) = @_;
  my $value = $map->{$var};
  defined $value or
    FAIL "Can't find '$var' in:", $map;
  return $value if not ref $value;
  return $self->call($value, 'number');
}
name flip => \&flip;

sub the_end {
  my ($self) = @_;
  return (
    $self->{pos} >= $self->{end} or (
      $self->state_curr->{doc} and
      $self->start_of_line and
      substr($self->{input}, $self->{pos}) =~
        /^(?:---|\.\.\.)(?=\s|\z)/
    )
  );
}

# Match a single char:
sub chr {
  my ($self, $char) = @_;
  name chr => sub {
    return false if $self->the_end;
    if (
      $self->{pos} >= $self->{end} or (
        $self->state_curr->{doc} and
        $self->start_of_line and
        substr($self->{input}, $self->{pos}) =~
          /^(?:---|\.\.\.)(?=\s|\z)/
      )
    ) {
      return false;
    }
    if (substr($self->{input}, $self->{pos}, 1) eq $char) {
      $self->{pos}++;
      return true;
    }
    return false;
  }, "chr(${\ stringify($char)})";
}

# Match a char in a range:
sub rng {
  my ($self, $low, $high) = @_;
  name rng => sub {
    return false if $self->the_end;
    if (
      $low le substr($self->{input}, $self->{pos}, 1) and
      substr($self->{input}, $self->{pos}, 1) le $high
    ) {
      $self->{pos}++;
      return true;
    }
    return false;
  }, "rng(${\ stringify($low)},${\ stringify($high)})";
}

# Must match first rule but none of others:
sub but {
  my ($self, @funcs) = @_;
  name but => sub {
    return false if $self->the_end;
    my $pos1 = $self->{pos};
    return false unless $self->call($funcs[0]);
    my $pos2 = $self->{pos};
    $self->{pos} = $pos1;
    for my $func (@funcs[1..$#funcs]) {
      if ($self->call($func)) {
        $self->{pos} = $pos1;
        return false;
      }
    }
    $self->{pos} = $pos2;
    return true;
  }
}

sub chk {
  my ($self, $type, $expr) = @_;
  name chk => sub {
    my $pos = $self->{pos};
    $self->{pos}-- if $type eq '<=';
    my $ok = $self->call($expr);
    $self->{pos} = $pos;
    return $type eq '!' ? not($ok) : $ok;
  }, "chk($type, ${\ stringify $expr})";
}

sub set {
  my ($self, $var, $expr) = @_;
  name set => sub {
    my $value = $self->call($expr, 'any');
    return false if $value == -1;
    $value = $self->auto_detect if $value eq 'auto-detect';
    my $state = $self->state_prev;
    $state->{$var} = $value;
    if ($state->{name} ne 'all') {
      my $size = @{$self->{state}};
      for (my $i = 3; $i < $size; $i++) {
        FAIL "failed to traverse state stack in 'set'"
          if $i > $size - 2;
        $state = $self->{state}[0 - $i];
        $state->{$var} = $value;
        last if $state->{name} eq 's_l_block_scalar';
      }
    }
    return true;
  }, "set('$var', ${\ stringify $expr})";
}

sub max {
  my ($self, $max) = @_;
  name max => sub {
    return true;
  };
}

sub exclude {
  my ($self, $rule) = @_;
  name exclude => sub {
    return true;
  };
}

sub add {
  my ($self, $x, $y) = @_;
  name add => sub {
    $y = $self->call($y, 'number') if isFunction $y;
    FAIL "y is '${\ stringify $y}', not number in 'add'"
      unless isNumber $y;
    return $x + $y;
  }, "add($x,${\ stringify $y})";
}

sub sub {
  my ($self, $x, $y) = @_;
  name sub => sub {
    return $x - $y;
  }, "sub($x,$y)";
}

# This method does not need to return a function since it is never
# called in the grammar.
sub match {
  my ($self) = @_;
  my $state = $self->{state};
  my $i = @$state - 1;
  while ($i > 0 && not defined $state->[$i]{end}) {
    FAIL "Can't find match" if $i == 1;
    $i--;
  }

  my ($beg, $end) = @{$self->{state}[$i]}{qw<beg end>};
  return substr($self->{input}, $beg, ($end - $beg));
}
name match => \&match;

sub len {
  my ($self, $str) = @_;
  name len => sub {
    $str = $self->call($str, 'string') unless isString($str);
    return length $str;
  };
}

sub ord {
  my ($self, $str) = @_;
  name ord => sub {
    # Should be `$self->call($str, 'string')`, but... Perl
    $str = $self->call($str, 'number') unless isString($str);
    return ord($str) - 48;
  };
}

sub if {
  my ($self, $test, $do_if_true) = @_;
  name if => sub {
    $test = $self->call($test, 'boolean') unless isBoolean $test;
    if ($test) {
      $self->call($do_if_true);
      return true;
    }
    return false;
  };
}

sub lt {
  my ($self, $x, $y) = @_;
  name lt => sub {
    $x = $self->call($x, 'number') unless isNumber($x);
    $y = $self->call($y, 'number') unless isNumber($y);
    return $x < $y ? true : false;
  }, "lt(${\ stringify $x},${\ stringify $y})";
}

sub le {
  my ($self, $x, $y) = @_;
  name le => sub {
    $x = $self->call($x, 'number') unless isNumber($x);
    $y = $self->call($y, 'number') unless isNumber($y);
    return $x <= $y ? true : false;
  }, "le(${\ stringify $x},${\ stringify $y})";
}

sub m {
  my ($self) = @_;
  name m => sub {
    $self->state_curr->{m};
  };
}

sub t {
  my ($self) = @_;
  name t => sub {
    $self->state_curr->{t};
  };
}

#------------------------------------------------------------------------------
# Special grammar rules
#------------------------------------------------------------------------------
sub start_of_line {
  my ($self) = @_;
  (
    $self->{pos} == 0 ||
    $self->{pos} >= $self->{end} ||
    substr($self->{input}, $self->{pos} - 1, 1) eq "\n"
  ) ? true : false;
}
name 'start_of_line', \&start_of_line;

sub end_of_stream {
  my ($self) = @_;
  ($self->{pos} >= $self->{end}) ? true : false;
}
name 'end_of_stream', \&end_of_stream;

sub empty { true }
name 'empty', \&empty;

sub auto_detect_indent {
  my ($self, $n) = @_;
  substr($self->{input}, $self->{pos}) =~ /^(\ *)/;
  my $indent = length($1) - $n;
  return $indent > 0 ? $indent : -1;
}
name 'auto_detect_indent', \&auto_detect_indent;

sub auto_detect {
  my ($self, $n) = @_;
  substr($self->{input}, $self->{pos}) =~ /^.*\n(\ *)/
    or return 0;
  my $m = length($1) - $n;
  return 0 if $m < 0;
  return $m;
}
name 'auto_detect', \&auto_detect;

#------------------------------------------------------------------------------
# Trace debugging
#------------------------------------------------------------------------------
sub trace_start {
  '' || "$ENV{TRACE_START}";
}

sub trace_quiet {
  return [] if $ENV{DEBUG};
  [
    split(',', ($ENV{TRACE_QUIET} || '')),
#     'b_as_line_feed',
#     's_indent',
#     'nb_char',

    'c_directives_end',
    'c_l_folded',
    'c_l_literal',
    'c_ns_alias_node',
    'c_ns_anchor_property',
    'c_ns_tag_property',
    'l_directive_document',
    'l_document_prefix',
    'ns_flow_content',
    'ns_plain',
    's_l_comments',
    's_separate',
  ];
}

sub trace {
  my ($self, $type, $call, $args) = @_;
  $args //= [];

  $call = "'$call'" if $call =~ /^($| |.* $)/;
  return unless $self->{trace_on} or $call eq $self->trace_start;

  my $level = $self->state_curr->{lvl};
  my $indent = ' ' x $level;
  if ($level > 0) {
    my $l = length "$level";
    $indent = "$level" . substr($indent, $l);
  }

  my $input = substr($self->{input}, $self->{pos});
  $input = substr($input, 0, 30) . '…'
    if length($input) > 30;
  $input =~ s/\t/\\t/g;
  $input =~ s/\r/\\r/g;
  $input =~ s/\n/\\n/g;

  my $line = sprintf(
    "%s%s %-40s  %4d '%s'\n",
    $indent,
    $type,
    $self->trace_format_call($call, $args),
    $self->{pos},
    $input,
  );

  if ($ENV{DEBUG}) {
    warn sprintf "%6d %s",
      $self->{trace_num}, $line;
    return;
  }

  my $trace_info = undef;
  $level = "${level}_$call";
  if ($type eq '?' and not $self->{trace_off}) {
    $trace_info = [$type, $level, $line, $self->{trace_num}];
  }
  if (grep $_ eq $call, @{$self->trace_quiet}) {
    $self->{trace_off} += $type eq '?' ? 1 : -1;
  }
  if ($type ne '?' and not $self->{trace_off}) {
    $trace_info = [$type, $level, $line, $self->{trace_num}];
  }

  if (defined $trace_info) {
    my ($prev_type, $prev_level, $prev_line, $trace_num) =
      @{$self->{trace_info}};
    if ($prev_type eq '?' and $prev_level eq $level) {
      $trace_info->[1] = '';
      if ($line =~ /^\d*\ *\+/) {
        $prev_line =~ s/\?/=/;
      }
      else {
        $prev_line =~ s/\?/!/;
      }
    }
    if ($prev_level) {
      warn sprintf "%5d %6d %s",
        ++$self->{trace_line}, $trace_num, $prev_line;
    }

    $self->{trace_info} = $trace_info;
  }

  if ($call eq $self->trace_start) {
    $self->{trace_on} = not $self->{trace_on};
  }
}

sub trace_format_call {
  my ($self, $call, $args) = @_;
  return $call unless @$args;
  my $list = join ',', map stringify($_), @$args;
  return "$call($list)";
}

sub trace_flush {
  my ($self) = @_;
  my ($type, $level, $line, $count) = @{$self->{trace_info}};
  if (my $line = $self->{trace_info}[2]) {
    warn sprintf "%5d %6d %s",
      ++$self->{trace_line}, $count, $line;
  }
}

1;

# vim: sw=2:
