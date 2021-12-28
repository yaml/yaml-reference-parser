use v5.12;
package TestReceiver;
use base 'Receiver';
use YAML::PP::Common qw(
    YAML_PLAIN_SCALAR_STYLE
    YAML_SINGLE_QUOTED_SCALAR_STYLE YAML_DOUBLE_QUOTED_SCALAR_STYLE
    YAML_LITERAL_SCALAR_STYLE YAML_FOLDED_SCALAR_STYLE
);

use Prelude;

my $event_map = {
  stream_start_event => '+STR',
  stream_end_event => '-STR',
  document_start_event => '+DOC',
  document_end_event => '-DOC',
  mapping_start_event => '+MAP',
  mapping_end_event => '-MAP',
  sequence_start_event => '+SEQ',
  sequence_end_event => '-SEQ',
  scalar_event => '=VAL',
  alias_event => '=ALI',
};

my $style_map = {
  YAML_PLAIN_SCALAR_STYLE() => ':',
  YAML_SINGLE_QUOTED_SCALAR_STYLE() => "'",
  YAML_DOUBLE_QUOTED_SCALAR_STYLE() => '"',
  YAML_LITERAL_SCALAR_STYLE() => '|',
  YAML_FOLDED_SCALAR_STYLE() => '>',
};

sub output {
  my ($self) = @_;
  join '', map {
    my $type = $event_map->{$_->{event}};
    my @event = ($type);
    push @event, '---' if $type eq '+DOC' and $_->{explicit};
    push @event, '...' if $type eq '-DOC' and $_->{explicit};
    push @event, '{}' if $type eq '+MAP' and $_->{flow};
    push @event, '[]' if $type eq '+SEQ' and $_->{flow};
    push @event, "&$_->{anchor}" if $_->{anchor};
    push @event, "<$_->{tag}>" if $_->{tag};
    push @event, "*$_->{name}" if $_->{name};
    if (exists $_->{value}) {
      my $style = $style_map->{$_->{style}};
      my $value = $_->{value};
      $value =~ s/\\/\\\\/g;
      $value =~ s/\x08/\\b/g;
      $value =~ s/\t/\\t/g;
      $value =~ s/\n/\\n/g;
      $value =~ s/\r/\\r/g;
      push @event, "$style$value";
    }
    join(' ', @event) . "\n";
  } @{$self->{event}};
}

1;

# vim: sw=2:
